#import <Foundation/Foundation.h>
#include <poll.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

static NSError *QuotaQueryError(NSString *message) {
    return [NSError errorWithDomain:@"CodexUsageQuota" code:1
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *CodexExecutable(void) {
    NSArray *paths = @[
        @"/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        @"/Applications/Codex.app/Contents/Resources/codex",
        [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"],
        @"/opt/homebrew/bin/codex", @"/usr/local/bin/codex"
    ];
    for (NSString *path in paths) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

static BOOL SendQuotaMessage(int fd, NSDictionary *message) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    NSMutableData *line = [json mutableCopy];
    [line appendBytes:"\n" length:1];
    NSUInteger offset = 0;
    while (offset < line.length) {
        ssize_t count = write(fd, (const char *)line.bytes + offset, line.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return NO;
        offset += count;
    }
    return YES;
}

// A short-lived read-only app-server session. No threads or inference are started.
static NSDictionary *QueryCodexQuota(NSString *executable, NSTimeInterval timeout, NSError **errorOut) {
    if (!executable) {
        if (errorOut) *errorOut = QuotaQueryError(@"未找到 Codex，请安装或登录 Codex 后重试");
        return nil;
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = @[@"app-server", @"--listen", @"stdio://"];
    task.currentDirectoryURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    NSPipe *input = [NSPipe pipe], *output = [NSPipe pipe];
    task.standardInput = input;
    task.standardOutput = output;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil]) {
        if (errorOut) *errorOut = QuotaQueryError(@"无法启动 Codex 额度查询");
        return nil;
    }
    int inFD = input.fileHandleForWriting.fileDescriptor;
    int outFD = output.fileHandleForReading.fileDescriptor;
    fcntl(inFD, F_SETNOSIGPIPE, 1);
    fcntl(outFD, F_SETFL, fcntl(outFD, F_GETFL) | O_NONBLOCK);
    NSString *failure = @"额度查询超时，保留上次读数";
    NSDictionary *result = nil;
    @try {
        if (!SendQuotaMessage(inFD, @{@"id": @1, @"method": @"initialize", @"params": @{
            @"clientInfo": @{@"name": @"codex_usage_monitor", @"title": @"Codex Usage", @"version": @"0.1.12"}
        }})) {
            failure = @"Codex 额度查询连接已断开";
        } else {
            NSMutableData *pending = [NSMutableData data];
            NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + timeout;
            BOOL finished = NO, initialized = NO;
            while (!finished && NSProcessInfo.processInfo.systemUptime < deadline) {
                struct pollfd descriptor = {outFD, POLLIN, 0};
                int waitMS = (int)MIN(250, MAX(1, (deadline - NSProcessInfo.processInfo.systemUptime) * 1000));
                int ready = poll(&descriptor, 1, waitMS);
                if (ready < 0 && errno == EINTR) continue;
                if (ready < 0) break;
                if (!ready) continue;
                char bytes[8192];
                ssize_t count = read(outFD, bytes, sizeof(bytes));
                if (count < 0 && (errno == EAGAIN || errno == EINTR)) continue;
                if (count <= 0) { failure = @"Codex 额度查询连接已断开"; break; }
                [pending appendBytes:bytes length:count];
                if (pending.length > 1024 * 1024) { failure = @"额度查询响应异常"; break; }
                while (pending.length) {
                    const char *newline = memchr(pending.bytes, '\n', pending.length);
                    if (!newline) break;
                    NSUInteger length = newline - (const char *)pending.bytes;
                    NSData *line = [pending subdataWithRange:NSMakeRange(0, length)];
                    [pending replaceBytesInRange:NSMakeRange(0, length + 1) withBytes:NULL length:0];
                    id decoded = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
                    if (![decoded isKindOfClass:NSDictionary.class]) continue;
                    NSDictionary *message = decoded;
                    if ([message[@"id"] isEqual:@1] && !initialized) {
                        if (message[@"error"] || ![message[@"result"] isKindOfClass:NSDictionary.class]) {
                            failure = @"Codex 初始化失败，请更新 Codex 后重试"; finished = YES; break;
                        }
                        initialized = YES;
                        if (!SendQuotaMessage(inFD, @{@"method": @"initialized"}) ||
                            !SendQuotaMessage(inFD, @{@"id": @2, @"method": @"account/rateLimits/read"})) {
                            failure = @"Codex 额度查询连接已断开"; finished = YES; break;
                        }
                    } else if (initialized && [message[@"id"] isEqual:@2]) {
                        result = [message[@"result"] isKindOfClass:NSDictionary.class] ? message[@"result"] : nil;
                        failure = @"额度查询失败，请检查网络或 Codex 登录状态";
                        finished = YES;
                        break;
                    }
                }
            }
        }
    } @finally {
        [input.fileHandleForWriting closeFile];
        if (task.running) [task terminate];
        NSTimeInterval stop = NSProcessInfo.processInfo.systemUptime + 0.3;
        while (task.running && NSProcessInfo.processInfo.systemUptime < stop) usleep(10000);
        if (task.running) kill(task.processIdentifier, SIGKILL);
        [task waitUntilExit];
        [output.fileHandleForReading closeFile];
    }
    if (!result && errorOut) *errorOut = QuotaQueryError(failure);
    return result;
}

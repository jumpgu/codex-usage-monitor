#define main CodexUsageApplicationMain
#import "../Sources/ObjC/CodexUsageMonitor.m"
#undef main
#include <assert.h>
int main(void) {
    @autoreleasepool {
        NSDate *now = [NSDate date];
        NSDictionary *weekly = @{@"usedPercent": @23, @"windowMinutes": @10080, @"resetsAt": LocalISOString([now dateByAddingTimeInterval:3600])};
        assert([WindowTitle(weekly) isEqual:@"7 天"]);
        assert([RemainingPercentText(weekly[@"usedPercent"]) isEqual:@"77%"]);
        assert([WindowTitle(@{@"windowMinutes": @300}) isEqual:@"5 小时"]);
        NSDictionary *expired = @{@"usedPercent": @90, @"windowMinutes": @300, @"resetsAt": LocalISOString([now dateByAddingTimeInterval:-3600])};
        NSDictionary *normalized = NormalizeLimitDictionary(@{@"primary": weekly, @"secondary": expired}, now);
        assert([normalized[@"primary"] isEqual:weekly]);
        assert(normalized[@"secondary"][@"usedPercent"] == NSNull.null);
        assert([normalized[@"secondary"][@"resetsAt"] isEqual:expired[@"resetsAt"]]);
        assert(LimitDictionary(@{@"limit_id": @"other"}) == nil);
        assert(LimitDictionary(@{@"primary": NSNull.null}) != nil);
        assert(ShouldDisplaySecondaryInStatus(nil, weekly));

        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [NSFileManager.defaultManager createDirectoryAtPath:[root stringByAppendingPathComponent:@"sessions"] withIntermediateDirectories:YES attributes:nil error:nil];
        setenv("CODEX_HOME", root.UTF8String, 1);
        NSString *file = [SessionsRoot() stringByAppendingPathComponent:@"fixture.jsonl"];
        NSDictionary *info = @{@"last_token_usage": @{@"total_tokens": @100, @"input_tokens": @80, @"output_tokens": @20}, @"total_token_usage": @{@"total_tokens": @100}};
        NSDictionary *event = @{@"timestamp": LocalISOString(now), @"payload": @{@"type": @"token_count", @"info": info, @"rate_limits": @{@"limit_id": @"codex", @"primary": @{@"used_percent": @23, @"window_minutes": @10080, @"resets_at": @([now timeIntervalSince1970]+3600)}}}};
        NSString *json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:event options:0 error:nil] encoding:NSUTF8StringEncoding];
        NSString *lines = [NSString stringWithFormat:@"%@\n%@\n{partial", json, json];
        [lines writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSError *error = nil;
        NSDictionary *summary = CollectUsage(&error);
        assert(summary && !error);
        assert([summary[@"usage"][@"allTime"][@"totalTokens"] longLongValue] == 100);
        assert([summary[@"usage"][@"allTime"][@"events"] longLongValue] == 1);
        assert([WindowTitle(PrimaryLimit(summary)) isEqual:@"7 天"]);
        NSArray *cached = TokenEventsInFile(file);
        assert(cached == TokenEventsInFile(file));
        [@"{bad}\n" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
        assert(TokenEventsInFile(file).count == 0);
        [NSFileManager.defaultManager removeItemAtPath:file error:nil];
        assert(TokenEventsInFile(file).count == 0);
        summary = CollectUsage(&error);
        assert([summary[@"source"][@"filesScanned"] intValue] == 0);
        assert(TokenEventCache().count == 0);
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
        puts("PASS: weekly window, expired limits, legacy schema, duplicate events, cache invalidation, partial/malformed lines, removed files");
    }
}

#define CODEX_USAGE_TESTING 1
#define main CodexUsageApplicationMain
#import "../Sources/ObjC/CodexUsageMonitor.m"
#undef main
#include <assert.h>
@interface TestDiskDelegate : CodexUsageAppDelegate
@property(nonatomic, assign) NSInteger diskReadCount;
@end
@implementation TestDiskDelegate
- (NSDictionary *)readDiskSnapshot:(NSError **)error {
    self.diskReadCount += 1;
    return @{@"total": @1000000000000LL, @"available": @500000000000LL, @"observedAt": NSDate.date};
}
@end

@interface TestPopover : NSPopover
@property(nonatomic, assign) BOOL testShown;
@end
@implementation TestPopover
- (BOOL)isShown { return self.testShown; }
- (void)close {
    self.testShown = NO;
    [self.delegate popoverDidClose:[NSNotification notificationWithName:NSPopoverDidCloseNotification object:self]];
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [MonitorPreferences() removePersistentDomainForName:@"com.gukai.CodexUsage.tests"];
        CodexUsageAppDelegate *settings = [[CodexUsageAppDelegate alloc] init];
        settings.showWindowOnLaunch = YES;
        NSButton *checkbox = [settings diskPreferenceButton];
        assert(checkbox.state == NSControlStateValueOff);
        [checkbox performClick:nil];
        assert([MonitorPreferences() boolForKey:DiskMonitoringPreference]);
        assert([settings diskPreferenceButton].state == NSControlStateValueOn);
        [settings disableDiskMonitoring:nil];
        assert(![MonitorPreferences() boolForKey:DiskMonitoringPreference]);
        [MonitorPreferences() removePersistentDomainForName:@"com.gukai.CodexUsage.tests"];
        [MonitorPreferences() synchronize];
        NSError *capacityError = nil;
        NSDictionary *actualDisk = ReadDiskSnapshot([NSURL fileURLWithPath:NSHomeDirectory()], &capacityError);
        assert(actualDisk && !capacityError && [actualDisk[@"total"] longLongValue] > 0);
        NSRect panel = NSMakeRect(-300, 200, 250, 300);
        NSRect anchor = NSMakeRect(-200, 520, 100, 24);
        assert(!ShouldDismissPopoverClick(NSMakePoint(-150, 350), panel, anchor));
        assert(!ShouldDismissPopoverClick(NSMakePoint(-150, 530), panel, anchor));
        assert(ShouldDismissPopoverClick(NSMakePoint(10, 10), panel, anchor));
        assert(ShouldDismissPopoverClick(NSMakePoint(-400, 300), panel, anchor));
        CodexUsageAppDelegate *popup = [[CodexUsageAppDelegate alloc] init];
        TestPopover *popover = [[TestPopover alloc] init];
        popover.delegate = popup;
        popover.testShown = YES;
        popup.popover = popover;
        [popup startPopoverEventMonitors];
        assert(popup.localPopoverMonitor != nil);
        [popup applicationDidResignActive:[NSNotification notificationWithName:NSApplicationDidResignActiveNotification object:NSApp]];
        assert(!popover.shown && !popup.localPopoverMonitor && !popup.globalPopoverMonitor);
        popover.testShown = YES;
        [popup startPopoverEventMonitors];
        [popup startPopoverEventMonitors];
        [popup closePopover];
        [popup closePopover];
        assert(!popover.shown && !popup.localPopoverMonitor && !popup.globalPopoverMonitor);
        popup.diskMonitoringEnabled = YES;
        popup.diskSnapshot = @{@"total": @1000000000000LL, @"available": @500000000000LL, @"observedAt": NSDate.date, @"name": @"test"};
        popup.diskStatusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
        [popup updateDiskDisplay];
        NSMenu *diskMenu = popup.diskStatusItem.menu;
        NSInteger itemCount = diskMenu.numberOfItems;
        [popup menuWillOpen:diskMenu];
        assert(popup.diskMenuTracking);
        [popup updateDiskDisplay];
        assert(popup.diskStatusItem.menu == diskMenu && diskMenu.numberOfItems == itemCount);
        [popup menuDidClose:diskMenu];
        assert(!popup.diskMenuTracking);
        [popup updateDiskDisplay];
        assert(popup.diskStatusItem.menu == diskMenu);
        [popup setDiskMonitoringActive:NO];
        NSDate *now = [NSDate date];
        assert(!DataIsStale([now dateByAddingTimeInterval:-179], now));
        assert(DataIsStale([now dateByAddingTimeInterval:-180], now));
        assert(DataIsStale(nil, now));
        assert([DiskCapacityText(128000000000LL) isEqual:@"128 GB"]);
        assert(DiskWarningLevel(@{@"total": @1000000000000LL, @"available": @5000000000LL}) == 2);
        assert(DiskWarningLevel(@{@"total": @1000000000000LL, @"available": @90000000000LL}) == 1);
        assert(DiskWarningLevel(@{@"total": @1000000000000LL, @"available": @500000000000LL}) == 0);
        TestDiskDelegate *monitor = [[TestDiskDelegate alloc] init];
        [monitor refreshDisk:nil];
        assert(!monitor.diskRefreshing && monitor.diskReadCount == 0 && monitor.diskSnapshot == nil);
        monitor.diskMonitoringEnabled = YES;
        monitor.diskGeneration = 1;
        monitor.diskTimer = [NSTimer timerWithTimeInterval:60 target:monitor selector:@selector(refreshDisk:) userInfo:nil repeats:YES];
        [monitor refreshDisk:nil];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (monitor.diskRefreshing && [deadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        assert(monitor.diskReadCount == 1 && monitor.diskSnapshot != nil && !monitor.diskRefreshing);
        NSTimer *oldTimer = monitor.diskTimer;
        NSDictionary *snapshot = monitor.diskSnapshot;
        [monitor setDiskMonitoringActive:NO];
        assert(!oldTimer.valid && monitor.diskTimer == nil && monitor.diskSnapshot == nil);
        assert(![monitor acceptDiskSnapshot:snapshot error:nil generation:1]);
        [monitor refreshDisk:nil];
        assert(monitor.diskReadCount == 1 && monitor.diskSnapshot == nil);
        monitor.diskMonitoringEnabled = YES;
        monitor.diskGeneration = 3;
        assert(![monitor acceptDiskSnapshot:snapshot error:nil generation:1]);
        assert([monitor acceptDiskSnapshot:snapshot error:nil generation:3]);
        NSError *diskError = [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"read failed"}];
        assert([monitor acceptDiskSnapshot:nil error:diskError generation:3]);
        assert(monitor.diskSnapshot == snapshot && [monitor.diskError isEqual:@"read failed"]);
        monitor.summary = @{@"updatedAt": LocalISOString(now), @"source": @{@"limitsObservedAt": LocalISOString([now dateByAddingTimeInterval:-181])}};
        assert([monitor codexDataIsStale]); // A fresh scan must not make an old quota snapshot fresh.
        monitor.summary = @{@"updatedAt": LocalISOString(now), @"source": @{@"limitsObservedAt": LocalISOString(now)}};
        assert(![monitor codexDataIsStale]);
        monitor.lastErrorMessage = @"read failed";
        assert([monitor codexDataIsStale]);
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
        puts("PASS: popup outside-click geometry, app-switch close, monitor cleanup, stable disk menu, disk opt-in/no disabled reads, timer cancellation, in-flight result rejection, failed reads, 180-second freshness, weekly window, expired limits, duplicate events, cache invalidation, malformed logs");
    }
}

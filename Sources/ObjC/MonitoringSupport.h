// Local-only helpers shared by the menu bar app and its regression tests.
static const NSTimeInterval StaleDataInterval = 180;
static NSString * const DiskMonitoringPreference = @"diskMonitoringEnabled";
static NSString * const PreferencesChangedNotification = @"com.gukai.CodexUsage.preferencesChanged";

static BOOL DataIsStale(NSDate *observedAt, NSDate *now) {
    return !observedAt || [now timeIntervalSinceDate:observedAt] >= StaleDataInterval;
}

static NSUserDefaults *MonitorPreferences(void) {
    static NSUserDefaults *preferences;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
#ifdef CODEX_USAGE_TESTING
        preferences = [[NSUserDefaults alloc] initWithSuiteName:@"com.gukai.CodexUsage.tests"];
#else
        preferences = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.gukai.CodexUsage"]
            ? NSUserDefaults.standardUserDefaults
            : [[NSUserDefaults alloc] initWithSuiteName:@"com.gukai.CodexUsage"];
#endif
    });
    return preferences;
}

static NSString *DiskCapacityText(long long bytes) {
    double gb = MAX(0, bytes) / 1000000000.0;
    if (gb >= 1000) return [NSString stringWithFormat:@"%.2f TB", gb / 1000];
    if (gb >= 100) return [NSString stringWithFormat:@"%.0f GB", gb];
    return [NSString stringWithFormat:@"%.1f GB", gb];
}

// APFS available capacity can include space macOS can reclaim. This does not scan files.
static NSDictionary *ReadDiskSnapshot(NSURL *url, NSError **error) {
    NSArray *keys = @[NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityForImportantUsageKey,
                      NSURLVolumeAvailableCapacityKey, NSURLVolumeNameKey];
    NSDictionary *values = [url resourceValuesForKeys:keys error:error];
    NSNumber *total = values[NSURLVolumeTotalCapacityKey];
    NSNumber *important = values[NSURLVolumeAvailableCapacityForImportantUsageKey];
    NSNumber *available = important ?: values[NSURLVolumeAvailableCapacityKey];
    if (!total || !available || total.longLongValue <= 0 || available.longLongValue < 0) {
        if (error && !*error) *error = [NSError errorWithDomain:@"CodexUsage.Disk" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"无法读取磁盘容量"}];
        return nil;
    }
    return @{@"total": total, @"available": @(MIN(total.longLongValue, available.longLongValue)),
             @"includesPurgeable": @(important != nil), @"name": values[NSURLVolumeNameKey] ?: @"系统磁盘",
             @"observedAt": [NSDate date]};
}

static NSInteger DiskWarningLevel(NSDictionary *snapshot) {
    if (!snapshot) return 0;
    double available = [snapshot[@"available"] doubleValue];
    double total = [snapshot[@"total"] doubleValue];
    if (total <= 0) return 0;
    if (available <= 5000000000.0 || available / total <= 0.05) return 2;
    if (available <= 10000000000.0 || available / total <= 0.10) return 1;
    return 0;
}

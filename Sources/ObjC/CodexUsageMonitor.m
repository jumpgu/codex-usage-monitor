#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

typedef struct {
    long long events;
    long long inputTokens;
    long long cachedInputTokens;
    long long outputTokens;
    long long reasoningOutputTokens;
    long long totalTokens;
} UsageBucket;

static NSString * const CodexUsageSummaryRelativePath = @"Library/Application Support/CodexUsage/usage_summary.json";
static NSString * const CodexUsageSessionRelativePath = @".codex/sessions";
static NSString * const CodexUsageArchivedSessionRelativePath = @".codex/archived_sessions";

static NSString *HomePath(void) {
    return NSHomeDirectory();
}

static NSString *SummaryPath(void) {
    return [HomePath() stringByAppendingPathComponent:CodexUsageSummaryRelativePath];
}

static NSString *WidgetContainerSummaryPath(void) {
    return [HomePath() stringByAppendingPathComponent:@"Library/Containers/com.gukai.CodexUsage.widgets/Data/Library/Application Support/CodexUsage/usage_summary.json"];
}

static NSString *SessionsRoot(void) {
    return [HomePath() stringByAppendingPathComponent:CodexUsageSessionRelativePath];
}

static NSString *ArchivedSessionsRoot(void) {
    return [HomePath() stringByAppendingPathComponent:CodexUsageArchivedSessionRelativePath];
}

static id NullSafe(id value) {
    return value ?: [NSNull null];
}

static NSString *AbbreviateHome(NSString *path) {
    NSString *home = HomePath();
    if ([path isEqualToString:home]) {
        return @"~";
    }
    NSString *prefix = [home stringByAppendingString:@"/"];
    if ([path hasPrefix:prefix]) {
        return [@"~/" stringByAppendingString:[path substringFromIndex:prefix.length]];
    }
    return path;
}

static NSDate *CodexDateFromString(NSString *value) {
    static NSISO8601DateFormatter *fractionalFormatter;
    static NSISO8601DateFormatter *plainFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fractionalFormatter = [[NSISO8601DateFormatter alloc] init];
        fractionalFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        plainFormatter = [[NSISO8601DateFormatter alloc] init];
        plainFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });

    return [fractionalFormatter dateFromString:value] ?: [plainFormatter dateFromString:value];
}

static NSString *LocalISOString(NSDate *date) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssXXXXX";
    });
    return [formatter stringFromDate:date];
}

static NSString *ResetDisplay(NSString *isoString) {
    if (![isoString isKindOfClass:NSString.class]) {
        return @"--";
    }

    NSDate *date = CodexDateFromString(isoString);
    if (!date) {
        static NSDateFormatter *localParser;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            localParser = [[NSDateFormatter alloc] init];
            localParser.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
            localParser.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            localParser.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
            localParser.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssXXXXX";
        });
        date = [localParser dateFromString:isoString];
    }
    if (!date) {
        return @"--";
    }

    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.timeZone = calendar.timeZone;
    formatter.dateFormat = [calendar isDateInToday:date] ? @"HH:mm" : @"M/d HH:mm";
    return [formatter stringFromDate:date];
}

static long long LongLongValue(id value) {
    if ([value respondsToSelector:@selector(longLongValue)]) {
        return [value longLongValue];
    }
    return 0;
}

static double DoubleValue(id value) {
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return [value doubleValue];
    }
    return 0;
}

static NSNumber *NumberOrNil(id value) {
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

static NSString *StringOrNil(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static void AddUsage(UsageBucket *bucket, NSDictionary *usage) {
    bucket->events += 1;
    bucket->inputTokens += LongLongValue(usage[@"input_tokens"]);
    bucket->cachedInputTokens += LongLongValue(usage[@"cached_input_tokens"]);
    bucket->outputTokens += LongLongValue(usage[@"output_tokens"]);
    bucket->reasoningOutputTokens += LongLongValue(usage[@"reasoning_output_tokens"]);
    bucket->totalTokens += LongLongValue(usage[@"total_tokens"]);
}

static NSDictionary *BucketDictionary(UsageBucket bucket) {
    long long nonCached = bucket.totalTokens - bucket.cachedInputTokens;
    if (nonCached < 0) {
        nonCached = 0;
    }
    return @{
        @"events": @(bucket.events),
        @"inputTokens": @(bucket.inputTokens),
        @"cachedInputTokens": @(bucket.cachedInputTokens),
        @"outputTokens": @(bucket.outputTokens),
        @"reasoningOutputTokens": @(bucket.reasoningOutputTokens),
        @"totalTokens": @(bucket.totalTokens),
        @"nonCachedApproxTokens": @(nonCached)
    };
}

static NSString *PercentText(id value) {
    NSNumber *number = NumberOrNil(value);
    if (!number) {
        return @"--";
    }
    return [NSString stringWithFormat:@"%.0f%%", number.doubleValue];
}

static NSString *RemainingPercentText(id usedValue) {
    NSNumber *number = NumberOrNil(usedValue);
    if (!number) {
        return @"--";
    }
    double remaining = 100.0 - number.doubleValue;
    if (remaining < 0) {
        remaining = 0;
    }
    if (remaining > 100) {
        remaining = 100;
    }
    return [NSString stringWithFormat:@"%.0f%%", remaining];
}

static NSString *YiTokens(long long tokens, NSInteger digits) {
    double value = (double)tokens / 100000000.0;
    return [NSString stringWithFormat:@"%.*f 亿", (int)digits, value];
}

static BOOL BytesContainNeedle(const uint8_t *bytes, NSUInteger start, NSUInteger end, const char *needle, NSUInteger needleLength) {
    if (end <= start || end - start < needleLength) {
        return NO;
    }

    NSUInteger maxStart = end - needleLength;
    for (NSUInteger i = start; i <= maxStart; i++) {
        if (bytes[i] != (uint8_t)needle[0]) {
            continue;
        }
        BOOL matched = YES;
        for (NSUInteger offset = 1; offset < needleLength; offset++) {
            if (bytes[i + offset] != (uint8_t)needle[offset]) {
                matched = NO;
                break;
            }
        }
        if (matched) {
            return YES;
        }
    }
    return NO;
}

static NSDictionary *RateWindowDictionary(NSDictionary *window) {
    if (![window isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSNumber *used = NumberOrNil(window[@"used_percent"]);
    NSNumber *minutes = NumberOrNil(window[@"window_minutes"]);
    if (!used || !minutes) {
        return nil;
    }

    NSString *resetsAt = nil;
    NSNumber *epoch = NumberOrNil(window[@"resets_at"]);
    if (epoch) {
        resetsAt = LocalISOString([NSDate dateWithTimeIntervalSince1970:epoch.doubleValue]);
    }

    return @{
        @"usedPercent": used,
        @"windowMinutes": minutes,
        @"resetsAt": NullSafe(resetsAt)
    };
}

static NSDate *NextLocalWindowReset(NSDate *now, NSNumber *windowMinutes) {
    NSInteger minutes = windowMinutes.integerValue > 0 ? windowMinutes.integerValue : 300;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];

    NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour)
                                               fromDate:now];
    components.minute = 0;
    components.second = 0;
    components.nanosecond = 0;
    NSDate *hourStart = [calendar dateFromComponents:components];
    return [calendar dateByAddingUnit:NSCalendarUnitMinute value:minutes toDate:hourStart options:0];
}

static NSDictionary *NormalizeLimitDictionary(NSDictionary *limits, NSDate *now) {
    if (![limits isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSDictionary *primary = [limits[@"primary"] isKindOfClass:NSDictionary.class] ? limits[@"primary"] : nil;
    NSString *resetsAt = StringOrNil(primary[@"resetsAt"]);
    NSDate *resetDate = resetsAt ? CodexDateFromString(resetsAt) : nil;
    if (!primary || !resetDate || [resetDate compare:now] == NSOrderedDescending) {
        return limits;
    }

    NSMutableDictionary *normalized = [limits mutableCopy];
    NSMutableDictionary *normalizedPrimary = [primary mutableCopy];
    NSNumber *windowMinutes = NumberOrNil(primary[@"windowMinutes"]) ?: @300;
    normalizedPrimary[@"usedPercent"] = @0;
    normalizedPrimary[@"resetsAt"] = LocalISOString(NextLocalWindowReset(now, windowMinutes));
    normalizedPrimary[@"windowMinutes"] = windowMinutes;
    normalized[@"primary"] = normalizedPrimary;
    return normalized;
}

static NSDictionary *LimitDictionary(NSDictionary *rateLimits) {
    if (![rateLimits isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    if (![StringOrNil(rateLimits[@"limit_id"]) isEqualToString:@"codex"] || !StringOrNil(rateLimits[@"plan_type"])) {
        return nil;
    }

    NSDictionary *primary = RateWindowDictionary(rateLimits[@"primary"]);
    NSDictionary *secondary = RateWindowDictionary(rateLimits[@"secondary"]);
    NSString *planType = StringOrNil(rateLimits[@"plan_type"]);
    NSString *reachedType = StringOrNil(rateLimits[@"rate_limit_reached_type"]);

    return @{
        @"planType": NullSafe(planType),
        @"primary": NullSafe(primary),
        @"secondary": NullSafe(secondary),
        @"rateLimitReachedType": NullSafe(reachedType)
    };
}

static NSArray<NSString *> *JSONLFilesUnderRoot(NSString *root) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:root isDirectory:&isDirectory] || !isDirectory) {
        return @[];
    }

    NSURL *rootURL = [NSURL fileURLWithPath:root isDirectory:YES];
    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:rootURL
                                                   includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:nil];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        if (![url.pathExtension isEqualToString:@"jsonl"]) {
            continue;
        }
        NSNumber *isRegular = nil;
        [url getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
        if (isRegular.boolValue) {
            [files addObject:url.path];
        }
    }

    return [files sortedArrayUsingSelector:@selector(compare:)];
}

static NSDictionary *CollectUsage(NSError **errorOut) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *sessionsRoot = SessionsRoot();
    NSString *archivedRoot = ArchivedSessionsRoot();

    if (![fileManager fileExistsAtPath:sessionsRoot] && ![fileManager fileExistsAtPath:archivedRoot]) {
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:@"CodexUsage"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"No Codex session directory was found under ~/.codex."}];
        }
        return nil;
    }

    NSMutableArray<NSString *> *files = [NSMutableArray array];
    [files addObjectsFromArray:JSONLFilesUnderRoot(sessionsRoot)];
    [files addObjectsFromArray:JSONLFilesUnderRoot(archivedRoot)];

    NSDate *now = [NSDate date];
    NSDate *fiveHoursAgo = [now dateByAddingTimeInterval:-5 * 60 * 60];
    NSDate *sevenDaysAgo = [now dateByAddingTimeInterval:-7 * 24 * 60 * 60];
    NSCalendar *shanghaiCalendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    shanghaiCalendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSDate *todayStart = [shanghaiCalendar startOfDayForDate:now];

    UsageBucket last5h = {0};
    UsageBucket today = {0};
    UsageBucket last7d = {0};
    UsageBucket allTime = {0};

    NSInteger sessionsWithUsage = 0;
    NSDate *firstEventAt = nil;
    NSDate *lastEventAt = nil;
    NSDate *latestLimitAt = nil;
    NSDictionary *latestLimits = nil;
    const char *needle = "\"token_count\"";
    NSUInteger needleLength = strlen(needle);

    for (NSString *file in files) {
        NSData *data = [NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:nil];
        if (!data.length) {
            continue;
        }

        BOOL fileHasUsage = NO;
        const uint8_t *bytes = data.bytes;
        NSUInteger length = data.length;
        NSUInteger lineStart = 0;

        for (NSUInteger index = 0; index <= length; index++) {
            if (index != length && bytes[index] != '\n') {
                continue;
            }

            NSUInteger lineEnd = index;
            if (lineEnd > lineStart && BytesContainNeedle(bytes, lineStart, lineEnd, needle, needleLength)) {
                NSData *lineData = [NSData dataWithBytes:bytes + lineStart length:lineEnd - lineStart];
                NSDictionary *object = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
                NSDictionary *payload = [object isKindOfClass:NSDictionary.class] ? object[@"payload"] : nil;
                if ([payload isKindOfClass:NSDictionary.class] && [payload[@"type"] isEqualToString:@"token_count"]) {
                    NSDate *timestamp = CodexDateFromString(StringOrNil(object[@"timestamp"]));
                    if (timestamp) {
                        firstEventAt = firstEventAt ? [firstEventAt earlierDate:timestamp] : timestamp;
                        lastEventAt = lastEventAt ? [lastEventAt laterDate:timestamp] : timestamp;
                    }

                    NSDictionary *limits = LimitDictionary(payload[@"rate_limits"]);
                    if (timestamp && limits && (!latestLimitAt || [timestamp compare:latestLimitAt] != NSOrderedAscending)) {
                        latestLimitAt = timestamp;
                        latestLimits = limits;
                    }

                    NSDictionary *info = [payload[@"info"] isKindOfClass:NSDictionary.class] ? payload[@"info"] : nil;
                    NSDictionary *usage = [info[@"last_token_usage"] isKindOfClass:NSDictionary.class] ? info[@"last_token_usage"] : nil;
                    if (timestamp && usage && NumberOrNil(usage[@"total_tokens"])) {
                        fileHasUsage = YES;
                        AddUsage(&allTime, usage);
                        if ([timestamp compare:fiveHoursAgo] != NSOrderedAscending) {
                            AddUsage(&last5h, usage);
                        }
                        if ([timestamp compare:todayStart] != NSOrderedAscending) {
                            AddUsage(&today, usage);
                        }
                        if ([timestamp compare:sevenDaysAgo] != NSOrderedAscending) {
                            AddUsage(&last7d, usage);
                        }
                    }
                }
            }

            lineStart = index + 1;
        }

        if (fileHasUsage) {
            sessionsWithUsage += 1;
        }
    }

    return @{
        @"version": @1,
        @"updatedAt": LocalISOString(now),
        @"source": @{
            @"sessionsRoot": AbbreviateHome(sessionsRoot),
            @"archivedSessionsRoot": AbbreviateHome(archivedRoot),
            @"filesScanned": @(files.count),
            @"sessionsWithUsage": @(sessionsWithUsage),
            @"firstEventAt": NullSafe(firstEventAt ? LocalISOString(firstEventAt) : nil),
            @"lastEventAt": NullSafe(lastEventAt ? LocalISOString(lastEventAt) : nil)
        },
        @"limits": NormalizeLimitDictionary(latestLimits, now) ?: @{
            @"planType": [NSNull null],
            @"primary": [NSNull null],
            @"secondary": [NSNull null],
            @"rateLimitReachedType": [NSNull null]
        },
        @"usage": @{
            @"last5h": BucketDictionary(last5h),
            @"today": BucketDictionary(today),
            @"last7d": BucketDictionary(last7d),
            @"allTime": BucketDictionary(allTime)
        }
    };
}

static BOOL SaveSummary(NSDictionary *summary, NSError **errorOut) {
    NSJSONWritingOptions options = NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys;
    if (@available(macOS 10.13, *)) {
        options |= NSJSONWritingWithoutEscapingSlashes;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:summary options:options error:errorOut];
    if (!data) {
        return NO;
    }

    NSArray<NSString *> *paths = @[SummaryPath(), WidgetContainerSummaryPath()];
    BOOL wrote = NO;
    NSError *lastError = nil;
    for (NSString *path in paths) {
        NSString *directory = path.stringByDeletingLastPathComponent;
        if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&lastError]) {
            continue;
        }
        if ([data writeToFile:path options:NSDataWritingAtomic error:&lastError]) {
            wrote = YES;
        }
    }

    if (!wrote && errorOut) {
        *errorOut = lastError ?: [NSError errorWithDomain:@"CodexUsage"
                                                     code:2
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to write usage summary."}];
    }
    return wrote;
}

static NSDictionary *LoadSummary(void) {
    NSData *data = [NSData dataWithContentsOfFile:SummaryPath()];
    if (!data) {
        return nil;
    }
    NSDictionary *summary = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [summary isKindOfClass:NSDictionary.class] ? summary : nil;
}

static NSDictionary *CollectAndSave(NSError **errorOut) {
    NSDictionary *summary = CollectUsage(errorOut);
    if (!summary) {
        return nil;
    }
    if (!SaveSummary(summary, errorOut)) {
        return nil;
    }
    return summary;
}

static NSDictionary *UsageBucketDict(NSDictionary *summary, NSString *key) {
    NSDictionary *usage = [summary[@"usage"] isKindOfClass:NSDictionary.class] ? summary[@"usage"] : nil;
    NSDictionary *bucket = [usage[key] isKindOfClass:NSDictionary.class] ? usage[key] : nil;
    return bucket ?: @{};
}

static NSDictionary *PrimaryLimit(NSDictionary *summary) {
    NSDictionary *limits = [summary[@"limits"] isKindOfClass:NSDictionary.class] ? summary[@"limits"] : nil;
    NSDictionary *primary = [limits[@"primary"] isKindOfClass:NSDictionary.class] ? limits[@"primary"] : nil;
    return primary;
}

static NSDictionary *SecondaryLimit(NSDictionary *summary) {
    NSDictionary *limits = [summary[@"limits"] isKindOfClass:NSDictionary.class] ? summary[@"limits"] : nil;
    NSDictionary *secondary = [limits[@"secondary"] isKindOfClass:NSDictionary.class] ? limits[@"secondary"] : nil;
    return secondary;
}

static NSColor *ColorForPercent(NSNumber *percent) {
    if (!percent) {
        return NSColor.secondaryLabelColor;
    }
    double value = percent.doubleValue;
    if (value < 50) {
        return NSColor.systemGreenColor;
    }
    if (value < 80) {
        return NSColor.systemYellowColor;
    }
    if (value < 95) {
        return NSColor.systemOrangeColor;
    }
    return NSColor.systemRedColor;
}

static NSString *BucketLine(NSString *title, NSDictionary *bucket) {
    long long total = LongLongValue(bucket[@"totalTokens"]);
    long long nonCached = LongLongValue(bucket[@"nonCachedApproxTokens"]);
    return [NSString stringWithFormat:@"%@: %@ total / %@ non-cache", title, YiTokens(total, 2), YiTokens(nonCached, 3)];
}

@interface CodexUsageAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *windowTitleLabel;
@property(nonatomic, strong) NSTextField *windowLimitLabel;
@property(nonatomic, strong) NSTextField *windowUsageLabel;
@property(nonatomic, strong) NSTextField *windowUpdatedLabel;
@property(nonatomic, strong) NSDictionary *summary;
@property(nonatomic, strong) NSDate *launchDate;
@property(nonatomic, assign) BOOL refreshing;
@property(nonatomic, assign) BOOL showWindowOnLaunch;
@end

@implementation CodexUsageAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.launchDate = [NSDate date];
    if (!self.showWindowOnLaunch) {
        self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
        if ([self.statusItem respondsToSelector:@selector(setAutosaveName:)]) {
            self.statusItem.autosaveName = @"com.gukai.CodexUsage.status";
        }
        self.statusItem.button.title = @"Codex --";
        self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"speedometer" accessibilityDescription:@"Codex Usage"];
        self.statusItem.button.imagePosition = NSImageLeft;
    }
    self.summary = LoadSummary();
    [self rebuildMenu];
    [self updateWindowContent];
    [self refresh:nil];
    if (!self.showWindowOnLaunch) {
        [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
    }

    if (self.showWindowOnLaunch) {
        [self showWindow:nil];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (self.showWindowOnLaunch) {
        return;
    }
    if ([[NSDate date] timeIntervalSinceDate:self.launchDate] < 1.5) {
        return;
    }
    if (!self.window.visible) {
        [self showWindow:nil];
    }
}

- (void)refresh:(id)sender {
    if (self.refreshing) {
        return;
    }

    self.refreshing = YES;
    self.statusItem.button.title = @"Codex ...";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSDictionary *summary = CollectAndSave(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.refreshing = NO;
            if (summary) {
                self.summary = summary;
            } else if (error) {
                if (self.statusItem) {
                    NSMenu *menu = self.statusItem.menu ?: [[NSMenu alloc] init];
                    [menu addItem:[NSMenuItem separatorItem]];
                    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:error.localizedDescription action:nil keyEquivalent:@""];
                    [menu addItem:item];
                    self.statusItem.menu = menu;
                }
            }
            [self rebuildMenu];
            [self updateWindowContent];
        });
    });
}

- (void)rebuildMenu {
    if (!self.statusItem) {
        return;
    }

    NSDictionary *primary = PrimaryLimit(self.summary);
    NSDictionary *secondary = SecondaryLimit(self.summary);
    NSNumber *primaryPercent = NumberOrNil(primary[@"usedPercent"]);
    self.statusItem.button.title = [NSString stringWithFormat:@"Codex %@ left", RemainingPercentText(primaryPercent)];
    self.statusItem.button.contentTintColor = ColorForPercent(primaryPercent);

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Codex Usage"];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Codex Usage" action:nil keyEquivalent:@""]];
    [menu addItem:[NSMenuItem separatorItem]];

    if (self.summary) {
        NSString *five = [NSString stringWithFormat:@"5h left: %@ (used %@), reset %@",
                          RemainingPercentText(primary[@"usedPercent"]),
                          PercentText(primary[@"usedPercent"]),
                          ResetDisplay(StringOrNil(primary[@"resetsAt"]))];
        NSString *seven = [NSString stringWithFormat:@"7d left: %@ (used %@), reset %@",
                           RemainingPercentText(secondary[@"usedPercent"]),
                           PercentText(secondary[@"usedPercent"]),
                           ResetDisplay(StringOrNil(secondary[@"resetsAt"]))];
        [menu addItem:[[NSMenuItem alloc] initWithTitle:five action:nil keyEquivalent:@""]];
        [menu addItem:[[NSMenuItem alloc] initWithTitle:seven action:nil keyEquivalent:@""]];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[[NSMenuItem alloc] initWithTitle:BucketLine(@"Last 5h", UsageBucketDict(self.summary, @"last5h")) action:nil keyEquivalent:@""]];
        [menu addItem:[[NSMenuItem alloc] initWithTitle:BucketLine(@"Today", UsageBucketDict(self.summary, @"today")) action:nil keyEquivalent:@""]];
        [menu addItem:[[NSMenuItem alloc] initWithTitle:BucketLine(@"Last 7d", UsageBucketDict(self.summary, @"last7d")) action:nil keyEquivalent:@""]];
        [menu addItem:[[NSMenuItem alloc] initWithTitle:BucketLine(@"All time", UsageBucketDict(self.summary, @"allTime")) action:nil keyEquivalent:@""]];
        [menu addItem:[NSMenuItem separatorItem]];

        NSString *updated = [NSString stringWithFormat:@"Updated: %@", StringOrNil(self.summary[@"updatedAt"]) ?: @"--"];
        [menu addItem:[[NSMenuItem alloc] initWithTitle:updated action:nil keyEquivalent:@""]];
        [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Non-cache = total - cached input; not official billing." action:nil keyEquivalent:@""]];
    } else {
        [menu addItem:[[NSMenuItem alloc] initWithTitle:@"No local usage summary yet." action:nil keyEquivalent:@""]];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *show = [[NSMenuItem alloc] initWithTitle:@"Show Window" action:@selector(showWindow:) keyEquivalent:@"o"];
    show.target = self;
    [menu addItem:show];

    NSMenuItem *refresh = [[NSMenuItem alloc] initWithTitle:self.refreshing ? @"Refreshing..." : @"Refresh Now"
                                                     action:@selector(refresh:)
                                              keyEquivalent:@"r"];
    refresh.target = self;
    refresh.enabled = !self.refreshing;
    [menu addItem:refresh];

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];

    self.statusItem.menu = menu;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self showWindow:nil];
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return self.showWindowOnLaunch;
}

- (void)showWindow:(id)sender {
    [self ensureWindow];
    [self updateWindowContent];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSTextField *)labelWithFont:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (void)ensureWindow {
    if (self.window) {
        return;
    }

    NSRect frame = NSMakeRect(0, 0, 460, 340);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"Codex Usage";
    self.window.releasedWhenClosed = NO;
    [self.window center];

    NSView *content = [[NSView alloc] initWithFrame:frame];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    self.window.contentView = content;

    self.windowTitleLabel = [self labelWithFont:[NSFont boldSystemFontOfSize:22] color:NSColor.labelColor];
    self.windowLimitLabel = [self labelWithFont:[NSFont monospacedDigitSystemFontOfSize:18 weight:NSFontWeightSemibold] color:NSColor.labelColor];
    self.windowUsageLabel = [self labelWithFont:[NSFont systemFontOfSize:13] color:NSColor.secondaryLabelColor];
    self.windowUpdatedLabel = [self labelWithFont:[NSFont systemFontOfSize:12] color:NSColor.tertiaryLabelColor];

    NSButton *refreshButton = [NSButton buttonWithTitle:@"Refresh" target:self action:@selector(refresh:)];
    refreshButton.translatesAutoresizingMaskIntoConstraints = NO;

    [content addSubview:self.windowTitleLabel];
    [content addSubview:self.windowLimitLabel];
    [content addSubview:self.windowUsageLabel];
    [content addSubview:self.windowUpdatedLabel];
    [content addSubview:refreshButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.windowTitleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:24],
        [self.windowTitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [self.windowTitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [self.windowLimitLabel.topAnchor constraintEqualToAnchor:self.windowTitleLabel.bottomAnchor constant:18],
        [self.windowLimitLabel.leadingAnchor constraintEqualToAnchor:self.windowTitleLabel.leadingAnchor],
        [self.windowLimitLabel.trailingAnchor constraintEqualToAnchor:self.windowTitleLabel.trailingAnchor],
        [self.windowUsageLabel.topAnchor constraintEqualToAnchor:self.windowLimitLabel.bottomAnchor constant:16],
        [self.windowUsageLabel.leadingAnchor constraintEqualToAnchor:self.windowTitleLabel.leadingAnchor],
        [self.windowUsageLabel.trailingAnchor constraintEqualToAnchor:self.windowTitleLabel.trailingAnchor],
        [self.windowUpdatedLabel.topAnchor constraintEqualToAnchor:self.windowUsageLabel.bottomAnchor constant:14],
        [self.windowUpdatedLabel.leadingAnchor constraintEqualToAnchor:self.windowTitleLabel.leadingAnchor],
        [self.windowUpdatedLabel.trailingAnchor constraintEqualToAnchor:self.windowTitleLabel.trailingAnchor],
        [self.windowUpdatedLabel.bottomAnchor constraintLessThanOrEqualToAnchor:refreshButton.topAnchor constant:-14],
        [refreshButton.leadingAnchor constraintEqualToAnchor:self.windowTitleLabel.leadingAnchor],
        [refreshButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-22]
    ]];

}

- (void)updateWindowContent {
    if (!self.window) {
        return;
    }

    if (!self.summary) {
        self.windowTitleLabel.stringValue = @"Codex Usage";
        self.windowLimitLabel.stringValue = @"No local summary yet";
        self.windowUsageLabel.stringValue = @"Click Refresh after Codex has written token_count events.";
        self.windowUpdatedLabel.stringValue = SummaryPath();
        return;
    }

    NSDictionary *primary = PrimaryLimit(self.summary);
    NSDictionary *secondary = SecondaryLimit(self.summary);
    NSDictionary *today = UsageBucketDict(self.summary, @"today");
    NSDictionary *last5h = UsageBucketDict(self.summary, @"last5h");
    NSDictionary *last7d = UsageBucketDict(self.summary, @"last7d");
    NSDictionary *allTime = UsageBucketDict(self.summary, @"allTime");

    self.windowTitleLabel.stringValue = @"Codex Usage";
    self.windowLimitLabel.stringValue = [NSString stringWithFormat:@"5h left %@ · used %@ · reset %@\n7d left %@ · used %@ · reset %@",
                                         RemainingPercentText(primary[@"usedPercent"]),
                                         PercentText(primary[@"usedPercent"]),
                                         ResetDisplay(StringOrNil(primary[@"resetsAt"])),
                                         RemainingPercentText(secondary[@"usedPercent"]),
                                         PercentText(secondary[@"usedPercent"]),
                                         ResetDisplay(StringOrNil(secondary[@"resetsAt"]))];
    self.windowUsageLabel.stringValue = [NSString stringWithFormat:@"%@\n%@\n%@\n%@\n\nNon-cache = total - cached input; not official billing.",
                                         BucketLine(@"Last 5h", last5h),
                                         BucketLine(@"Today", today),
                                         BucketLine(@"Last 7d", last7d),
                                         BucketLine(@"All time", allTime)];
    self.windowUpdatedLabel.stringValue = [NSString stringWithFormat:@"Updated: %@\n%@", StringOrNil(self.summary[@"updatedAt"]) ?: @"--", SummaryPath()];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

@end

static void PrintSummary(NSDictionary *summary) {
    NSDictionary *primary = PrimaryLimit(summary);
    NSDictionary *secondary = SecondaryLimit(summary);
    printf("Updated: %s\n", [StringOrNil(summary[@"updatedAt"]) ?: @"--" UTF8String]);
    printf("5h left: %s used %s reset %s\n", [RemainingPercentText(primary[@"usedPercent"]) UTF8String], [PercentText(primary[@"usedPercent"]) UTF8String], [ResetDisplay(StringOrNil(primary[@"resetsAt"])) UTF8String]);
    printf("7d left: %s used %s reset %s\n", [RemainingPercentText(secondary[@"usedPercent"]) UTF8String], [PercentText(secondary[@"usedPercent"]) UTF8String], [ResetDisplay(StringOrNil(secondary[@"resetsAt"])) UTF8String]);
    printf("%s\n", [BucketLine(@"Today", UsageBucketDict(summary, @"today")) UTF8String]);
    printf("%s\n", [BucketLine(@"All time", UsageBucketDict(summary, @"allTime")) UTF8String]);
    printf("Summary: %s\n", [SummaryPath() UTF8String]);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        if ([arguments containsObject:@"--collect"]) {
            NSError *error = nil;
            NSDictionary *summary = CollectAndSave(&error);
            if (!summary) {
                fprintf(stderr, "CodexUsageMonitor: %s\n", error.localizedDescription.UTF8String);
                return 1;
            }
            if ([arguments containsObject:@"--print"]) {
                PrintSummary(summary);
            }
            return 0;
        }

        NSApplication *app = NSApplication.sharedApplication;
        CodexUsageAppDelegate *delegate = [[CodexUsageAppDelegate alloc] init];
        delegate.showWindowOnLaunch = ![arguments containsObject:@"--menubar"];
        app.delegate = delegate;
        if (delegate.showWindowOnLaunch) {
            [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        } else {
            [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        }
        [app run];
    }
    return 0;
}

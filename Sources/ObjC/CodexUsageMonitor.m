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

static NSDate *DisplayDateFromString(NSString *isoString) {
    if (![isoString isKindOfClass:NSString.class]) {
        return nil;
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
    return date;
}

static NSString *ClockDisplay(NSString *isoString) {
    NSDate *date = DisplayDateFromString(isoString);
    if (!date) {
        return @"--";
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    formatter.dateFormat = @"HH:mm";
    return [formatter stringFromDate:date];
}

static NSString *ResetDisplay(NSString *isoString) {
    NSDate *date = DisplayDateFromString(isoString);
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

static double RemainingPercentValue(id usedValue) {
    NSNumber *number = NumberOrNil(usedValue);
    if (!number) {
        return 0;
    }
    double remaining = 100.0 - number.doubleValue;
    if (remaining < 0) {
        return 0;
    }
    if (remaining > 100) {
        return 100;
    }
    return remaining;
}

static NSColor *UsageColorForRemaining(double remaining) {
    if (remaining <= 10) {
        return NSColor.systemRedColor;
    }
    if (remaining <= 20) {
        return NSColor.systemOrangeColor;
    }
    if (remaining <= 50) {
        return [NSColor colorWithCalibratedRed:0.95 green:0.68 blue:0.05 alpha:1.0];
    }
    if (remaining <= 90) {
        return [NSColor colorWithCalibratedRed:0.10 green:0.74 blue:0.30 alpha:1.0];
    }
    return [NSColor colorWithCalibratedRed:0.10 green:0.55 blue:0.95 alpha:1.0];
}

static NSColor *StatusColorForRemaining(double remaining) {
    if (remaining <= 10) {
        return [NSColor colorWithCalibratedRed:1.00 green:0.32 blue:0.28 alpha:1.0];
    }
    if (remaining <= 20) {
        return [NSColor colorWithCalibratedRed:1.00 green:0.58 blue:0.18 alpha:1.0];
    }
    if (remaining <= 50) {
        return [NSColor colorWithCalibratedRed:1.00 green:0.86 blue:0.18 alpha:1.0];
    }
    if (remaining <= 90) {
        return [NSColor colorWithCalibratedRed:0.55 green:1.00 blue:0.62 alpha:1.0];
    }
    return [NSColor colorWithCalibratedRed:0.65 green:0.95 blue:1.00 alpha:1.0];
}

static NSString *YiTokens(long long tokens, NSInteger digits) {
    double value = (double)tokens / 100000000.0;
    return [NSString stringWithFormat:@"%.*f 亿", (int)digits, value];
}

static NSString *YiTokensCompact(long long tokens, NSInteger digits) {
    double value = (double)tokens / 100000000.0;
    return [NSString stringWithFormat:@"%.*f亿", (int)digits, value];
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

static NSDate *NextWindowResetAfterDate(NSDate *now, NSDate *resetDate, NSNumber *windowMinutes) {
    if (!resetDate) {
        return NextLocalWindowReset(now, windowMinutes);
    }

    NSInteger minutes = windowMinutes.integerValue > 0 ? windowMinutes.integerValue : 300;
    NSTimeInterval windowSeconds = (NSTimeInterval)minutes * 60.0;
    if ([resetDate compare:now] == NSOrderedDescending) {
        return resetDate;
    }

    NSTimeInterval elapsed = [now timeIntervalSinceDate:resetDate];
    NSInteger windowsToAdd = (NSInteger)floor(elapsed / windowSeconds) + 1;
    return [resetDate dateByAddingTimeInterval:windowSeconds * windowsToAdd];
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
    normalizedPrimary[@"resetsAt"] = LocalISOString(NextWindowResetAfterDate(now, resetDate, windowMinutes));
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

static void SetStatusTitle(NSStatusItem *statusItem, NSString *title) {
    if (!statusItem.button) {
        return;
    }

    statusItem.button.attributedTitle = [[NSAttributedString alloc] initWithString:@""];
    statusItem.button.title = title;
    statusItem.button.contentTintColor = nil;
}

static void DrawCodexMark(NSRect rect, NSColor *color) {
    NSColor *drawColor = color ?: NSColor.whiteColor;
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 1.5, 1.5)];
    ring.lineWidth = 1.4;
    [drawColor setStroke];
    [ring stroke];

    NSString *letter = @"C";
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:rect.size.height * 0.62 weight:NSFontWeightBlack],
        NSForegroundColorAttributeName: drawColor,
        NSParagraphStyleAttributeName: paragraph
    };
    NSSize textSize = [letter sizeWithAttributes:attributes];
    NSRect textRect = NSMakeRect(NSMinX(rect),
                                 NSMidY(rect) - textSize.height / 2.0 - 0.3,
                                 rect.size.width,
                                 textSize.height);
    [letter drawInRect:textRect withAttributes:attributes];
}

static NSImage *CodexBadgeImage(CGFloat size) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];

    NSRect rect = NSMakeRect(0, 0, size, size);
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 1, 1)
                                                               xRadius:size * 0.22
                                                               yRadius:size * 0.22];
    [[NSColor colorWithCalibratedRed:0.07 green:0.09 blue:0.13 alpha:1.0] setFill];
    [background fill];

    NSRect gaugeRect = NSInsetRect(rect, size * 0.18, size * 0.20);
    NSPoint center = NSMakePoint(NSMidX(gaugeRect), NSMinY(gaugeRect) + gaugeRect.size.height * 0.38);
    CGFloat radius = gaugeRect.size.width * 0.42;

    NSBezierPath *track = [[NSBezierPath alloc] init];
    [track appendBezierPathWithArcWithCenter:center radius:radius startAngle:205 endAngle:-25 clockwise:YES];
    track.lineWidth = MAX(2, size * 0.07);
    track.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithCalibratedWhite:1 alpha:0.28] setStroke];
    [track stroke];

    NSBezierPath *gauge = [[NSBezierPath alloc] init];
    [gauge appendBezierPathWithArcWithCenter:center radius:radius startAngle:205 endAngle:35 clockwise:YES];
    gauge.lineWidth = track.lineWidth;
    gauge.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithCalibratedRed:0.18 green:0.86 blue:0.50 alpha:1.0] setStroke];
    [gauge stroke];

    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:size * 0.32 weight:NSFontWeightBlack],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSString *letter = @"C";
    NSSize textSize = [letter sizeWithAttributes:attributes];
    [letter drawAtPoint:NSMakePoint((size - textSize.width) / 2.0,
                                    size * 0.58)
         withAttributes:attributes];

    [image unlockFocus];
    image.template = NO;
    return image;
}

static NSImage *StatusDisplayImage(double remaining, BOOL hasData) {
    NSSize size = NSMakeSize(49, 16);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];

    DrawCodexMark(NSMakeRect(0.5, 0.5, 15.0, 15.0), [NSColor colorWithCalibratedWhite:1.0 alpha:0.88]);

    NSRect bodyRect = NSMakeRect(20.0, 3.0, 24.0, 10.0);
    NSRect capRect = NSMakeRect(44.5, 6.0, 3.0, 4.0);
    NSBezierPath *bodyPath = [NSBezierPath bezierPathWithRoundedRect:bodyRect xRadius:3.2 yRadius:3.2];
    NSBezierPath *capPath = [NSBezierPath bezierPathWithRoundedRect:capRect xRadius:1.4 yRadius:1.4];

    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.30] setFill];
    [bodyPath fill];
    [capPath fill];

    if (hasData) {
        double clamped = MIN(MAX(remaining, 0), 100);
        CGFloat fillWidth = MAX(1.8, (bodyRect.size.width - 4.0) * clamped / 100.0);
        NSRect fillRect = NSMakeRect(NSMinX(bodyRect) + 2.0,
                                     NSMinY(bodyRect) + 2.0,
                                     fillWidth,
                                     bodyRect.size.height - 4.0);
        [UsageColorForRemaining(clamped) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:2.0 yRadius:2.0] fill];
    }

    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.72] setStroke];
    bodyPath.lineWidth = 1.0;
    [bodyPath stroke];

    [image unlockFocus];
    image.template = NO;
    return image;
}

static void SetStatusDisplay(NSStatusItem *statusItem, NSString *title, double remaining, BOOL hasData) {
    if (!statusItem.button) {
        return;
    }

    statusItem.button.attributedTitle = [[NSAttributedString alloc] initWithString:@""];
    statusItem.button.title = title ?: @"--";
    statusItem.button.image = StatusDisplayImage(remaining, hasData);
    statusItem.button.imagePosition = NSImageLeft;
    statusItem.button.imageScaling = NSImageScaleProportionallyDown;
    statusItem.button.contentTintColor = nil;
    statusItem.button.toolTip = @"Codex 使用情况";
}

static NSString *BucketLine(NSString *title, NSDictionary *bucket) {
    long long total = LongLongValue(bucket[@"totalTokens"]);
    long long nonCached = LongLongValue(bucket[@"nonCachedApproxTokens"]);
    return [NSString stringWithFormat:@"%@: %@ total / %@ non-cache", title, YiTokens(total, 2), YiTokens(nonCached, 3)];
}

static NSString *BucketCompactValue(NSDictionary *bucket) {
    long long cached = LongLongValue(bucket[@"cachedInputTokens"]);
    long long nonCached = LongLongValue(bucket[@"nonCachedApproxTokens"]);
    return [NSString stringWithFormat:@"命中%@ / 未命中%@",
            YiTokensCompact(cached, 2),
            YiTokensCompact(nonCached, 3)];
}

@interface CodexUsageMeterView : NSView
@property(nonatomic, assign) double remainingPercent;
@end

@implementation CodexUsageMeterView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    CGFloat inset = 4;
    CGFloat trackHeight = 12;
    NSRect bounds = self.bounds;
    NSRect trackRect = NSMakeRect(inset, floor((bounds.size.height - trackHeight) / 2.0), MAX(1, bounds.size.width - inset * 2), trackHeight);
    CGFloat radius = trackHeight / 2.0;
    NSBezierPath *clipPath = [NSBezierPath bezierPathWithRoundedRect:trackRect xRadius:radius yRadius:radius];

    [[NSColor colorWithCalibratedWhite:0.84 alpha:1.0] setFill];
    [clipPath fill];

    [NSGraphicsContext saveGraphicsState];
    [clipPath addClip];

    double remaining = MIN(MAX(self.remainingPercent, 0), 100);
    CGFloat width = trackRect.size.width * remaining / 100.0;
    if (width > 0) {
        [UsageColorForRemaining(remaining) setFill];
        NSRectFill(NSMakeRect(NSMinX(trackRect), NSMinY(trackRect), width, trackRect.size.height));
    }

    [NSGraphicsContext restoreGraphicsState];
}

@end

@interface CodexUsageAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSPopover *popover;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *windowTitleLabel;
@property(nonatomic, strong) NSTextField *windowLimitLabel;
@property(nonatomic, strong) NSTextField *windowUsageLabel;
@property(nonatomic, strong) NSTextField *windowUpdatedLabel;
@property(nonatomic, strong) NSDictionary *summary;
@property(nonatomic, copy) NSString *lastErrorMessage;
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
        SetStatusDisplay(self.statusItem, @"--", 0, NO);
        self.statusItem.button.target = self;
        self.statusItem.button.action = @selector(togglePopover:);
        [self.statusItem.button sendActionOn:(NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp)];
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

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSDictionary *summary = CollectAndSave(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.refreshing = NO;
            if (summary) {
                self.summary = summary;
                self.lastErrorMessage = nil;
            } else if (error) {
                self.lastErrorMessage = error.localizedDescription;
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
    NSNumber *primaryPercent = NumberOrNil(primary[@"usedPercent"]);
    NSString *remainingText = RemainingPercentText(primaryPercent);
    NSString *reset = ClockDisplay(StringOrNil(primary[@"resetsAt"]));
    NSString *statusTitle = [NSString stringWithFormat:@"%@ %@", remainingText, reset];
    if (primaryPercent) {
        double remaining = RemainingPercentValue(primaryPercent);
        SetStatusDisplay(self.statusItem, statusTitle, remaining, YES);
    } else {
        SetStatusDisplay(self.statusItem, statusTitle, 0, NO);
    }
    self.statusItem.menu = nil;
    if (self.popover.shown) {
        [self updatePopoverContent];
    }
}

- (void)togglePopover:(id)sender {
    if (self.popover.shown) {
        [self.popover performClose:sender];
        return;
    }

    [self showPopover:sender];
}

- (void)showPopover:(id)sender {
    if (!self.statusItem.button) {
        return;
    }

    if (!self.popover) {
        self.popover = [[NSPopover alloc] init];
        self.popover.behavior = NSPopoverBehaviorTransient;
        self.popover.animates = YES;
    }
    [self updatePopoverContent];
    [self.popover showRelativeToRect:self.statusItem.button.bounds
                               ofView:self.statusItem.button
                        preferredEdge:NSRectEdgeMinY];
}

- (void)updatePopoverContent {
    if (!self.popover) {
        return;
    }

    self.popover.contentViewController = [self popoverViewController];
}

- (NSTextField *)popoverLabelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:string ?: @""];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSView *)popoverRowWithTitle:(NSString *)title value:(NSString *)value valueColor:(NSColor *)valueColor emphasized:(BOOL)emphasized {
    NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 294, 22)];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *titleLabel = [self popoverLabelWithString:title
                                                      font:[NSFont systemFontOfSize:12.5 weight:emphasized ? NSFontWeightSemibold : NSFontWeightRegular]
                                                     color:NSColor.secondaryLabelColor];
    NSTextField *valueLabel = [self popoverLabelWithString:value
                                                      font:[NSFont monospacedDigitSystemFontOfSize:12.5 weight:emphasized ? NSFontWeightSemibold : NSFontWeightRegular]
                                                     color:valueColor ?: NSColor.labelColor];
    valueLabel.alignment = NSTextAlignmentRight;
    valueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    [row addSubview:titleLabel];
    [row addSubview:valueLabel];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:22],
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:12],
        [valueLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [valueLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [valueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:96]
    ]];

    return row;
}

- (NSView *)popoverRowWithTitle:(NSString *)title value:(NSString *)value emphasized:(BOOL)emphasized {
    return [self popoverRowWithTitle:title value:value valueColor:NSColor.labelColor emphasized:emphasized];
}

- (NSView *)popoverSeparator {
    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 340, 1)];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [separator.heightAnchor constraintEqualToConstant:1].active = YES;
    return separator;
}

- (NSButton *)popoverIconButtonWithSymbol:(NSString *)symbol tooltip:(NSString *)tooltip action:(SEL)action {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tooltip];
    NSButton *button = [NSButton buttonWithImage:image target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bordered = NO;
    button.toolTip = tooltip;
    button.contentTintColor = NSColor.secondaryLabelColor;
    [button.widthAnchor constraintEqualToConstant:24].active = YES;
    [button.heightAnchor constraintEqualToConstant:24].active = YES;
    return button;
}

- (NSView *)popoverButtonRow {
    NSStackView *row = [[NSStackView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.distribution = NSStackViewDistributionFill;
    row.spacing = 8;

    NSButton *refreshButton = [NSButton buttonWithTitle:@"刷新"
                                                 target:self
                                                 action:@selector(refresh:)];
    refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    refreshButton.enabled = !self.refreshing;
    refreshButton.bezelStyle = NSBezelStyleRounded;
    [refreshButton.widthAnchor constraintEqualToConstant:112].active = YES;

    NSView *spacer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    [row addArrangedSubview:spacer];
    [row addArrangedSubview:refreshButton];
    [row addArrangedSubview:[self popoverIconButtonWithSymbol:@"macwindow" tooltip:@"显示窗口" action:@selector(showWindow:)]];
    [row addArrangedSubview:[self popoverIconButtonWithSymbol:@"power" tooltip:@"退出" action:@selector(quit:)]];
    return row;
}

- (NSViewController *)popoverViewController {
    NSViewController *controller = [[NSViewController alloc] init];
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 326, 368)];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.95 green:0.98 blue:1.00 alpha:1.0].CGColor;
    content.layer.cornerRadius = 14;

    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeWidth;
    stack.spacing = 5;
    stack.edgeInsets = NSEdgeInsetsMake(13, 16, 13, 16);
    [content addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [content.widthAnchor constraintEqualToConstant:326],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
    ]];

    NSTextField *titleLabel = [self popoverLabelWithString:@"Codex 使用情况"
                                                      font:[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold]
                                                     color:NSColor.secondaryLabelColor];
    titleLabel.alignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:titleLabel];

    if (self.summary) {
        NSDictionary *primary = PrimaryLimit(self.summary);
        NSDictionary *secondary = SecondaryLimit(self.summary);
        double remaining = RemainingPercentValue(primary[@"usedPercent"]);

        CodexUsageMeterView *meter = [[CodexUsageMeterView alloc] initWithFrame:NSMakeRect(0, 0, 294, 34)];
        meter.translatesAutoresizingMaskIntoConstraints = NO;
        meter.remainingPercent = remaining;
        meter.wantsLayer = YES;
        [meter.heightAnchor constraintEqualToConstant:30].active = YES;
        [stack addArrangedSubview:meter];

        [stack addArrangedSubview:[self popoverRowWithTitle:@"5 小时剩余"
                                                      value:RemainingPercentText(primary[@"usedPercent"])
                                                 valueColor:UsageColorForRemaining(remaining)
                                                 emphasized:YES]];
        [stack addArrangedSubview:[self popoverRowWithTitle:@"5 小时刷新"
                                                      value:ClockDisplay(StringOrNil(primary[@"resetsAt"]))
                                                 emphasized:NO]];
        double secondaryRemaining = RemainingPercentValue(secondary[@"usedPercent"]);
        [stack addArrangedSubview:[self popoverRowWithTitle:@"1 周剩余"
                                                      value:RemainingPercentText(secondary[@"usedPercent"])
                                                 valueColor:UsageColorForRemaining(secondaryRemaining)
                                                 emphasized:YES]];
        [stack addArrangedSubview:[self popoverRowWithTitle:@"1 周刷新"
                                                      value:ResetDisplay(StringOrNil(secondary[@"resetsAt"]))
                                                 emphasized:NO]];
        [stack addArrangedSubview:[self popoverSeparator]];
        [stack addArrangedSubview:[self popoverRowWithTitle:@"最近 5 小时"
                                                      value:BucketCompactValue(UsageBucketDict(self.summary, @"last5h"))
                                                 emphasized:NO]];
        [stack addArrangedSubview:[self popoverRowWithTitle:@"今日"
                                                      value:BucketCompactValue(UsageBucketDict(self.summary, @"today"))
                                                 emphasized:NO]];
        [stack addArrangedSubview:[self popoverRowWithTitle:@"最近 7 天"
                                                      value:BucketCompactValue(UsageBucketDict(self.summary, @"last7d"))
                                                 emphasized:NO]];
        [stack addArrangedSubview:[self popoverRowWithTitle:@"总计"
                                                      value:BucketCompactValue(UsageBucketDict(self.summary, @"allTime"))
                                                 emphasized:NO]];
        [stack addArrangedSubview:[self popoverSeparator]];
        [stack addArrangedSubview:[self popoverRowWithTitle:@"更新"
                                                      value:ResetDisplay(StringOrNil(self.summary[@"updatedAt"]))
                                                 emphasized:NO]];
    } else {
        NSTextField *emptyLabel = [self popoverLabelWithString:@"暂无本地使用摘要"
                                                          font:[NSFont systemFontOfSize:13 weight:NSFontWeightRegular]
                                                         color:NSColor.secondaryLabelColor];
        emptyLabel.maximumNumberOfLines = 0;
        emptyLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [emptyLabel.heightAnchor constraintGreaterThanOrEqualToConstant:72].active = YES;
        [stack addArrangedSubview:emptyLabel];
    }

    if (self.lastErrorMessage.length > 0) {
        NSTextField *errorLabel = [self popoverLabelWithString:self.lastErrorMessage
                                                          font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]
                                                         color:NSColor.systemRedColor];
        errorLabel.maximumNumberOfLines = 2;
        errorLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [stack addArrangedSubview:errorLabel];
    }

    [stack addArrangedSubview:[self popoverButtonRow]];

    controller.view = content;
    return controller;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self showWindow:nil];
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return self.showWindowOnLaunch;
}

- (void)showWindow:(id)sender {
    [self.popover performClose:sender];
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

- (NSTextField *)windowLabelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:string ?: @""];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSView *)windowSeparator {
    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 460, 1)];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [separator.heightAnchor constraintEqualToConstant:1].active = YES;
    return separator;
}

- (NSView *)windowRowWithTitle:(NSString *)title value:(NSString *)value valueColor:(NSColor *)valueColor emphasized:(BOOL)emphasized {
    NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 25)];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *titleLabel = [self windowLabelWithString:title
                                                     font:[NSFont systemFontOfSize:14 weight:emphasized ? NSFontWeightSemibold : NSFontWeightRegular]
                                                    color:NSColor.secondaryLabelColor];
    NSTextField *valueLabel = [self windowLabelWithString:value
                                                     font:[NSFont monospacedDigitSystemFontOfSize:15 weight:emphasized ? NSFontWeightSemibold : NSFontWeightRegular]
                                                    color:valueColor ?: NSColor.labelColor];
    valueLabel.alignment = NSTextAlignmentRight;

    [row addSubview:titleLabel];
    [row addSubview:valueLabel];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:25],
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:18],
        [valueLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [valueLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [valueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:130]
    ]];

    return row;
}

- (NSView *)windowRowWithTitle:(NSString *)title value:(NSString *)value emphasized:(BOOL)emphasized {
    return [self windowRowWithTitle:title value:value valueColor:NSColor.labelColor emphasized:emphasized];
}

- (void)ensureWindow {
    if (self.window) {
        return;
    }

    NSRect frame = NSMakeRect(0, 0, 520, 430);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"Codex Usage";
    self.window.releasedWhenClosed = NO;
    [self.window center];

    NSView *content = [[NSView alloc] initWithFrame:frame];
    content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.95 green:0.98 blue:1.00 alpha:1.0].CGColor;
    self.window.contentView = content;
}

- (void)updateWindowContent {
    if (!self.window) {
        return;
    }

    NSView *content = self.window.contentView;
    for (NSView *subview in content.subviews.copy) {
        [subview removeFromSuperview];
    }
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.95 green:0.98 blue:1.00 alpha:1.0].CGColor;

    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeWidth;
    stack.spacing = 6;
    stack.edgeInsets = NSEdgeInsetsMake(22, 28, 22, 28);
    [content addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
    ]];

    NSStackView *header = [[NSStackView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 12;

    NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 34, 34)];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = CodexBadgeImage(34);
    [iconView.widthAnchor constraintEqualToConstant:34].active = YES;
    [iconView.heightAnchor constraintEqualToConstant:34].active = YES;

    NSTextField *titleLabel = [self windowLabelWithString:@"Codex 使用情况"
                                                     font:[NSFont systemFontOfSize:22 weight:NSFontWeightBold]
                                                    color:NSColor.labelColor];

    NSView *spacer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSString *updatedText = self.summary ? [NSString stringWithFormat:@"更新 %@", ResetDisplay(StringOrNil(self.summary[@"updatedAt"]))] : @"--";
    NSTextField *updatedLabel = [self windowLabelWithString:updatedText
                                                       font:[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular]
                                                      color:NSColor.tertiaryLabelColor];
    updatedLabel.alignment = NSTextAlignmentRight;

    [header addArrangedSubview:iconView];
    [header addArrangedSubview:titleLabel];
    [header addArrangedSubview:spacer];
    [header addArrangedSubview:updatedLabel];
    [stack addArrangedSubview:header];

    if (!self.summary) {
        NSTextField *emptyLabel = [self windowLabelWithString:@"暂无本地使用摘要"
                                                         font:[NSFont systemFontOfSize:15 weight:NSFontWeightRegular]
                                                        color:NSColor.secondaryLabelColor];
        [emptyLabel.heightAnchor constraintGreaterThanOrEqualToConstant:72].active = YES;
        [stack addArrangedSubview:emptyLabel];

        NSButton *refreshButton = [NSButton buttonWithTitle:@"刷新" target:self action:@selector(refresh:)];
        refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
        refreshButton.bezelStyle = NSBezelStyleRounded;
        [refreshButton.widthAnchor constraintEqualToConstant:96].active = YES;
        [stack addArrangedSubview:refreshButton];
        return;
    }

    NSDictionary *primary = PrimaryLimit(self.summary);
    NSDictionary *secondary = SecondaryLimit(self.summary);
    NSDictionary *today = UsageBucketDict(self.summary, @"today");
    NSDictionary *last5h = UsageBucketDict(self.summary, @"last5h");
    NSDictionary *last7d = UsageBucketDict(self.summary, @"last7d");
    NSDictionary *allTime = UsageBucketDict(self.summary, @"allTime");

    double primaryRemaining = RemainingPercentValue(primary[@"usedPercent"]);
    double secondaryRemaining = RemainingPercentValue(secondary[@"usedPercent"]);

    CodexUsageMeterView *meter = [[CodexUsageMeterView alloc] initWithFrame:NSMakeRect(0, 0, 464, 32)];
    meter.translatesAutoresizingMaskIntoConstraints = NO;
    meter.remainingPercent = primaryRemaining;
    [meter.heightAnchor constraintEqualToConstant:32].active = YES;
    [stack addArrangedSubview:meter];

    [stack addArrangedSubview:[self windowRowWithTitle:@"5 小时剩余"
                                                 value:RemainingPercentText(primary[@"usedPercent"])
                                            valueColor:UsageColorForRemaining(primaryRemaining)
                                            emphasized:YES]];
    [stack addArrangedSubview:[self windowRowWithTitle:@"5 小时刷新"
                                                 value:ClockDisplay(StringOrNil(primary[@"resetsAt"]))
                                            emphasized:NO]];
    [stack addArrangedSubview:[self windowRowWithTitle:@"1 周剩余"
                                                 value:RemainingPercentText(secondary[@"usedPercent"])
                                            valueColor:UsageColorForRemaining(secondaryRemaining)
                                            emphasized:YES]];
    [stack addArrangedSubview:[self windowRowWithTitle:@"1 周刷新"
                                                 value:ResetDisplay(StringOrNil(secondary[@"resetsAt"]))
                                            emphasized:NO]];
    [stack addArrangedSubview:[self windowSeparator]];
    [stack addArrangedSubview:[self windowRowWithTitle:@"最近 5 小时" value:BucketCompactValue(last5h) emphasized:NO]];
    [stack addArrangedSubview:[self windowRowWithTitle:@"今日" value:BucketCompactValue(today) emphasized:NO]];
    [stack addArrangedSubview:[self windowRowWithTitle:@"最近 7 天" value:BucketCompactValue(last7d) emphasized:NO]];
    [stack addArrangedSubview:[self windowRowWithTitle:@"总计" value:BucketCompactValue(allTime) emphasized:NO]];
    [stack addArrangedSubview:[self windowSeparator]];

    NSStackView *footer = [[NSStackView alloc] init];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    footer.alignment = NSLayoutAttributeCenterY;
    footer.spacing = 10;

    NSTextField *footerLabel = [self windowLabelWithString:@"本地日志汇总"
                                                      font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]
                                                     color:NSColor.tertiaryLabelColor];
    NSView *footerSpacer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)];
    footerSpacer.translatesAutoresizingMaskIntoConstraints = NO;
    [footerSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *refreshButton = [NSButton buttonWithTitle:@"刷新" target:self action:@selector(refresh:)];
    refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    refreshButton.enabled = !self.refreshing;
    refreshButton.bezelStyle = NSBezelStyleRounded;
    [refreshButton.widthAnchor constraintEqualToConstant:92].active = YES;

    [footer addArrangedSubview:footerLabel];
    [footer addArrangedSubview:footerSpacer];
    [footer addArrangedSubview:refreshButton];
    [stack addArrangedSubview:footer];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

@end

static void PrintSummary(NSDictionary *summary) {
    NSDictionary *primary = PrimaryLimit(summary);
    NSDictionary *secondary = SecondaryLimit(summary);
    printf("Updated: %s\n", [StringOrNil(summary[@"updatedAt"]) ?: @"--" UTF8String]);
    printf("5h left: %s used %s reset %s\n", [RemainingPercentText(primary[@"usedPercent"]) UTF8String], [PercentText(primary[@"usedPercent"]) UTF8String], [ClockDisplay(StringOrNil(primary[@"resetsAt"])) UTF8String]);
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

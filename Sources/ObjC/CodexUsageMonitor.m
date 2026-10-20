#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import "MonitoringSupport.h"
#import "QuotaQuery.h"
#include <math.h>

typedef struct {
    long long events;
    long long inputTokens;
    long long cachedInputTokens;
    long long outputTokens;
    long long reasoningOutputTokens;
    long long totalTokens;
} UsageBucket;

static NSString * const CodexUsageSummaryRelativePath = @"Library/Application Support/CodexUsage/usage_summary.json";
static NSString *CodexRoot(void) {
    NSString *configured = NSProcessInfo.processInfo.environment[@"CODEX_HOME"];
    return configured.length ? configured.stringByExpandingTildeInPath : [NSHomeDirectory() stringByAppendingPathComponent:@".codex"];
}

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
    return [CodexRoot() stringByAppendingPathComponent:@"sessions"];
}

static NSString *ArchivedSessionsRoot(void) {
    return [CodexRoot() stringByAppendingPathComponent:@"archived_sessions"];
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

// One remaining-quota palette for menu bar batteries, meters and value labels.
// Thresholds are inclusive: 5% is critical, 10% is red, 90% is the 81-90 band.
static NSColor *UsageColorForRemaining(double remaining) {
    if (!isfinite(remaining)) return NSColor.secondaryLabelColor;
    static const struct { double upper; unsigned int rgb; } bands[] = {
        {  5, 0xB91C1C }, // critical red
        { 10, 0xE53935 }, // red
        { 20, 0xF15524 }, // red-orange
        { 30, 0xF97316 }, // orange
        { 40, 0xE38A08 }, // amber
        { 50, 0xCB920D }, // golden yellow
        { 60, 0xB2A11B }, // yellow
        { 70, 0x96AF2B }, // yellow-green
        { 80, 0x65B83E }, // lime green
        { 90, 0x32B653 }, // green
        {100, 0x16A34A }  // plentiful green
    };
    double value = MIN(MAX(remaining, 0), 100);
    for (NSUInteger i = 0; i < sizeof(bands) / sizeof(bands[0]); i++) {
        if (value <= bands[i].upper) {
            unsigned int rgb = bands[i].rgb;
            return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0
                                      green:((rgb >> 8) & 255) / 255.0
                                       blue:(rgb & 255) / 255.0 alpha:1];
        }
    }
    return NSColor.secondaryLabelColor;
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

// A local log cannot establish the next server window after a reset.
// Keep the observed reset time and hide expired percentages until Codex updates it.
static NSDictionary *NormalizeLimitDictionary(NSDictionary *limits, NSDate *now) {
    if (![limits isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *result = [limits mutableCopy];
    for (NSString *key in @[@"primary", @"secondary"]) {
        NSDictionary *window = [limits[key] isKindOfClass:NSDictionary.class] ? limits[key] : nil;
        NSDate *reset = DisplayDateFromString(window[@"resetsAt"]);
        if (window && reset && [reset compare:now] != NSOrderedDescending) {
            NSMutableDictionary *expired = [window mutableCopy];
            expired[@"usedPercent"] = NSNull.null;
            result[key] = expired;
        }
    }
    return result;
}

static NSString *WindowTitle(NSDictionary *window) {
    NSInteger minutes = LongLongValue(window[@"windowMinutes"]);
    if (minutes == 10080) return @"7 天";
    if (minutes == 300) return @"5 小时";
    if (minutes > 0 && minutes % 1440 == 0) return [NSString stringWithFormat:@"%ld 天", (long)(minutes / 1440)];
    if (minutes > 0 && minutes % 60 == 0) return [NSString stringWithFormat:@"%ld 小时", (long)(minutes / 60)];
    return minutes > 0 ? [NSString stringWithFormat:@"%ld 分钟", (long)minutes] : @"额度";
}

static NSDictionary *LimitDictionary(NSDictionary *rateLimits) {
    if (![rateLimits isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    if (StringOrNil(rateLimits[@"limit_id"]) && ![rateLimits[@"limit_id"] isEqualToString:@"codex"]) {
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

static NSMutableDictionary *TokenEventCache(void) {
    static NSMutableDictionary *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    return cache;
}

static NSArray *TokenEventsInFile(NSString *file) {
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:file error:nil];
    if (!attributes) return @[];
    NSArray *signature = @[attributes[NSFileSize], attributes[NSFileModificationDate], attributes[NSFileSystemFileNumber]];
    NSDictionary *cached = TokenEventCache()[file];
    if ([cached[@"signature"] isEqual:signature]) return cached[@"events"];
    NSData *data = [NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return @[];
    NSMutableArray *events = [NSMutableArray array];
    const uint8_t *bytes = data.bytes;
    const char *needle = "\"token_count\"";
    NSUInteger start = 0;
    for (NSUInteger end = 0; end < data.length; end++) {
        if (bytes[end] != '\n') continue; // Retry a partially written final line next time.
        if (end > start && BytesContainNeedle(bytes, start, end, needle, strlen(needle))) {
            NSData *line = [NSData dataWithBytes:bytes + start length:end - start];
            NSDictionary *object = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
            NSDictionary *payload = [object isKindOfClass:NSDictionary.class] ? object[@"payload"] : nil;
            if ([payload isKindOfClass:NSDictionary.class] && [payload[@"type"] isEqual:@"token_count"] && StringOrNil(object[@"timestamp"])) {
                [events addObject:@{@"timestamp": object[@"timestamp"], @"payload": payload}];
            }
        }
        start = end + 1;
    }
    TokenEventCache()[file] = @{@"signature": signature, @"events": events};
    return events;
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
    NSMutableSet *removed = [NSMutableSet setWithArray:TokenEventCache().allKeys];
    [removed minusSet:[NSSet setWithArray:files]];
    [TokenEventCache() removeObjectsForKeys:removed.allObjects];
    for (NSString *file in files) {
        BOOL fileHasUsage = NO;
        NSNumber *previousTotal = nil;
        for (NSDictionary *object in TokenEventsInFile(file)) {
            @autoreleasepool {
                NSDictionary *payload = object[@"payload"];
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
                NSDictionary *total = [info[@"total_token_usage"] isKindOfClass:NSDictionary.class] ? info[@"total_token_usage"] : nil;
                NSNumber *cumulative = NumberOrNil(total[@"total_tokens"]);
                BOOL repeated = cumulative && previousTotal && [cumulative isEqualToNumber:previousTotal];
                if (cumulative) previousTotal = cumulative;
                if (timestamp && usage && NumberOrNil(usage[@"total_tokens"]) && !repeated) {
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
            @"lastEventAt": NullSafe(lastEventAt ? LocalISOString(lastEventAt) : nil),
            @"limitsObservedAt": NullSafe(latestLimitAt ? LocalISOString(latestLimitAt) : nil)
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

    NSArray<NSString *> *paths = @[SummaryPath()];
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

static NSDictionary *LiveLimitDictionary(NSDictionary *response) {
    NSDictionary *buckets = [response[@"rateLimitsByLimitId"] isKindOfClass:NSDictionary.class] ? response[@"rateLimitsByLimitId"] : nil;
    id value = buckets ? buckets[@"codex"] : response[@"rateLimits"];
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *raw = value;
    if (raw[@"limitId"] && ![raw[@"limitId"] isEqual:@"codex"]) return nil;
    NSMutableDictionary *mapped = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"primary", @"secondary"]) {
        NSDictionary *window = [raw[key] isKindOfClass:NSDictionary.class] ? raw[key] : nil;
        NSNumber *used = NumberOrNil(window[@"usedPercent"]);
        NSNumber *minutes = NumberOrNil(window[@"windowDurationMins"]);
        NSNumber *reset = NumberOrNil(window[@"resetsAt"]);
        if (used && minutes && isfinite(used.doubleValue) && used.doubleValue >= 0 && used.doubleValue <= 100 && minutes.doubleValue > 0) {
            mapped[key] = @{@"used_percent": used, @"window_minutes": minutes, @"resets_at": NullSafe(reset)};
        }
    }
    if (!mapped.count) return nil;
    mapped[@"plan_type"] = NullSafe(StringOrNil(raw[@"planType"]));
    mapped[@"rate_limit_reached_type"] = NullSafe(StringOrNil(raw[@"rateLimitReachedType"]));
    return LimitDictionary(mapped);
}

static NSDictionary *SummaryWithQuota(NSDictionary *summary, NSDictionary *previous, NSDictionary *limits, NSError *queryError) {
    NSMutableDictionary *result = [summary mutableCopy];
    NSMutableDictionary *source = [summary[@"source"] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (limits) {
        result[@"limits"] = NormalizeLimitDictionary(limits, NSDate.date);
        source[@"limitsObservedAt"] = LocalISOString(NSDate.date);
        source[@"limitsOrigin"] = @"server";
        [source removeObjectForKey:@"quotaQueryError"];
    } else {
        NSDate *oldDate = DisplayDateFromString(previous[@"source"][@"limitsObservedAt"]);
        NSDate *logDate = DisplayDateFromString(source[@"limitsObservedAt"]);
        if (oldDate && (!logDate || [oldDate compare:logDate] != NSOrderedAscending)) {
            result[@"limits"] = NormalizeLimitDictionary(previous[@"limits"], NSDate.date);
            source[@"limitsObservedAt"] = previous[@"source"][@"limitsObservedAt"];
            source[@"limitsOrigin"] = previous[@"source"][@"limitsOrigin"] ?: @"log";
        } else {
            source[@"limitsOrigin"] = @"log";
        }
        source[@"quotaQueryError"] = queryError.localizedDescription ?: @"未取得可用的账号额度，保留上次读数";
    }
    result[@"source"] = source;
    return result;
}

static NSString *QuotaSourceTitle(NSDictionary *summary) {
    return [summary[@"source"][@"limitsOrigin"] isEqual:@"server"] ? @"额度查询（账号）" : @"额度快照（本地日志）";
}

static NSDictionary *CollectAndSave(NSError **errorOut) {
    NSDictionary *previous = LoadSummary();
    NSError *collectionError = nil;
    NSDictionary *summary = CollectUsage(&collectionError);
    if (!summary) {
        summary = @{@"version": @1, @"updatedAt": LocalISOString(NSDate.date),
                    @"source": @{@"tokenCollectionError": collectionError.localizedDescription ?: @"本地日志采集失败"},
                    @"usage": previous[@"usage"] ?: @{}, @"limits": previous[@"limits"] ?: @{}};
    }
    NSError *queryError = nil;
    NSDictionary *response = QueryCodexQuota(CodexExecutable(), 15, &queryError);
    summary = SummaryWithQuota(summary, previous, LiveLimitDictionary(response), queryError);
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

static BOOL ShouldDisplaySecondaryInStatus(NSDictionary *primary, NSDictionary *secondary) {
    NSNumber *primaryUsed = NumberOrNil(primary[@"usedPercent"]);
    NSNumber *secondaryUsed = NumberOrNil(secondary[@"usedPercent"]);
    if (!secondaryUsed) return NO;
    if (!primaryUsed) return YES;

    double primaryRemaining = RemainingPercentValue(primaryUsed);
    double secondaryRemaining = RemainingPercentValue(secondaryUsed);
    return secondaryRemaining < 10.0 && secondaryRemaining * 7.0 < primaryRemaining;
}

static NSDictionary *StatusLimit(NSDictionary *summary, BOOL *showsSecondary) {
    NSDictionary *primary = PrimaryLimit(summary);
    NSDictionary *secondary = SecondaryLimit(summary);
    BOOL useSecondary = ShouldDisplaySecondaryInStatus(primary, secondary);
    if (showsSecondary) {
        *showsSecondary = useSecondary;
    }
    return useSecondary ? secondary : primary;
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

static void SetStatusDisplay(NSStatusItem *statusItem, NSString *title, double remaining, BOOL hasData, NSString *toolTip) {
    if (!statusItem.button) {
        return;
    }

    statusItem.button.attributedTitle = [[NSAttributedString alloc] initWithString:@""];
    statusItem.button.title = title ?: @"--";
    statusItem.button.image = StatusDisplayImage(remaining, hasData);
    statusItem.button.imagePosition = NSImageLeft;
    statusItem.button.imageScaling = NSImageScaleProportionallyDown;
    statusItem.button.contentTintColor = nil;
    statusItem.button.toolTip = toolTip ?: @"Codex 使用情况";
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

@interface CodexUsageAppDelegate : NSObject <NSApplicationDelegate, NSPopoverDelegate, NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSStatusItem *diskStatusItem;
@property(nonatomic, strong) NSTimer *diskTimer;
@property(nonatomic, strong) NSDictionary *diskSnapshot;
@property(nonatomic, copy) NSString *diskError;
@property(nonatomic, assign) BOOL diskMonitoringEnabled;
@property(nonatomic, assign) BOOL diskRefreshing;
@property(nonatomic, assign) NSUInteger diskGeneration;
- (void)refreshDisk:(id)sender;
- (NSDictionary *)readDiskSnapshot:(NSError **)error;
- (BOOL)acceptDiskSnapshot:(NSDictionary *)snapshot error:(NSError *)error generation:(NSUInteger)generation;
- (void)updateDiskDisplay;
- (void)preferencesChanged:(NSNotification *)notification;
@property(nonatomic, strong) NSPopover *popover;
@property(nonatomic, strong) id localPopoverMonitor;
@property(nonatomic, strong) id globalPopoverMonitor;
@property(nonatomic, assign) BOOL diskMenuTracking;
- (void)closePopover;
- (void)stopPopoverEventMonitors;
- (void)startPopoverEventMonitors;
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
        SetStatusDisplay(self.statusItem, @"--", 0, NO, @"Codex 使用情况");
        self.statusItem.button.target = self;
        self.statusItem.button.action = @selector(togglePopover:);
        [self.statusItem.button sendActionOn:(NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp)];
    }
    [NSDistributedNotificationCenter.defaultCenter addObserver:self selector:@selector(preferencesChanged:) name:PreferencesChangedNotification object:nil];
    [self applyDiskPreference];
    self.summary = LoadSummary();
    [self rebuildMenu];
    [self updateWindowContent];
    [self refresh:nil];
    NSTimer *timer = [NSTimer timerWithTimeInterval:60 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
    timer.tolerance = 10;
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    NSTimer *health = [NSTimer timerWithTimeInterval:15 target:self selector:@selector(checkFreshness:) userInfo:nil repeats:YES];
    health.tolerance = 2;
    [NSRunLoop.mainRunLoop addTimer:health forMode:NSRunLoopCommonModes];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(didWake:) name:NSWorkspaceDidWakeNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(workspaceApplicationActivated:) name:NSWorkspaceDidActivateApplicationNotification object:nil];

    if (self.showWindowOnLaunch) {
        [self showWindow:nil];
    }
}

- (void)didWake:(NSNotification *)notification {
    [self checkFreshness:nil];
    [self refresh:nil];
    if (self.diskMonitoringEnabled) [self refreshDisk:nil];
}

- (BOOL)codexDataIsStale {
    NSDate *snapshot = DisplayDateFromString(self.summary[@"source"][@"limitsObservedAt"]);
    NSDate *scan = DisplayDateFromString(self.summary[@"updatedAt"]);
    return DataIsStale(snapshot, NSDate.date) || DataIsStale(scan, NSDate.date) || self.lastErrorMessage.length > 0 ||
        StringOrNil(self.summary[@"source"][@"quotaQueryError"]).length > 0;
}

- (void)checkFreshness:(id)sender {
    // Independent of collection completion, so a stalled read cannot keep a green status.
    [self rebuildMenu];
    if (self.diskMonitoringEnabled) [self updateDiskDisplay];
    if (self.window.visible) [self updateWindowContent];
}

- (NSButton *)diskPreferenceButton {
    NSButton *button = [NSButton checkboxWithTitle:@"在菜单栏显示磁盘剩余空间" target:self action:@selector(toggleDiskMonitoring:)];
    button.state = [MonitorPreferences() boolForKey:DiskMonitoringPreference] ? NSControlStateValueOn : NSControlStateValueOff;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.toolTip = @"默认关闭；勾选后开始读取系统数据卷容量，取消后停止后台监测";
    return button;
}

- (void)toggleDiskMonitoring:(NSButton *)sender {
    NSUserDefaults *preferences = MonitorPreferences();
    [preferences setBool:sender.state == NSControlStateValueOn forKey:DiskMonitoringPreference];
    [preferences synchronize];
    [self preferencesChanged:nil];
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:PreferencesChangedNotification object:nil userInfo:nil deliverImmediately:YES];
}

- (void)preferencesChanged:(NSNotification *)notification {
    [MonitorPreferences() synchronize];
    [self applyDiskPreference];
    if (self.popover.shown) [self updatePopoverContent];
    if (self.window.visible) [self updateWindowContent];
}

- (void)applyDiskPreference {
    // A separately opened dashboard edits the shared preference; only the resident app monitors.
    if (self.showWindowOnLaunch) return;
    [self setDiskMonitoringActive:[MonitorPreferences() boolForKey:DiskMonitoringPreference]];
}

- (void)setDiskMonitoringActive:(BOOL)enabled {
    if (enabled == self.diskMonitoringEnabled) return;
    self.diskMonitoringEnabled = enabled;
    self.diskGeneration += 1; // Invalidate any read already in flight when the option changes.
    [self.diskTimer invalidate];
    self.diskTimer = nil;
    self.diskRefreshing = NO;
    self.diskSnapshot = nil;
    self.diskError = nil;
    if (!enabled) {
        if (self.diskStatusItem) [NSStatusBar.systemStatusBar removeStatusItem:self.diskStatusItem];
        self.diskStatusItem = nil;
        return;
    }
    self.diskStatusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.diskStatusItem.autosaveName = @"com.gukai.CodexUsage.disk";
    [self updateDiskDisplay];
    [self refreshDisk:nil];
    self.diskTimer = [NSTimer timerWithTimeInterval:60 target:self selector:@selector(refreshDisk:) userInfo:nil repeats:YES];
    self.diskTimer.tolerance = 10;
    [NSRunLoop.mainRunLoop addTimer:self.diskTimer forMode:NSRunLoopCommonModes];
}

- (NSDictionary *)readDiskSnapshot:(NSError **)error {
    return ReadDiskSnapshot([NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES], error);
}

- (BOOL)acceptDiskSnapshot:(NSDictionary *)snapshot error:(NSError *)error generation:(NSUInteger)generation {
    if (!self.diskMonitoringEnabled || generation != self.diskGeneration) return NO;
    self.diskRefreshing = NO;
    if (snapshot) {
        self.diskSnapshot = snapshot;
        self.diskError = nil;
    } else {
        self.diskError = error.localizedDescription ?: @"无法读取磁盘容量";
    }
    [self updateDiskDisplay];
    return YES;
}

- (void)refreshDisk:(id)sender {
    if (!self.diskMonitoringEnabled || self.diskRefreshing) return;
    self.diskRefreshing = YES;
    NSUInteger generation = self.diskGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSDictionary *snapshot = [self readDiskSnapshot:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self acceptDiskSnapshot:snapshot error:error generation:generation];
        });
    });
}

static NSImage *DiskStatusDisplayImage(NSString *title) {
    NSDictionary *attributes = @{
        NSForegroundColorAttributeName: NSColor.whiteColor,
        NSFontAttributeName: [NSFont menuBarFontOfSize:0]
    };
    NSSize textSize = [title sizeWithAttributes:attributes];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(ceil(textSize.width) + 22, 18)];
    [image lockFocus];
    NSImage *symbol = [[NSImage imageWithSystemSymbolName:@"internaldrive" accessibilityDescription:nil]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.whiteColor]]];
    [symbol drawInRect:NSMakeRect(0, 1, 17, 16)];
    [title drawAtPoint:NSMakePoint(22, floor((18 - textSize.height) / 2)) withAttributes:attributes];
    [image unlockFocus];
    image.template = NO;
    return image;
}

- (void)updateDiskDisplay {
    if (!self.diskMonitoringEnabled || !self.diskStatusItem) return;
    BOOL stale = DataIsStale(self.diskSnapshot[@"observedAt"], NSDate.date) || self.diskError.length > 0;
    NSInteger warning = DiskWarningLevel(self.diskSnapshot);
    NSStatusBarButton *button = self.diskStatusItem.button;
    NSString *space = self.diskSnapshot ? DiskCapacityText([self.diskSnapshot[@"available"] longLongValue]) : @"--";
    NSString *title = [NSString stringWithFormat:@"%@余 %@", stale ? @"⚠︎ " : @"", space];
    button.title = @"";
    button.attributedTitle = [[NSAttributedString alloc] initWithString:@""];
    button.image = DiskStatusDisplayImage(title);
    button.imagePosition = NSImageOnly;
    button.contentTintColor = nil;
    button.accessibilityLabel = [@"磁盘剩余空间 " stringByAppendingString:title];
    button.toolTip = stale ? @"磁盘数据未更新或读取失败，当前为上次读数" : @"系统数据卷可用空间";
    // Never replace a menu while AppKit is tracking its outside-click dismissal.
    if (self.diskMenuTracking) return;
    NSMenu *menu = self.diskStatusItem.menu ?: [[NSMenu alloc] init];
    menu.delegate = self;
    [menu removeAllItems];
    if (self.diskSnapshot) {
        long long total = [self.diskSnapshot[@"total"] longLongValue];
        long long available = [self.diskSnapshot[@"available"] longLongValue];
        for (NSString *line in @[
            [NSString stringWithFormat:@"磁盘：%@", self.diskSnapshot[@"name"]],
            [NSString stringWithFormat:@"总容量：%@", DiskCapacityText(total)],
            [NSString stringWithFormat:@"可用空间：%@", DiskCapacityText(available)],
            [NSString stringWithFormat:@"使用比例（估算）：%.1f%%", 100.0 * (total - available) / total],
            [NSString stringWithFormat:@"读取时间：%@", ResetDisplay(LocalISOString(self.diskSnapshot[@"observedAt"]))],
            [self.diskSnapshot[@"includesPurgeable"] boolValue] ? @"可用空间包含 macOS 可清理空间" : @"可用空间为当前空闲容量"]) {
            [menu addItemWithTitle:line action:nil keyEquivalent:@""];
        }
    }
    if (stale) [menu addItemWithTitle:self.diskError ?: @"⚠︎ 超过 3 分钟未取得新数据" action:nil keyEquivalent:@""];
    if (warning > 0) [menu addItemWithTitle:@"⚠︎ 磁盘可用空间不足" action:nil keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *refresh = [menu addItemWithTitle:@"立即刷新" action:@selector(refreshDisk:) keyEquivalent:@""];
    refresh.target = self;
    NSMenuItem *disable = [menu addItemWithTitle:@"关闭磁盘监测" action:@selector(disableDiskMonitoring:) keyEquivalent:@""];
    disable.target = self;
    self.diskStatusItem.menu = menu;
}

- (void)disableDiskMonitoring:(id)sender {
    NSButton *button = [[NSButton alloc] init];
    button.state = NSControlStateValueOff;
    [self toggleDiskMonitoring:button];
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    [self closePopover];
}

- (void)workspaceApplicationActivated:(NSNotification *)notification {
    NSRunningApplication *application = notification.userInfo[NSWorkspaceApplicationKey];
    if (application.processIdentifier != NSProcessInfo.processInfo.processIdentifier) [self closePopover];
}

- (void)menuWillOpen:(NSMenu *)menu {
    if (menu == self.diskStatusItem.menu) {
        self.diskMenuTracking = YES;
        [self closePopover];
    }
}

- (void)menuDidClose:(NSMenu *)menu {
    if (menu == self.diskStatusItem.menu) {
        self.diskMenuTracking = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateDiskDisplay]; });
    }
}

- (void)showDiskDetails:(id)sender {
    [self closePopover];
    [self.diskStatusItem.button performClick:sender];
}

- (void)refresh:(id)sender {
    if (self.refreshing) {
        return;
    }

    self.refreshing = YES;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSDictionary *summary = CollectAndSave(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.refreshing = NO;
            if (summary) {
                self.summary = summary;
                self.lastErrorMessage = StringOrNil(summary[@"source"][@"quotaQueryError"]) ?: StringOrNil(summary[@"source"][@"tokenCollectionError"]);
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

    BOOL showsSecondary = NO;
    NSDictionary *limit = StatusLimit(self.summary, &showsSecondary);
    NSNumber *usedPercent = NumberOrNil(limit[@"usedPercent"]);
    NSString *remainingText = RemainingPercentText(usedPercent);
    NSString *reset = ResetDisplay(StringOrNil(limit[@"resetsAt"]));
    BOOL stale = [self codexDataIsStale];
    NSString *statusTitle = [NSString stringWithFormat:@"%@%@ %@", stale ? @"⚠︎ " : @"", remainingText, reset];
    NSString *toolTip = [NSString stringWithFormat:@"Codex · %@窗口 · %@ %@", WindowTitle(limit), QuotaSourceTitle(self.summary), ResetDisplay(self.summary[@"source"][@"limitsObservedAt"])];
    if (usedPercent) {
        double remaining = RemainingPercentValue(usedPercent);
        SetStatusDisplay(self.statusItem, statusTitle, remaining, YES, toolTip);
    } else {
        SetStatusDisplay(self.statusItem, statusTitle, 0, NO, @"Codex 使用情况");
    }
    if (stale) {
        self.statusItem.button.toolTip = [toolTip stringByAppendingString:@" · 额度查询失败或超过 3 分钟未更新，当前为旧读数"];
        self.statusItem.button.contentTintColor = NSColor.systemOrangeColor;
    }
    self.statusItem.menu = nil;
    if (self.popover.shown) {
        [self updatePopoverContent];
    }
}

- (void)togglePopover:(id)sender {
    if (self.popover.shown) {
        [self closePopover];
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
        self.popover.animates = NO;
        self.popover.delegate = self;
    }
    [self updatePopoverContent];
    [self.popover showRelativeToRect:self.statusItem.button.bounds
                               ofView:self.statusItem.button
                        preferredEdge:NSRectEdgeMinY];
    if (self.popover.shown) [self startPopoverEventMonitors];
}

- (void)handlePopoverMouseAtPoint:(NSPoint)point {
    if (!self.popover.shown) return;
    NSWindow *panel = self.popover.contentViewController.view.window;
    NSStatusBarButton *button = self.statusItem.button;
    NSRect buttonFrame = button.window ? [button.window convertRectToScreen:[button convertRect:button.bounds toView:nil]] : NSZeroRect;
    if (ShouldDismissPopoverClick(point, panel.frame, buttonFrame)) [self closePopover];
}

- (void)startPopoverEventMonitors {
    [self stopPopoverEventMonitors];
    __weak typeof(self) weakSelf = self;
    NSEventMask clicks = NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown;
    self.localPopoverMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:clicks | NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event.type == NSEventTypeKeyDown) {
            if (event.keyCode == 53 && weakSelf.popover.shown) {
                [weakSelf closePopover];
                return nil;
            }
        } else {
            NSPoint point = event.window ? [event.window convertPointToScreen:event.locationInWindow] : NSEvent.mouseLocation;
            [weakSelf handlePopoverMouseAtPoint:point];
        }
        return event; // Preserve delivery of the original click to the other window.
    }];
    // Mouse clicks only: no global keyboard monitoring or accessibility permission.
    self.globalPopoverMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:clicks handler:^(NSEvent *event) {
        [weakSelf handlePopoverMouseAtPoint:NSEvent.mouseLocation];
    }];
}

- (void)stopPopoverEventMonitors {
    if (self.localPopoverMonitor) [NSEvent removeMonitor:self.localPopoverMonitor];
    if (self.globalPopoverMonitor) [NSEvent removeMonitor:self.globalPopoverMonitor];
    self.localPopoverMonitor = nil;
    self.globalPopoverMonitor = nil;
}

- (void)closePopover {
    [self stopPopoverEventMonitors];
    [self.popover close];
}

- (void)popoverDidClose:(NSNotification *)notification {
    [self stopPopoverEventMonitors];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self stopPopoverEventMonitors];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
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

        for (NSDictionary *window in @[primary ?: @{}, secondary ?: @{}]) {
            if (!window.count) continue;
            NSString *name = WindowTitle(window);
            [stack addArrangedSubview:[self popoverRowWithTitle:[name stringByAppendingString:@"剩余"]
                value:RemainingPercentText(window[@"usedPercent"])
                valueColor:UsageColorForRemaining(RemainingPercentValue(window[@"usedPercent"])) emphasized:YES]];
            NSDate *reset = DisplayDateFromString(window[@"resetsAt"]);
            NSString *resetText = reset && [reset timeIntervalSinceNow] <= 0 ? @"已到期，等待 Codex 更新" : ResetDisplay(window[@"resetsAt"]);
            [stack addArrangedSubview:[self popoverRowWithTitle:[name stringByAppendingString:@"重置"] value:resetText emphasized:NO]];
        }
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
        [stack addArrangedSubview:[self popoverRowWithTitle:QuotaSourceTitle(self.summary) value:ResetDisplay(self.summary[@"source"][@"limitsObservedAt"]) emphasized:NO]];
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

    if ([self codexDataIsStale]) {
        NSTextField *warning = [self popoverLabelWithString:@"⚠︎ 额度查询失败或超过 3 分钟未更新，当前为旧读数"
            font:[NSFont systemFontOfSize:11] color:NSColor.systemOrangeColor];
        warning.maximumNumberOfLines = 2;
        warning.lineBreakMode = NSLineBreakByWordWrapping;
        [stack addArrangedSubview:warning];
    }
    [stack addArrangedSubview:[self diskPreferenceButton]];
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
    BOOL hadWindow = self.window != nil;
    [self ensureWindow];
    if (!hadWindow) [self updateWindowContent];
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

    NSRect frame = NSMakeRect(0, 0, 520, 520);
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
    [stack addArrangedSubview:[self diskPreferenceButton]];
    if (self.diskMonitoringEnabled) {
        NSString *value = self.diskSnapshot ? DiskCapacityText([self.diskSnapshot[@"available"] longLongValue]) : (self.diskError ?: @"正在读取…");
        [stack addArrangedSubview:[self windowRowWithTitle:@"磁盘可用空间" value:value emphasized:NO]];
        NSButton *details = [NSButton buttonWithTitle:@"磁盘详情" target:self action:@selector(showDiskDetails:)];
        [stack addArrangedSubview:details];
    }
    if ([self codexDataIsStale]) {
        NSTextField *warning = [self windowLabelWithString:@"⚠︎ 额度查询失败或超过 3 分钟未更新，当前为旧读数"
            font:[NSFont systemFontOfSize:12] color:NSColor.systemOrangeColor];
        warning.maximumNumberOfLines = 2;
        warning.lineBreakMode = NSLineBreakByWordWrapping;
        [stack addArrangedSubview:warning];
    }
    [stack addArrangedSubview:[self windowRowWithTitle:QuotaSourceTitle(self.summary) value:ResetDisplay(self.summary[@"source"][@"limitsObservedAt"]) emphasized:NO]];

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

    for (NSDictionary *window in @[primary ?: @{}, secondary ?: @{}]) {
        if (!window.count) continue;
        NSString *name = WindowTitle(window);
        [stack addArrangedSubview:[self windowRowWithTitle:[name stringByAppendingString:@"剩余"]
            value:RemainingPercentText(window[@"usedPercent"])
            valueColor:UsageColorForRemaining(RemainingPercentValue(window[@"usedPercent"])) emphasized:YES]];
        NSDate *reset = DisplayDateFromString(window[@"resetsAt"]);
        NSString *resetText = reset && [reset timeIntervalSinceNow] <= 0 ? @"已到期，等待 Codex 更新" : ResetDisplay(window[@"resetsAt"]);
        [stack addArrangedSubview:[self windowRowWithTitle:[name stringByAppendingString:@"重置"] value:resetText emphasized:NO]];
    }
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
    printf("Primary left: %s used %s reset %s\n", [RemainingPercentText(primary[@"usedPercent"]) UTF8String], [PercentText(primary[@"usedPercent"]) UTF8String], [ClockDisplay(StringOrNil(primary[@"resetsAt"])) UTF8String]);
    printf("Secondary left: %s used %s reset %s\n", [RemainingPercentText(secondary[@"usedPercent"]) UTF8String], [PercentText(secondary[@"usedPercent"]) UTF8String], [ResetDisplay(StringOrNil(secondary[@"resetsAt"])) UTF8String]);
    printf("%s\n", [BucketLine(@"Today", UsageBucketDict(summary, @"today")) UTF8String]);
    printf("%s\n", [BucketLine(@"All time", UsageBucketDict(summary, @"allTime")) UTF8String]);
    printf("Summary: %s\n", [SummaryPath() UTF8String]);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        if ([arguments containsObject:@"--disk-monitoring=on"] || [arguments containsObject:@"--disk-monitoring=off"]) {
            BOOL enabled = [arguments containsObject:@"--disk-monitoring=on"];
            [MonitorPreferences() setBool:enabled forKey:DiskMonitoringPreference];
            [MonitorPreferences() synchronize];
            [NSDistributedNotificationCenter.defaultCenter postNotificationName:PreferencesChangedNotification object:nil userInfo:nil deliverImmediately:YES];
            printf("Disk monitoring: %s\n", [MonitorPreferences() boolForKey:DiskMonitoringPreference] ? "enabled" : "disabled");
            return 0;
        }
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

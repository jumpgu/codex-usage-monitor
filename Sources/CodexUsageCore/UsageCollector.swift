import Foundation

public enum UsageCollectorError: Error, LocalizedError {
    case noCodexSessionDirectory

    public var errorDescription: String? {
        switch self {
        case .noCodexSessionDirectory:
            return "No Codex session directory was found under ~/.codex."
        }
    }
}

public struct UsageCollector: Sendable {
    public init() {}

    public func collectAndWrite(now: Date = Date()) throws -> UsageSummary {
        let summary = try collect(now: now)
        try UsageSummaryStore.save(summary)
        return summary
    }

    public func collect(now: Date = Date()) throws -> UsageSummary {
        let sessionsRoot = SharedPaths.sessionsRoot
        let archivedSessionsRoot = SharedPaths.archivedSessionsRoot

        guard FileManager.default.fileExists(atPath: sessionsRoot.path)
            || FileManager.default.fileExists(atPath: archivedSessionsRoot.path)
        else {
            throw UsageCollectorError.noCodexSessionDirectory
        }

        let files = jsonlFiles(under: sessionsRoot) + jsonlFiles(under: archivedSessionsRoot)
        let todayStart = startOfShanghaiDay(for: now)
        let fiveHoursAgo = now.addingTimeInterval(-5 * 60 * 60)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)

        var last5h = UsageBucket()
        var today = UsageBucket()
        var last7d = UsageBucket()
        var allTime = UsageBucket()
        var sessionsWithUsage = 0
        var firstEventAt: Date?
        var lastEventAt: Date?
        var latestLimits: (date: Date, value: LimitSummary)?

        for file in files {
            var fileHasUsage = false
            try parseTokenEvents(in: file) { event in
                firstEventAt = minDate(firstEventAt, event.timestamp)
                lastEventAt = maxDate(lastEventAt, event.timestamp)

                if let limits = event.limits {
                    if latestLimits == nil || event.timestamp >= latestLimits!.date {
                        latestLimits = (event.timestamp, limits)
                    }
                }

                guard let usage = event.usage else { return }
                fileHasUsage = true
                allTime.add(usage)

                if event.timestamp >= fiveHoursAgo {
                    last5h.add(usage)
                }
                if event.timestamp >= todayStart {
                    today.add(usage)
                }
                if event.timestamp >= sevenDaysAgo {
                    last7d.add(usage)
                }
            }

            if fileHasUsage {
                sessionsWithUsage += 1
            }
        }

        let normalizedLimits = latestLimits.map { normalizeLimits($0.value, now: now) }

        return UsageSummary(
            version: 1,
            updatedAt: DateFormatters.string(from: now),
            source: SourceSummary(
                sessionsRoot: abbreviateHome(sessionsRoot.path),
                archivedSessionsRoot: abbreviateHome(archivedSessionsRoot.path),
                filesScanned: files.count,
                sessionsWithUsage: sessionsWithUsage,
                firstEventAt: firstEventAt.map(DateFormatters.string(from:)),
                lastEventAt: lastEventAt.map(DateFormatters.string(from:))
            ),
            limits: normalizedLimits ?? LimitSummary(
                planType: nil,
                primary: nil,
                secondary: nil,
                rateLimitReachedType: nil
            ),
            usage: UsageWindows(
                last5h: last5h,
                today: today,
                last7d: last7d,
                allTime: allTime
            )
        )
    }

    private func jsonlFiles(under root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }

        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            if (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true {
                files.append(url)
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private func parseTokenEvents(in file: URL, handle: (TokenEvent) throws -> Void) throws {
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        let tokenNeedle = Array(#""token_count""#.utf8)

        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }

            var lineStart = 0
            var index = 0

            while index <= data.count {
                if index == data.count || base[index] == 10 {
                    let lineEnd = index
                    if lineEnd > lineStart,
                       bufferContains(base: base, start: lineStart, end: lineEnd, needle: tokenNeedle) {
                        let lineData = Data(bytes: base.advanced(by: lineStart), count: lineEnd - lineStart)
                        if let event = parseTokenEvent(from: lineData) {
                            try handle(event)
                        }
                    }
                    lineStart = index + 1
                }
                index += 1
            }
        }
    }

    private func bufferContains(base: UnsafePointer<UInt8>, start: Int, end: Int, needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, end - start >= needle.count else { return false }
        var i = start
        let maxStart = end - needle.count
        while i <= maxStart {
            if base[i] == needle[0] {
                var matched = true
                for offset in 1..<needle.count where base[i + offset] != needle[offset] {
                    matched = false
                    break
                }
                if matched { return true }
            }
            i += 1
        }
        return false
    }

    private func parseTokenEvent(from lineData: Data) -> TokenEvent? {
        guard
            let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
            let timestampString = object["timestamp"] as? String,
            let timestamp = DateFormatters.codexDate(from: timestampString),
            let payload = object["payload"] as? [String: Any],
            payload["type"] as? String == "token_count"
        else {
            return nil
        }

        let info = payload["info"] as? [String: Any]
        let lastUsage = (info?["last_token_usage"] as? [String: Any]).flatMap(parseUsage)
        let rateLimits = (payload["rate_limits"] as? [String: Any]).flatMap(parseLimits)

        return TokenEvent(timestamp: timestamp, usage: lastUsage, limits: rateLimits)
    }

    private func parseUsage(_ dictionary: [String: Any]) -> TokenUsage? {
        guard let totalTokens = int64Value(dictionary["total_tokens"]) else {
            return nil
        }

        return TokenUsage(
            inputTokens: int64Value(dictionary["input_tokens"]) ?? 0,
            cachedInputTokens: int64Value(dictionary["cached_input_tokens"]) ?? 0,
            outputTokens: int64Value(dictionary["output_tokens"]) ?? 0,
            reasoningOutputTokens: int64Value(dictionary["reasoning_output_tokens"]) ?? 0,
            totalTokens: totalTokens
        )
    }

    private func parseLimits(_ dictionary: [String: Any]) -> LimitSummary? {
        guard
            dictionary["limit_id"] as? String == "codex",
            dictionary["plan_type"] is String
        else {
            return nil
        }

        return LimitSummary(
            planType: dictionary["plan_type"] as? String,
            primary: (dictionary["primary"] as? [String: Any]).flatMap(parseRateLimitWindow),
            secondary: (dictionary["secondary"] as? [String: Any]).flatMap(parseRateLimitWindow),
            rateLimitReachedType: dictionary["rate_limit_reached_type"] as? String
        )
    }

    private func parseRateLimitWindow(_ dictionary: [String: Any]) -> RateLimitWindow? {
        guard
            let usedPercent = doubleValue(dictionary["used_percent"]),
            let windowMinutes = intValue(dictionary["window_minutes"])
        else {
            return nil
        }

        let resetsAt = int64Value(dictionary["resets_at"])
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
            .map(DateFormatters.string(from:))

        return RateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private func normalizeLimits(_ limits: LimitSummary, now: Date) -> LimitSummary {
        guard
            var primary = limits.primary,
            let resetsAt = primary.resetsAt,
            let resetDate = DateFormatters.localISO.date(from: resetsAt) ?? ISO8601DateFormatter().date(from: resetsAt),
            resetDate <= now
        else {
            return limits
        }

        primary.usedPercent = 0
        primary.resetsAt = DateFormatters.string(from: nextLocalWindowReset(now: now, windowMinutes: primary.windowMinutes))

        var normalized = limits
        normalized.primary = primary
        return normalized
    }

    private func nextLocalWindowReset(now: Date, windowMinutes: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

        var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        components.minute = 0
        components.second = 0
        components.nanosecond = 0

        let hourStart = calendar.date(from: components) ?? now
        return calendar.date(byAdding: .minute, value: max(windowMinutes, 1), to: hourStart)
            ?? hourStart.addingTimeInterval(TimeInterval(max(windowMinutes, 1) * 60))
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func startOfShanghaiDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar.startOfDay(for: date)
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func minDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return min(lhs, rhs)
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return max(lhs, rhs)
    }
}

private struct TokenEvent {
    var timestamp: Date
    var usage: TokenUsage?
    var limits: LimitSummary?
}

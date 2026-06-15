import Foundation

public let codexUsageAppGroupIdentifier = "group.com.gukai.CodexUsage"
public let codexUsageControlKind = "com.gukai.CodexUsage.refresh"

public struct UsageSummary: Codable, Sendable {
    public var version: Int
    public var updatedAt: String
    public var source: SourceSummary
    public var limits: LimitSummary
    public var usage: UsageWindows

    public init(version: Int, updatedAt: String, source: SourceSummary, limits: LimitSummary, usage: UsageWindows) {
        self.version = version
        self.updatedAt = updatedAt
        self.source = source
        self.limits = limits
        self.usage = usage
    }
}

public struct SourceSummary: Codable, Sendable {
    public var sessionsRoot: String
    public var archivedSessionsRoot: String
    public var filesScanned: Int
    public var sessionsWithUsage: Int
    public var firstEventAt: String?
    public var lastEventAt: String?

    public init(
        sessionsRoot: String,
        archivedSessionsRoot: String,
        filesScanned: Int,
        sessionsWithUsage: Int,
        firstEventAt: String?,
        lastEventAt: String?
    ) {
        self.sessionsRoot = sessionsRoot
        self.archivedSessionsRoot = archivedSessionsRoot
        self.filesScanned = filesScanned
        self.sessionsWithUsage = sessionsWithUsage
        self.firstEventAt = firstEventAt
        self.lastEventAt = lastEventAt
    }
}

public struct LimitSummary: Codable, Sendable {
    public var planType: String?
    public var primary: RateLimitWindow?
    public var secondary: RateLimitWindow?
    public var rateLimitReachedType: String?

    public init(
        planType: String?,
        primary: RateLimitWindow?,
        secondary: RateLimitWindow?,
        rateLimitReachedType: String?
    ) {
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.rateLimitReachedType = rateLimitReachedType
    }
}

public struct RateLimitWindow: Codable, Sendable {
    public var usedPercent: Double
    public var windowMinutes: Int
    public var resetsAt: String?

    public init(usedPercent: Double, windowMinutes: Int, resetsAt: String?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public struct UsageWindows: Codable, Sendable {
    public var last5h: UsageBucket
    public var today: UsageBucket
    public var last7d: UsageBucket
    public var allTime: UsageBucket

    public init(last5h: UsageBucket, today: UsageBucket, last7d: UsageBucket, allTime: UsageBucket) {
        self.last5h = last5h
        self.today = today
        self.last7d = last7d
        self.allTime = allTime
    }
}

public struct UsageBucket: Codable, Sendable {
    public var events: Int
    public var inputTokens: Int64
    public var cachedInputTokens: Int64
    public var outputTokens: Int64
    public var reasoningOutputTokens: Int64
    public var totalTokens: Int64
    public var nonCachedApproxTokens: Int64

    public init(
        events: Int = 0,
        inputTokens: Int64 = 0,
        cachedInputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        reasoningOutputTokens: Int64 = 0,
        totalTokens: Int64 = 0
    ) {
        self.events = events
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
        self.nonCachedApproxTokens = max(0, totalTokens - cachedInputTokens)
    }

    public mutating func add(_ usage: TokenUsage) {
        events += 1
        inputTokens += usage.inputTokens
        cachedInputTokens += usage.cachedInputTokens
        outputTokens += usage.outputTokens
        reasoningOutputTokens += usage.reasoningOutputTokens
        totalTokens += usage.totalTokens
        nonCachedApproxTokens = max(0, totalTokens - cachedInputTokens)
    }
}

public struct TokenUsage: Sendable {
    public var inputTokens: Int64
    public var cachedInputTokens: Int64
    public var outputTokens: Int64
    public var reasoningOutputTokens: Int64
    public var totalTokens: Int64
}

public enum UsageFormatting {
    public static func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }

    public static func remainingPercentText(_ usedValue: Double?) -> String {
        guard let usedValue else { return "--" }
        let remaining = min(max(100 - usedValue, 0), 100)
        return "\(Int(remaining.rounded()))%"
    }

    public static func shortPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))"
    }

    public static func tokensText(_ tokens: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
    }

    public static func yiTokens(_ tokens: Int64, digits: Int = 2) -> String {
        let value = Double(tokens) / 100_000_000
        return String(format: "%.\(digits)f 亿", value)
    }

    public static func resetText(_ isoString: String?) -> String {
        guard
            let isoString,
            let date = DateFormatters.localISO.date(from: isoString)
                ?? ISO8601DateFormatter().date(from: isoString)
        else {
            return "--"
        }

        let calendar = Calendar(identifier: .gregorian)
        let localCalendar = calendarWithShanghaiTimeZone(calendar)
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.locale = Locale(identifier: "zh_CN")

        if localCalendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M/d HH:mm"
        }
        return formatter.string(from: date)
    }

    private static func calendarWithShanghaiTimeZone(_ calendar: Calendar) -> Calendar {
        var copy = calendar
        copy.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return copy
    }
}

public enum SharedPaths {
    public static var summaryURL: URL {
        return applicationSupportDirectory.appendingPathComponent("usage_summary.json")
    }

    public static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CodexUsage", isDirectory: true)
    }

    public static var fallbackSummaryURL: URL {
        applicationSupportDirectory.appendingPathComponent("usage_summary.json")
    }

    public static var sessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    public static var archivedSessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/archived_sessions", isDirectory: true)
    }
}

public enum UsageSummaryStore {
    public static func load() -> UsageSummary? {
        let candidates = [SharedPaths.summaryURL, SharedPaths.fallbackSummaryURL]
        for url in candidates {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let summary = try? JSONDecoder().decode(UsageSummary.self, from: data) {
                return summary
            }
        }
        return nil
    }

    public static func save(_ summary: UsageSummary) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(summary)

        let urls = unique([SharedPaths.summaryURL, SharedPaths.fallbackSummaryURL])
        var lastError: Error?
        var wroteAtLeastOne = false

        for url in urls {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: [.atomic])
                wroteAtLeastOne = true
            } catch {
                lastError = error
            }
        }

        if !wroteAtLeastOne, let lastError {
            throw lastError
        }
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { seen.insert($0.path).inserted }
    }
}

public enum DateFormatters {
    public static let localISO: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter
    }()

    public static let codexTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static let codexTimestampNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func string(from date: Date) -> String {
        localISO.string(from: date)
    }

    public static func codexDate(from string: String) -> Date? {
        codexTimestamp.date(from: string) ?? codexTimestampNoFraction.date(from: string)
    }
}

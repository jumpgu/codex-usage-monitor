import AppIntents
import CodexUsageCore
import SwiftUI
import WidgetKit

@main
struct CodexUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexUsageWidget()

        if #available(macOS 26.0, *) {
            CodexUsageRefreshControl()
        }
    }
}

struct CodexUsageEntry: TimelineEntry {
    let date: Date
    let summary: UsageSummary?
}

struct CodexUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexUsageEntry {
        CodexUsageEntry(date: Date(), summary: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexUsageEntry) -> Void) {
        completion(CodexUsageEntry(date: Date(), summary: UsageSummaryStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexUsageEntry>) -> Void) {
        let entry = CodexUsageEntry(date: Date(), summary: UsageSummaryStore.load())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct CodexUsageWidget: Widget {
    let kind = "com.gukai.CodexUsage.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexUsageProvider()) { entry in
            CodexUsageWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(nsColor: .windowBackgroundColor)
                }
        }
        .configurationDisplayName("Codex Usage")
        .description("Show local Codex token usage and rate-limit windows.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CodexUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexUsageEntry

    var body: some View {
        if let summary = entry.summary {
            switch family {
            case .systemSmall:
                small(summary)
            case .systemMedium:
                medium(summary)
            default:
                large(summary)
            }
        } else {
            unavailable
        }
    }

    private func small(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Codex")
                .font(.headline)
            Spacer(minLength: 0)
            Gauge(value: min(max((summary.limits.primary?.usedPercent ?? 0) / 100, 0), 1)) {
                Text("5h")
            } currentValueLabel: {
                Text(UsageFormatting.remainingPercentText(summary.limits.primary?.usedPercent))
                    .font(.title2.weight(.bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(statusColor(summary.limits.primary?.usedPercent))
            Spacer(minLength: 0)
            Text("left · \(UsageFormatting.resetText(summary.limits.primary?.resetsAt)) reset")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding()
    }

    private func medium(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            header(summary)
            CompactLimitLine(title: "5h", limit: summary.limits.primary)
            CompactLimitLine(title: "7d", limit: summary.limits.secondary)
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(UsageFormatting.yiTokens(summary.usage.today.totalTokens)) total")
                    .font(.caption.monospacedDigit())
                Text("/")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(UsageFormatting.yiTokens(summary.usage.today.nonCachedApproxTokens, digits: 3)) non-cache")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func large(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(summary)
            LimitProgress(title: "5h Window", limit: summary.limits.primary)
            LimitProgress(title: "7d Window", limit: summary.limits.secondary)
            Divider()
            WidgetUsageLine(title: "Today", value: UsageFormatting.yiTokens(summary.usage.today.totalTokens))
            WidgetUsageLine(title: "Today non-cache", value: UsageFormatting.yiTokens(summary.usage.today.nonCachedApproxTokens, digits: 3))
            WidgetUsageLine(title: "7d total", value: UsageFormatting.yiTokens(summary.usage.last7d.totalTokens))
            WidgetUsageLine(title: "All time", value: UsageFormatting.yiTokens(summary.usage.allTime.totalTokens))
            Spacer(minLength: 0)
            HStack {
                Text("Updated")
                Spacer()
                Text(summary.updatedAt)
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func header(_ summary: UsageSummary) -> some View {
        HStack {
            Text("Codex Usage")
                .font(.headline)
            Spacer()
            Text(summary.limits.planType ?? "local")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Codex Usage")
                .font(.headline)
            Spacer()
            Text("No local summary yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Open the menu bar app or wait for the collector.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func statusColor(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        switch percent {
        case ..<50:
            return .green
        case ..<80:
            return .yellow
        case ..<95:
            return .orange
        default:
            return .red
        }
    }
}

struct CompactLimitLine: View {
    var title: String
    var limit: RateLimitWindow?

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 34, alignment: .leading)
            ProgressView(value: min(max((limit?.usedPercent ?? 0) / 100, 0), 1))
                .tint(statusColor)
            Text(UsageFormatting.remainingPercentText(limit?.usedPercent))
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 40, alignment: .trailing)
            Text("\(UsageFormatting.resetText(limit?.resetsAt)) reset")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    private var statusColor: Color {
        guard let percent = limit?.usedPercent else { return .secondary }
        switch percent {
        case ..<50:
            return .green
        case ..<80:
            return .yellow
        case ..<95:
            return .orange
        default:
            return .red
        }
    }
}

struct LimitProgress: View {
    var title: String
    var limit: RateLimitWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("left \(UsageFormatting.remainingPercentText(limit?.usedPercent)) · used \(UsageFormatting.percentText(limit?.usedPercent)) · \(UsageFormatting.resetText(limit?.resetsAt)) reset")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max((limit?.usedPercent ?? 0) / 100, 0), 1))
                .tint(statusColor)
        }
    }

    private var statusColor: Color {
        guard let percent = limit?.usedPercent else { return .secondary }
        switch percent {
        case ..<50:
            return .green
        case ..<80:
            return .yellow
        case ..<95:
            return .orange
        default:
            return .red
        }
    }
}

struct WidgetUsageLine: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
        }
    }
}

@available(macOS 26.0, *)
struct CodexUsageRefreshControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: codexUsageControlKind) {
            ControlWidgetButton(action: RefreshUsageIntent()) {
                Label(controlLabelText, systemImage: "speedometer")
            }
            .tint(controlTint)
        }
        .displayName("Codex Usage")
        .description("Refresh and open local Codex usage.")
    }

    private var controlLabelText: String {
        let summary = UsageSummaryStore.load()
        let percent = UsageFormatting.remainingPercentText(summary?.limits.primary?.usedPercent)
        return "5h \(percent) left"
    }

    private var controlTint: Color {
        guard let percent = UsageSummaryStore.load()?.limits.primary?.usedPercent else {
            return .blue
        }
        switch percent {
        case ..<50:
            return .green
        case ..<80:
            return .yellow
        case ..<95:
            return .orange
        default:
            return .red
        }
    }
}

struct RefreshUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Codex Usage"
    static var description = IntentDescription("Refresh local Codex usage and open the menu bar app.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        _ = try? UsageCollector().collectAndWrite()
        WidgetCenter.shared.reloadAllTimelines()
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadControls(ofKind: codexUsageControlKind)
        }
        return .result()
    }
}

extension UsageSummary {
    static var placeholder: UsageSummary {
        UsageSummary(
            version: 1,
            updatedAt: DateFormatters.string(from: Date()),
            source: SourceSummary(
                sessionsRoot: "~/.codex/sessions",
                archivedSessionsRoot: "~/.codex/archived_sessions",
                filesScanned: 72,
                sessionsWithUsage: 70,
                firstEventAt: nil,
                lastEventAt: nil
            ),
            limits: LimitSummary(
                planType: "prolite",
                primary: RateLimitWindow(usedPercent: 31, windowMinutes: 300, resetsAt: DateFormatters.string(from: Date().addingTimeInterval(3600))),
                secondary: RateLimitWindow(usedPercent: 54, windowMinutes: 10080, resetsAt: DateFormatters.string(from: Date().addingTimeInterval(4 * 24 * 3600))),
                rateLimitReachedType: nil
            ),
            usage: UsageWindows(
                last5h: UsageBucket(events: 24, cachedInputTokens: 61_502_720, totalTokens: 69_445_916),
                today: UsageBucket(events: 30, cachedInputTokens: 63_393_280, totalTokens: 71_857_473),
                last7d: UsageBucket(events: 300, cachedInputTokens: 394_658_048, totalTokens: 435_719_040),
                allTime: UsageBucket(events: 600, cachedInputTokens: 631_311_360, totalTokens: 696_842_842)
            )
        )
    }
}

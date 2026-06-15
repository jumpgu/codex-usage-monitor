import AppKit
import CodexUsageCore
import SwiftUI
import WidgetKit

@main
struct CodexUsageMenuBarApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(viewModel: viewModel)
                .frame(width: 340)
                .padding(14)
        } label: {
            Label(viewModel.menuBarTitle, systemImage: "speedometer")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var summary: UsageSummary?
    @Published var errorMessage: String?
    @Published var isRefreshing = false

    var menuBarTitle: String {
        guard let summary else { return "Codex --" }
        return "Codex \(UsageFormatting.remainingPercentText(summary.limits.primary?.usedPercent)) left"
    }

    init() {
        summary = UsageSummaryStore.load()
        Task { await refresh() }

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let collected = try UsageCollector().collectAndWrite()
            summary = collected
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
            if #available(macOS 26.0, *) {
                ControlCenter.shared.reloadControls(ofKind: codexUsageControlKind)
            }
        } catch {
            errorMessage = error.localizedDescription
            summary = UsageSummaryStore.load()
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}

struct UsageMenuView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            if let summary = viewModel.summary {
                limitRows(summary)
                Divider()
                usageRows(summary)
                Divider()
                metadata(summary)
            } else {
                ContentUnavailableView(
                    "No Codex usage yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Click refresh after Codex has written token_count events.")
                )
                .frame(height: 160)
            }

            actionRow
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Usage")
                    .font(.headline)
                Text("Local token trend, not official billing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: viewModel.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            .disabled(viewModel.isRefreshing)
        }
    }

    @ViewBuilder
    private func limitRows(_ summary: UsageSummary) -> some View {
        VStack(spacing: 10) {
            LimitRow(
                title: "5h Window",
                percent: summary.limits.primary?.usedPercent,
                reset: UsageFormatting.resetText(summary.limits.primary?.resetsAt)
            )
            LimitRow(
                title: "7d Window",
                percent: summary.limits.secondary?.usedPercent,
                reset: UsageFormatting.resetText(summary.limits.secondary?.resetsAt)
            )
        }
    }

    @ViewBuilder
    private func usageRows(_ summary: UsageSummary) -> some View {
        VStack(spacing: 8) {
            UsageValueRow(title: "Last 5h", bucket: summary.usage.last5h)
            UsageValueRow(title: "Today", bucket: summary.usage.today)
            UsageValueRow(title: "Last 7d", bucket: summary.usage.last7d)
            UsageValueRow(title: "All time", bucket: summary.usage.allTime)
        }
    }

    @ViewBuilder
    private func metadata(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Updated")
                Spacer()
                Text(summary.updatedAt)
                    .monospacedDigit()
            }

            HStack {
                Text("Files")
                Spacer()
                Text("\(summary.source.filesScanned) scanned / \(summary.source.sessionsWithUsage) with usage")
            }

            Text("Non-cached approx is total minus cached input. It is a trend signal, not official billing.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var actionRow: some View {
        HStack {
            Spacer()

            Button("Quit") {
                viewModel.quit()
            }
        }
        .controlSize(.small)
    }
}

struct LimitRow: View {
    var title: String
    var percent: Double?
    var reset: String

    var body: some View {
        HStack(spacing: 12) {
            Gauge(value: min(max((percent ?? 0) / 100, 0), 1)) {}
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(statusColor)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(UsageFormatting.remainingPercentText(percent)) left")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(statusColor)
                }

                HStack {
                    Text("Used \(UsageFormatting.percentText(percent)) · Reset")
                    Spacer()
                    Text(reset)
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        statusColorForPercent(percent)
    }
}

struct UsageValueRow: View {
    var title: String
    var bucket: UsageBucket

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(UsageFormatting.yiTokens(bucket.totalTokens)) total")
                    .font(.subheadline.monospacedDigit())
                Text("\(UsageFormatting.yiTokens(bucket.nonCachedApproxTokens, digits: 3)) non-cached")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

func statusColorForPercent(_ percent: Double?) -> Color {
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

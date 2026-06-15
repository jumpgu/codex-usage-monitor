import Foundation
import CodexUsageCore
import WidgetKit

@main
struct CodexUsageCLI {
    static func main() {
        do {
            let summary = try UsageCollector().collectAndWrite()
            reloadWidgetsAndControls()

            if CommandLine.arguments.contains("--print") {
                printSummary(summary)
            }
        } catch {
            fputs("CodexUsageCLI: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func reloadWidgetsAndControls() {
        WidgetCenter.shared.reloadAllTimelines()
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadControls(ofKind: codexUsageControlKind)
        }
    }

    private static func printSummary(_ summary: UsageSummary) {
        let primary = summary.limits.primary?.usedPercent
        let secondary = summary.limits.secondary?.usedPercent
        print("Updated: \(summary.updatedAt)")
        print("5h left: \(UsageFormatting.remainingPercentText(primary)) used \(UsageFormatting.percentText(primary)) reset \(UsageFormatting.resetText(summary.limits.primary?.resetsAt))")
        print("7d left: \(UsageFormatting.remainingPercentText(secondary)) used \(UsageFormatting.percentText(secondary)) reset \(UsageFormatting.resetText(summary.limits.secondary?.resetsAt))")
        print("Today: \(UsageFormatting.yiTokens(summary.usage.today.totalTokens)) total / \(UsageFormatting.yiTokens(summary.usage.today.nonCachedApproxTokens, digits: 3)) non-cached")
        print("All time: \(UsageFormatting.yiTokens(summary.usage.allTime.totalTokens)) total")
        print("Summary: \(SharedPaths.summaryURL.path)")
    }
}

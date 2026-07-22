import ThreadBeaconCore
import SwiftUI

struct TokenDetailPopoverView: View {
    @Environment(\.locale) private var locale
    let snapshot: ThreadSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("任务详情")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                metricRow("模型", value: snapshot.model ?? "—")
                metricRow("推理强度", value: reasoningEffortText)
            }

            if let tokenUsage = snapshot.tokenUsage {
                Divider()

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    metricRow("会话总量", value: TokenCountFormatter.string(for: tokenUsage.totalTokens))
                    metricRow("输入", value: formatted(tokenUsage.cumulative?.inputTokens))
                    metricRow("缓存输入", value: formatted(tokenUsage.cumulative?.cachedInputTokens))
                    metricRow("非缓存输入", value: formatted(tokenUsage.cumulative?.uncachedInputTokens))
                    metricRow("输出", value: formatted(tokenUsage.cumulative?.outputTokens))
                    metricRow("Reasoning", value: formatted(tokenUsage.cumulative?.reasoningOutputTokens))
                    metricRow("当前 turn", value: currentTurnText(tokenUsage))
                    metricRow("缓存率", value: cacheRatioText(tokenUsage))
                    metricRow("更新时间", value: updatedAtText(tokenUsage))
                }

                Divider()

                Text("缓存输入已包含在输入中；Reasoning 已包含在输出中。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 290, alignment: .leading)
    }

    @ViewBuilder
    private func metricRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(AppLocalization.string(label, locale: locale))
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func formatted(_ value: Int64?) -> String {
        value.map(TokenCountFormatter.string) ?? "—"
    }

    private func currentTurnText(_ tokenUsage: TokenUsageSnapshot) -> String {
        guard let total = tokenUsage.currentTurn?.totalTokens else {
            return "—"
        }
        return "+" + TokenCountFormatter.string(for: total)
    }

    private func cacheRatioText(_ tokenUsage: TokenUsageSnapshot) -> String {
        tokenUsage.cumulative?.cacheRatio.map(TokenCountFormatter.percent) ?? "—"
    }

    private func updatedAtText(_ tokenUsage: TokenUsageSnapshot) -> String {
        tokenUsage.updatedAt?.formatted(
            Date.FormatStyle(date: .omitted, time: .standard).locale(locale)
        ) ?? "—"
    }

    private var reasoningEffortText: String {
        guard let reasoningEffort = snapshot.reasoningEffort else {
            return "—"
        }
        return switch reasoningEffort.lowercased() {
        case "xhigh": "XHigh"
        case "high": "High"
        case "medium": "Medium"
        case "low": "Low"
        case "minimal": "Minimal"
        case "none": "None"
        default: reasoningEffort
        }
    }
}

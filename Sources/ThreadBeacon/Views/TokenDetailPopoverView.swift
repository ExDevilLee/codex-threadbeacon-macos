import ThreadBeaconCore
import SwiftUI

struct TokenDetailPopoverView: View {
    let snapshot: TokenUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Token 详情")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                metricRow("会话总量", value: TokenCountFormatter.string(for: snapshot.totalTokens))
                metricRow("输入", value: formatted(snapshot.cumulative?.inputTokens))
                metricRow("缓存输入", value: formatted(snapshot.cumulative?.cachedInputTokens))
                metricRow("非缓存输入", value: formatted(snapshot.cumulative?.uncachedInputTokens))
                metricRow("输出", value: formatted(snapshot.cumulative?.outputTokens))
                metricRow("Reasoning", value: formatted(snapshot.cumulative?.reasoningOutputTokens))
                metricRow("当前 turn", value: currentTurnText)
                metricRow("缓存率", value: cacheRatioText)
                metricRow("更新时间", value: updatedAtText)
            }

            Divider()

            Text("缓存输入已包含在输入中；Reasoning 已包含在输出中。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 270, alignment: .leading)
    }

    @ViewBuilder
    private func metricRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func formatted(_ value: Int64?) -> String {
        value.map(TokenCountFormatter.string) ?? "—"
    }

    private var currentTurnText: String {
        guard let total = snapshot.currentTurn?.totalTokens else {
            return "—"
        }
        return "+" + TokenCountFormatter.string(for: total)
    }

    private var cacheRatioText: String {
        snapshot.cumulative?.cacheRatio.map(TokenCountFormatter.percent) ?? "—"
    }

    private var updatedAtText: String {
        snapshot.updatedAt?.formatted(date: .omitted, time: .standard) ?? "—"
    }
}

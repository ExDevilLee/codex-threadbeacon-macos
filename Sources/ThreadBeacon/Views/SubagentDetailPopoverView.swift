import ThreadBeaconCore
import SwiftUI

struct SubagentDetailPopoverView: View {
    let snapshot: SubagentSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subagent 详情")
                .font(.headline)

            Text(snapshot.title.isEmpty ? "未命名 Subagent" : snapshot.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                detailRow("状态", value: snapshot.status.displayName)
                detailRow("Agent", value: snapshot.agentNickname ?? "—")
                detailRow("角色", value: snapshot.agentRole ?? "—")
                detailRow("模型", value: snapshot.model ?? "—")
                detailRow("Reasoning", value: snapshot.reasoningEffort ?? "—")
                detailRow("累计 Token", value: totalTokenText)
                detailRow(
                    "输入",
                    value: formatted(snapshot.tokenUsage?.cumulative?.inputTokens)
                )
                detailRow(
                    "缓存输入",
                    value: formatted(snapshot.tokenUsage?.cumulative?.cachedInputTokens)
                )
                detailRow(
                    "输出",
                    value: formatted(snapshot.tokenUsage?.cumulative?.outputTokens)
                )
                detailRow(
                    "Reasoning Token",
                    value: formatted(snapshot.tokenUsage?.cumulative?.reasoningOutputTokens)
                )
                detailRow(
                    "当前 turn",
                    value: currentTurnText
                )
                detailRow("最近活动", value: activityText)
            }
        }
        .padding(12)
        .frame(width: 310, alignment: .leading)
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var totalTokenText: String {
        snapshot.tokenUsage.map { TokenCountFormatter.string(for: $0.totalTokens) } ?? "—"
    }

    private func formatted(_ value: Int64?) -> String {
        value.map(TokenCountFormatter.string) ?? "—"
    }

    private var currentTurnText: String {
        guard let value = snapshot.tokenUsage?.currentTurn?.totalTokens else {
            return "—"
        }
        return "+" + TokenCountFormatter.string(for: value)
    }

    private var activityText: String {
        let date = snapshot.latestEventAt ?? snapshot.updatedAt
        return date.formatted(date: .abbreviated, time: .standard)
    }
}

import ThreadBeaconCore
import SwiftUI

struct SubagentRowView: View {
    let snapshot: SubagentSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 10, height: 18)

            StatusDotView(status: snapshot.status)
                .scaleEffect(0.78)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    HStack(spacing: 4) {
                        if let alias = SubagentAliasFormatter.displayAlias(
                            nickname: snapshot.agentNickname,
                            title: snapshot.title
                        ) {
                            Text(alias)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .layoutPriority(0)
                                .help(alias)
                            Text("｜")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Text(snapshot.title.isEmpty ? "未命名 Subagent" : snapshot.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let tokenUsage = snapshot.tokenUsage {
                        Text(TokenCountFormatter.string(for: tokenUsage.totalTokens))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }

                    SubagentInfoButton(snapshot: snapshot)
                }

                HStack(spacing: 6) {
                    Text(snapshot.status.displayName)
                        .fontWeight(.medium)
                        .foregroundStyle(snapshot.status.color)
                    Text("·")
                    Text(RelativeActivityFormatter.string(since: activityDate))
                        .help(activityDate.formatted(date: .abbreviated, time: .standard))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
        .background(Color.secondary.opacity(0.035))
    }

    private var activityDate: Date {
        snapshot.latestEventAt ?? snapshot.updatedAt
    }
}

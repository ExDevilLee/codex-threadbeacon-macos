import ThreadBeaconCore
import SwiftUI

struct SubagentRowView: View {
    @Environment(\.locale) private var locale
    let snapshot: SubagentSnapshot
    let usesColorBlindSafeIndicators: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 10, height: 18)

            StatusDotView(
                status: snapshot.status,
                usesColorBlindSafeIndicators: usesColorBlindSafeIndicators
            )
                .scaleEffect(0.78)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    HStack(spacing: 4) {
                        if let alias = SubagentAliasFormatter.displayAlias(
                            agentPath: snapshot.agentPath,
                            nickname: snapshot.agentNickname,
                            title: snapshot.title
                        ) {
                            Text(alias)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 150, alignment: .leading)
                                .layoutPriority(2)
                                .help(alias)
                            Text("｜")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Text(snapshot.title.isEmpty
                            ? AppLocalization.string("未命名 Subagent", locale: locale)
                            : snapshot.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .layoutPriority(0)
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
                    Text(AppLocalization.string(snapshot.status.displayName, locale: locale))
                        .fontWeight(.medium)
                        .foregroundStyle(snapshot.status.color)
                    Text("·")
                    Text(AppLocalization.relativeActivity(since: activityDate, locale: locale))
                        .help(activityDate.formatted(
                            Date.FormatStyle(date: .abbreviated, time: .standard).locale(locale)
                        ))
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

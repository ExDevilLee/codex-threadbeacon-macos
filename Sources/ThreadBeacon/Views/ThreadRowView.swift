import ThreadBeaconCore
import SwiftUI

struct ThreadRowView: View {
    @Environment(\.locale) private var locale
    let snapshot: ThreadSnapshot
    let isPinned: Bool
    let isFavorite: Bool
    let isRestoringArchive: Bool
    let isSubagentExpanded: Bool
    let toggleSubagents: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDotView(status: snapshot.status)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("已置顶")
                            .accessibilityLabel("已置顶")
                    }

                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .help("已收藏")
                            .accessibilityLabel("已收藏")
                    }

                    if snapshot.isArchived {
                        Image(systemName: "archivebox.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("已归档")
                            .accessibilityLabel("已归档")
                    }

                    if isRestoringArchive {
                        ProgressView()
                            .controlSize(.mini)
                            .help("正在恢复")
                            .accessibilityLabel("正在恢复")
                    }

                    Text(snapshot.title.isEmpty
                        ? AppLocalization.string("未命名任务", locale: locale)
                        : snapshot.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let label = SubagentCountFormatter.label(for: snapshot.subagentCount) {
                        SubagentCountBadge(
                            label: label,
                            isExpanded: isSubagentExpanded,
                            toggle: toggleSubagents
                        )

                        if snapshot.tokenUsage != nil {
                            Divider()
                                .frame(height: 12)
                                .accessibilityHidden(true)
                        }
                    }

                    if let tokenUsage = snapshot.tokenUsage {
                        Text(TokenCountFormatter.string(for: tokenUsage.totalTokens))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        TokenInfoButton(snapshot: tokenUsage)
                    }
                }

                HStack(spacing: 6) {
                    Text(primaryStatusText)
                        .fontWeight(.medium)
                        .foregroundStyle(snapshot.status.color)
                    if let incident = snapshot.serviceIncident {
                        if let statusCode = incident.httpStatusCode {
                            Text("·")
                            Text("HTTP \(statusCode)")
                        }
                        if incident.phase == .retrying,
                           let attempt = incident.retryAttempt,
                           let limit = incident.retryLimit {
                            Text("·")
                            Text(AppLocalization.formatted(
                                "重试 %lld/%lld",
                                locale: locale,
                                attempt,
                                limit
                            ))
                        }
                    }
                    Text("·")
                    Text(RelativeTimeFormatter.statusDuration(since: snapshot.statusChangedAt, locale: locale))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var primaryStatusText: String {
        if isRestoringArchive {
            return AppLocalization.string("正在恢复", locale: locale)
        }
        if snapshot.isArchived {
            return AppLocalization.string("已归档", locale: locale)
        }
        return snapshot.serviceIncident?.phase == .failed
            ? AppLocalization.string("服务失败", locale: locale)
            : AppLocalization.string(snapshot.status.displayName, locale: locale)
    }
}

extension ThreadDisplayStatus {
    var displayName: String {
        switch self {
        case .error: "错误"
        case .needsAction: "需要操作"
        case .warning: "服务异常"
        case .running: "运行中"
        case .justCompleted: "刚完成"
        case .idle: "空闲"
        case .unknown: "未知"
        }
    }

    var color: Color {
        switch self {
        case .error: .red
        case .needsAction: .orange
        case .warning: .yellow
        case .running: .blue
        case .justCompleted: .green
        case .idle: .secondary
        case .unknown: .yellow
        }
    }
}

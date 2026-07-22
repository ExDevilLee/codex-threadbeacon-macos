import ThreadBeaconCore
import SwiftUI

struct SubagentCountBadge: View {
    @Environment(\.locale) private var locale
    let label: SubagentCountLabel
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 14, height: 14)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(.secondary.opacity(0.72), lineWidth: 1)
                    }
                    .accessibilityHidden(true)
                Text(label.countText)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize()
        .help(actionLabel)
        .accessibilityLabel(actionLabel)
    }

    private var actionLabel: String {
        return AppLocalization.formatted(
            isExpanded
                ? "运行中 %lld 个，共 %lld 个 Subagent；点击收起"
                : "运行中 %lld 个，共 %lld 个 Subagent；点击展开",
            locale: locale,
            label.activeCount,
            label.totalCount
        )
    }
}

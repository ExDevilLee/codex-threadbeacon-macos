import ThreadBeaconCore
import SwiftUI

struct SubagentCountBadge: View {
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
        .help(isExpanded ? "收起 \(label.accessibilityLabel)" : "展开 \(label.accessibilityLabel)")
        .accessibilityLabel(Text(isExpanded ? "收起 \(label.accessibilityLabel)" : "展开 \(label.accessibilityLabel)"))
    }
}

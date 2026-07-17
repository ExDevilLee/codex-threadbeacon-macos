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
                Image(systemName: "arrow.triangle.branch")
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

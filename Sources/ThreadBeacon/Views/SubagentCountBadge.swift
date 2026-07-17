import ThreadBeaconCore
import SwiftUI

struct SubagentCountBadge: View {
    let label: SubagentCountLabel

    var body: some View {
        Label {
            Text(label.countText)
                .monospacedDigit()
        } icon: {
            Image(systemName: "arrow.triangle.branch")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize()
        .help(label.accessibilityLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label.accessibilityLabel))
    }
}

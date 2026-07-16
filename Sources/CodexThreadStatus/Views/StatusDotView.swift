import CodexThreadStatusCore
import SwiftUI

struct StatusDotView: View {
    let status: ThreadDisplayStatus

    var body: some View {
        ZStack {
            if status == .running {
                Circle()
                    .stroke(status.color.opacity(0.35), lineWidth: 2)
                    .frame(width: 14, height: 14)
            }
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

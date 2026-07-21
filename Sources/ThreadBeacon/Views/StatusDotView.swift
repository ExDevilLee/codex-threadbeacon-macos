import ThreadBeaconCore
import SwiftUI

struct StatusDotView: View {
    @Environment(\.locale) private var locale
    let status: ThreadDisplayStatus
    let usesColorBlindSafeIndicators: Bool

    var body: some View {
        ZStack {
            if usesColorBlindSafeIndicators {
                Image(systemName: status.colorBlindSafeSymbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.color)
                    .frame(width: 14, height: 14)
            } else {
                if status == .running {
                    Circle()
                        .stroke(status.color.opacity(0.35), lineWidth: 2)
                        .frame(width: 14, height: 14)
                }
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 18, height: 18)
        .help(AppLocalization.string(status.displayName, locale: locale))
        .accessibilityHidden(true)
    }
}

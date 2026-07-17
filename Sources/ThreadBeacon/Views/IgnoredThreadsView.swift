import ThreadBeaconCore
import SwiftUI

struct IgnoredThreadsView: View {
    @ObservedObject var store: ThreadStatusStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已忽略任务")
                .font(.headline)

            ForEach(store.ignoredThreadIDs, id: \.self) { threadID in
                HStack(spacing: 8) {
                    Text(displayTitle(for: threadID))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        let shouldDismiss = store.ignoredThreadIDs.count == 1
                        store.restoreIgnored(threadID)
                        Task { await store.refresh(notificationPolicy: .baseline) }
                        if shouldDismiss {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("恢复任务")
                    .accessibilityLabel("恢复 \(displayTitle(for: threadID))")
                }
            }

            if store.ignoredThreadIDs.count > 1 {
                Divider()

                Button {
                    store.restoreAllIgnored()
                    Task { await store.refresh(notificationPolicy: .baseline) }
                    dismiss()
                } label: {
                    Label("全部恢复", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func displayTitle(for threadID: String) -> String {
        let title = store.ignoredTitle(for: threadID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return title
        }
        return "任务 \(threadID.prefix(8))"
    }
}

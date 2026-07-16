import CodexThreadStatusCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ThreadStatusStore
    @AppStorage("windowPinned") private var isWindowPinned = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            WindowLevelBridge(mode: WindowPinMode(isPinned: isWindowPinned))
                .frame(width: 0, height: 0)
        }
        .task {
            while !Task.isCancelled {
                await store.refresh()
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Codex 任务")
                .font(.headline)
            Text("\(store.snapshots.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button {
                isWindowPinned.toggle()
            } label: {
                Image(systemName: isWindowPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isWindowPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(isWindowPinned ? "取消钉住" : "钉在最前面")
            .accessibilityLabel(isWindowPinned ? "取消钉住" : "钉在最前面")

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("刷新任务状态")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    @ViewBuilder
    private var content: some View {
        if store.snapshots.isEmpty {
            ContentUnavailableView(
                "暂无 Codex 任务",
                systemImage: "list.bullet.rectangle"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        ThreadRowView(snapshot: snapshot)
                        if index < store.snapshots.count - 1 {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let errorMessage = store.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .lineLimit(1)
                    .help(errorMessage)
            } else if let refreshedAt = store.lastRefreshedAt {
                Image(systemName: store.isRefreshing ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                Text("更新于 \(refreshedAt.formatted(date: .omitted, time: .standard))")
            } else {
                ProgressView()
                    .controlSize(.mini)
                Text("正在读取任务")
            }

            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 32)
    }
}

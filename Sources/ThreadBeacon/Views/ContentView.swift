import ThreadBeaconCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ThreadStatusStore
    @AppStorage("windowPinned") private var isWindowPinned = false
    @State private var monitoringMode = MonitoringMode.active
    @State private var isShowingSoundSettings = false
    let previewSound: (CompletionSound) -> Void

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
        .task(id: monitoringMode) {
            guard monitoringMode.shouldAutoRefresh else { return }
            await store.refresh(notificationPolicy: .baseline)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                await store.refresh(notificationPolicy: .notify)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Codex 任务")
                .font(.headline)
            Text(taskCountLabel.displayText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help(taskCountLabel.explanation)
                .accessibilityLabel(taskCountLabel.explanation)

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
                isShowingSoundSettings.toggle()
            } label: {
                Image(systemName: "speaker.wave.2")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("提示音设置")
            .accessibilityLabel("提示音设置")
            .popover(isPresented: $isShowingSoundSettings) {
                SoundSettingsView(preview: previewSound)
            }

            Button {
                monitoringMode.toggle()
            } label: {
                Image(systemName: monitoringMode == .active ? "pause.fill" : "play.fill")
                    .foregroundStyle(monitoringMode == .paused ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(monitoringMode == .active ? "暂停监听" : "恢复监听")
            .accessibilityLabel(monitoringMode == .active ? "暂停监听" : "恢复监听")

            Button {
                Task { await store.refresh(notificationPolicy: .baseline) }
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

    private var taskCountLabel: ThreadCountLabel {
        ThreadCountFormatter.label(for: store.snapshots.map(\.status))
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
            } else if monitoringMode == .paused {
                Image(systemName: "pause.circle.fill")
                if let refreshedAt = store.lastRefreshedAt {
                    Text("监听已暂停 · 上次更新 \(refreshedAt.formatted(date: .omitted, time: .standard))")
                } else {
                    Text("监听已暂停 · 尚未更新")
                }
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

import ThreadBeaconCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ThreadStatusStore
    @AppStorage("windowPinned") private var isWindowPinned = false
    @AppStorage(DisplayPreferenceKeys.refreshIntervalSeconds)
    private var refreshIntervalSeconds = DisplaySettings.defaultRefreshIntervalSeconds
    @AppStorage(DisplayPreferenceKeys.maximumTaskCount)
    private var maximumTaskCount = DisplaySettings.defaultMaximumTaskCount
    @State private var monitoringMode = MonitoringMode.active
    @State private var isShowingIgnoredTasks = false
    @State private var pendingArchiveRestore: ThreadSnapshot?

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
            ZStack {
                WindowLevelBridge(mode: WindowPinMode(isPinned: isWindowPinned))
                WindowPlacementBridge()
            }
                .frame(width: 0, height: 0)
        }
        .task(id: monitoringSchedule) {
            guard monitoringSchedule.mode.shouldAutoRefresh else { return }
            await store.refresh(notificationPolicy: .baseline)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(monitoringSchedule.refreshIntervalSeconds))
                } catch {
                    return
                }
                await store.refresh(notificationPolicy: .notify)
            }
        }
        .onChange(of: maximumTaskCount) { _, newValue in
            let settings = DisplaySettings(
                refreshIntervalSeconds: refreshIntervalSeconds,
                maximumTaskCount: newValue
            )
            store.updateVisibleLimit(settings.maximumTaskCount)
            Task { await store.refresh(notificationPolicy: .baseline) }
        }
        .confirmationDialog(
            "恢复为激活状态？",
            isPresented: archiveRestoreConfirmationIsPresented,
            titleVisibility: .visible,
            presenting: pendingArchiveRestore
        ) { snapshot in
            Button("恢复") {
                pendingArchiveRestore = nil
                Task { await store.restoreArchivedFavorite(snapshot.id) }
            }
            Button("取消", role: .cancel) {
                pendingArchiveRestore = nil
            }
        } message: { snapshot in
            Text("将调用本机 Codex CLI 恢复“\(snapshot.title.isEmpty ? "未命名任务" : snapshot.title)”。恢复后继续保留收藏；旧会话可能不会重新出现在 Codex App 侧边栏。")
        }
        .alert(
            archiveRestoreFeedbackTitle,
            isPresented: archiveRestoreFeedbackIsPresented
        ) {
            Button("好") {
                store.dismissArchiveRestoreFeedback()
            }
        } message: {
            Text(archiveRestoreFeedbackMessage)
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
                store.toggleFavoritesOnly()
                Task { await store.refresh(notificationPolicy: .baseline) }
            } label: {
                Image(systemName: store.showsFavoritesOnly ? "star.fill" : "star")
                    .foregroundStyle(store.showsFavoritesOnly ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(store.showsFavoritesOnly ? "显示全部任务" : "仅显示收藏")
            .accessibilityLabel(store.showsFavoritesOnly ? "显示全部任务" : "仅显示收藏")

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

            if !store.ignoredThreadIDs.isEmpty {
                Button {
                    isShowingIgnoredTasks.toggle()
                } label: {
                    Image(systemName: "eye.slash")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("管理已忽略任务")
                .accessibilityLabel("管理已忽略任务，共 \(store.ignoredThreadIDs.count) 个")
                .popover(isPresented: $isShowingIgnoredTasks) {
                    IgnoredThreadsView(store: store)
                }
            }

            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("设置")
            .accessibilityLabel("打开设置")

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

    private var monitoringSchedule: MonitoringSchedule {
        let settings = DisplaySettings(
            refreshIntervalSeconds: refreshIntervalSeconds,
            maximumTaskCount: maximumTaskCount
        )
        return MonitoringSchedule(
            mode: monitoringMode,
            refreshIntervalSeconds: settings.refreshIntervalSeconds
        )
    }

    @ViewBuilder
    private var content: some View {
        if store.snapshots.isEmpty {
            ContentUnavailableView(
                store.showsFavoritesOnly ? "暂无收藏任务" : "暂无 Codex 任务",
                systemImage: store.showsFavoritesOnly ? "star" : "list.bullet.rectangle"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        let isExpanded = store.expandedThreadIDs.contains(snapshot.id)
                        let isRestoringArchive = store.isRestoringArchive(snapshot.id)
                        VStack(spacing: 0) {
                            ThreadRowView(
                                snapshot: snapshot,
                                isPinned: store.isPinned(snapshot.id),
                                isFavorite: store.isFavorite(snapshot.id),
                                isRestoringArchive: isRestoringArchive,
                                isSubagentExpanded: isExpanded,
                                toggleSubagents: {
                                    store.toggleExpansion(for: snapshot.id)
                                    Task { await store.refresh(notificationPolicy: .baseline) }
                                }
                            )
                            .contextMenu {
                                if ArchiveRestoreAvailability.current.isEnabled,
                                   snapshot.isArchived,
                                   store.isFavorite(snapshot.id) {
                                    Button {
                                        pendingArchiveRestore = snapshot
                                    } label: {
                                        Label(
                                            isRestoringArchive ? "正在恢复" : "恢复为激活状态",
                                            systemImage: "arrow.uturn.backward.circle"
                                        )
                                    }
                                    .disabled(isRestoringArchive)

                                    Divider()
                                }

                                Button {
                                    store.toggleFavorite(for: snapshot.id)
                                    Task { await store.refresh(notificationPolicy: .baseline) }
                                } label: {
                                    Label(
                                        store.isFavorite(snapshot.id) ? "取消收藏" : "收藏会话",
                                        systemImage: store.isFavorite(snapshot.id) ? "star.slash" : "star"
                                    )
                                }
                                .disabled(isRestoringArchive)

                                Button {
                                    store.togglePin(for: snapshot.id)
                                    Task { await store.refresh(notificationPolicy: .baseline) }
                                } label: {
                                    Label(
                                        store.isPinned(snapshot.id) ? "取消置顶" : "置顶任务",
                                        systemImage: store.isPinned(snapshot.id) ? "pin.slash" : "pin"
                                    )
                                }
                                .disabled(isRestoringArchive)

                                Divider()

                                Button(role: .destructive) {
                                    store.ignore(snapshot.id)
                                    Task { await store.refresh(notificationPolicy: .baseline) }
                                } label: {
                                    Label("忽略此任务", systemImage: "eye.slash")
                                }
                                .disabled(isRestoringArchive)
                            }

                            if isExpanded {
                                Divider().padding(.leading, 42)
                                if snapshot.subagents.isEmpty {
                                    SubagentLoadingRow(
                                        isRefreshing: store.isRefreshing,
                                        hasError: store.errorMessage != nil
                                    )
                                } else {
                                    ForEach(Array(snapshot.subagents.enumerated()), id: \.element.id) { childIndex, subagent in
                                        SubagentRowView(snapshot: subagent)
                                        if childIndex < snapshot.subagents.count - 1 {
                                            Divider().padding(.leading, 50)
                                        }
                                    }
                                }
                            }
                        }
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

            if let dataSourceHealth = store.dataSourceHealth {
                DataSourceHealthButton(report: dataSourceHealth)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    private var archiveRestoreConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingArchiveRestore != nil },
            set: { isPresented in
                if !isPresented {
                    pendingArchiveRestore = nil
                }
            }
        )
    }

    private var archiveRestoreFeedbackIsPresented: Binding<Bool> {
        Binding(
            get: { store.archiveRestoreFeedback != nil },
            set: { isPresented in
                if !isPresented {
                    store.dismissArchiveRestoreFeedback()
                }
            }
        )
    }

    private var archiveRestoreFeedbackTitle: String {
        switch store.archiveRestoreFeedback {
        case .success:
            "恢复请求已完成"
        case .failure:
            "恢复失败"
        case nil:
            ""
        }
    }

    private var archiveRestoreFeedbackMessage: String {
        switch store.archiveRestoreFeedback {
        case .success:
            "任务已恢复，收藏状态保持不变。当前 Codex App 可能不会把旧会话重新加入侧边栏。"
        case let .failure(_, message):
            message
        case nil:
            ""
        }
    }
}

private struct MonitoringSchedule: Equatable {
    let mode: MonitoringMode
    let refreshIntervalSeconds: Int
}

import AppKit
import ThreadBeaconCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ThreadBeaconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appLanguageStore: AppLanguageStore
    @StateObject private var store: ThreadStatusStore
    @StateObject private var launchAtLoginStore: LaunchAtLoginStore
    @StateObject private var updateCheckStore: UpdateCheckStore
    @StateObject private var autoRecoveryLogStore: AutoRecoveryLogStore
    @StateObject private var autoRecoverySettingsStore: AutoRecoverySettingsStore
    @StateObject private var accessibilityPermissionStore: AccessibilityPermissionStore
    @AppStorage(DisplayPreferenceKeys.appTheme)
    private var appThemeRawValue = AppTheme.defaultValue.rawValue
    private let soundPlayer: SoundPlaybackService

    init() {
        let languageStore = AppLanguageStore()
        _appLanguageStore = StateObject(wrappedValue: languageStore)
        let displaySettingsRepository = DisplaySettingsRepository()
        let displaySettings = displaySettingsRepository.load()
        displaySettingsRepository.save(displaySettings)
        let repository = SQLiteThreadRepository(databaseURL: CodexPaths.stateDatabaseURL)
        let loader = ThreadStatusLoader(repository: repository)
        let archiveRestoreService = CodexArchiveRestoreService()
        let recoveryLogs = AutoRecoveryLogStore()
        let recoverySettings = AutoRecoverySettingsStore(
            promptLanguage: AutoRecoveryPromptLanguage(
                localeIdentifier: languageStore.locale.identifier
            )
        )
        let accessibilityStore = AccessibilityPermissionStore()
        _autoRecoveryLogStore = StateObject(wrappedValue: recoveryLogs)
        _autoRecoverySettingsStore = StateObject(wrappedValue: recoverySettings)
        _accessibilityPermissionStore = StateObject(wrappedValue: accessibilityStore)
        let history = SoundNotificationHistory()
        let preferenceRepository = ThreadListPreferenceRepository()
        let player = SoundPlaybackService()
        soundPlayer = player
        _launchAtLoginStore = StateObject(wrappedValue: LaunchAtLoginStore(
            manager: SystemLaunchAtLoginManager()
        ))
        let releaseClient = GitHubReleaseClient()
        let appVersion = AboutAppInfo(infoDictionary: Bundle.main.infoDictionary).version
        _updateCheckStore = StateObject(wrappedValue: UpdateCheckStore(
            currentVersion: appVersion,
            checkOperation: releaseClient.check
        ))
        _store = StateObject(wrappedValue: ThreadStatusStore(
            loadResult: { request in
                try await loader.loadResult(
                    limit: request.recentLimit,
                    includedThreadIDs: request.includedThreadIDs,
                    favoriteThreadIDs: request.favoriteThreadIDs,
                    expandedThreadIDs: request.expandedThreadIDs
                )
            },
            restoreArchive: { threadID in
                try await archiveRestoreService.restore(threadID: threadID)
            },
            initialPreferences: preferenceRepository.load(),
            visibleLimit: displaySettings.maximumTaskCount,
            notificationTracker: SoundNotificationTracker(initialSeenEventIDs: history.load()),
            onNotification: { event in
                player.play(event)
            },
            onAutoRecovery: { candidate in
                accessibilityStore.refresh()
                let decision = AutoRecoveryPolicy.evaluate(
                    candidate: candidate,
                    settings: recoverySettings.settings,
                    isAccessibilityAuthorized: accessibilityStore.isAuthorized
                )
                switch decision {
                case .disabled:
                    break
                case let .needsAccessibilityAuthorization(prompt):
                    let logID = recoveryLogs.recordAttempt(
                        candidate: candidate,
                        prompt: prompt
                    )
                    recoveryLogs.recordSkipped(logID)
                case let .send(prompt):
                    let logID = recoveryLogs.recordAttempt(
                        candidate: candidate,
                        prompt: prompt
                    )
                    Task { @MainActor in
                        guard let result = await accessibilityStore.runAutomaticRecovery(
                            threadID: candidate.threadID,
                            prompt: prompt
                        ) else {
                            recoveryLogs.recordFailure(
                                logID,
                                detail: "已有恢复操作正在执行，或辅助功能权限已失效"
                            )
                            return
                        }
                        if result.isVerified {
                            recoveryLogs.recordSuccess(logID)
                        } else {
                            recoveryLogs.recordFailure(logID, detail: result.recoveryLogDetail)
                        }
                    }
                }
            },
            onNotificationHistoryChange: { eventIDs in
                history.save(eventIDs)
            },
            onPreferencesChange: { preferences in
                preferenceRepository.save(preferences)
            }
        ))
    }

    var body: some Scene {
        WindowGroup("ThreadBeacon") {
            ContentView(store: store, updateCheckStore: updateCheckStore)
                .frame(minWidth: 360, minHeight: 240)
                .environment(\.locale, appLanguageStore.locale)
                .environmentObject(appLanguageStore)
                .preferredColorScheme(selectedTheme.colorScheme)
                .onChange(of: appLanguageStore.locale.identifier) { _, identifier in
                    synchronizeRecoveryPromptLanguage(identifier)
                }
        }
        .defaultSize(width: 420, height: 360)
        .windowResizability(.contentMinSize)
        .commands {
            ThreadBeaconAboutCommands(locale: appLanguageStore.locale)
        }

        Window("ThreadBeacon", id: "about") {
            ThreadBeaconAboutView(updateCheckStore: updateCheckStore)
                .environment(\.locale, appLanguageStore.locale)
                .environmentObject(appLanguageStore)
                .preferredColorScheme(selectedTheme.colorScheme)
        }
        .windowResizability(.contentSize)

        Settings {
            ThreadBeaconSettingsView(
                languageStore: appLanguageStore,
                launchAtLoginStore: launchAtLoginStore,
                previewSound: soundPlayer.preview,
                autoRecoveryLogStore: autoRecoveryLogStore,
                autoRecoverySettingsStore: autoRecoverySettingsStore,
                accessibilityPermissionStore: accessibilityPermissionStore
            )
            .environment(\.locale, appLanguageStore.locale)
            .environmentObject(appLanguageStore)
            .preferredColorScheme(selectedTheme.colorScheme)
            .onChange(of: appLanguageStore.locale.identifier) { _, identifier in
                synchronizeRecoveryPromptLanguage(identifier)
            }
        }
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .defaultValue
    }

    private func synchronizeRecoveryPromptLanguage(_ localeIdentifier: String) {
        autoRecoverySettingsStore.setPromptLanguage(
            AutoRecoveryPromptLanguage(localeIdentifier: localeIdentifier)
        )
    }

}

private extension AutoRecoveryLogStore {
    func recordAttempt(candidate: AutoRecoveryCandidate, prompt: String) -> UUID {
        recordAttempt(
            threadID: candidate.threadID,
            episodeID: candidate.episodeID,
            incident: candidate.incidentLabel,
            prompt: prompt
        )
    }
}

private extension AccessibilityRecoverySendResult {
    var recoveryLogDetail: String {
        switch self {
        case .targetSelectionFailed:
            "无法安全定位并确认目标任务"
        case .rolloutUnavailable:
            "无法读取目标任务 rollout"
        case .composerNotEmpty:
            "目标输入框已有草稿"
        case .composerNotSettable:
            "目标输入框不可写"
        case .writeFailed:
            "无法写入恢复提示词"
        case .readbackFailed:
            "恢复提示词回读不一致"
        case .cleanupFailed:
            "无法确认目标输入框已清空"
        case let .sendButtonNotUnique(count):
            "发送按钮候选数量异常：\(count)"
        case .sendFailed:
            "发送按钮执行失败"
        case .sentUnconfirmed:
            "已触发发送，但 rollout 未在时限内确认"
        case .verified:
            "Codex App 已确认恢复消息并启动新任务"
        }
    }
}

private struct ThreadBeaconAboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let locale: Locale

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(AppLocalization.string("关于 ThreadBeacon", locale: locale)) {
                openWindow(id: "about")
            }
        }
    }
}

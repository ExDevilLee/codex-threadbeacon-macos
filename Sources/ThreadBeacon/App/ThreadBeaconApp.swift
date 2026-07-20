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
    @StateObject private var accessibilityPermissionStore: AccessibilityPermissionStore
    @AppStorage(DisplayPreferenceKeys.appTheme)
    private var appThemeRawValue = AppTheme.defaultValue.rawValue
    private let soundPlayer: SoundPlaybackService

    init() {
        _appLanguageStore = StateObject(wrappedValue: AppLanguageStore())
        let displaySettingsRepository = DisplaySettingsRepository()
        let displaySettings = displaySettingsRepository.load()
        displaySettingsRepository.save(displaySettings)
        let repository = SQLiteThreadRepository(databaseURL: CodexPaths.stateDatabaseURL)
        let loader = ThreadStatusLoader(repository: repository)
        let archiveRestoreService = CodexArchiveRestoreService()
        let recoveryLogs = AutoRecoveryLogStore()
        _autoRecoveryLogStore = StateObject(wrappedValue: recoveryLogs)
        _accessibilityPermissionStore = StateObject(wrappedValue: AccessibilityPermissionStore())
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
            onAutoRecovery: { threadID, episodeID, incident, prompt in
                let logID = recoveryLogs.recordAttempt(
                    threadID: threadID,
                    episodeID: episodeID,
                    incident: incident,
                    prompt: prompt
                )
                // External `codex exec resume` is intentionally disabled. Only the
                // future Accessibility path may inject a message into Codex App.
                recoveryLogs.recordSkipped(logID)
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
                accessibilityPermissionStore: accessibilityPermissionStore
            )
            .environment(\.locale, appLanguageStore.locale)
            .environmentObject(appLanguageStore)
            .preferredColorScheme(selectedTheme.colorScheme)
        }
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .defaultValue
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

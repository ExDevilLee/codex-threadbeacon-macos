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
    @StateObject private var store: ThreadStatusStore
    private let soundPlayer: SoundPlaybackService

    init() {
        let repository = SQLiteThreadRepository(databaseURL: CodexPaths.stateDatabaseURL)
        let loader = ThreadStatusLoader(repository: repository)
        let history = SoundNotificationHistory()
        let preferenceRepository = ThreadListPreferenceRepository()
        let player = SoundPlaybackService()
        soundPlayer = player
        _store = StateObject(wrappedValue: ThreadStatusStore(
            load: { request in
                try await loader.load(
                    limit: request.recentLimit,
                    includedThreadIDs: request.includedThreadIDs,
                    expandedThreadIDs: request.expandedThreadIDs
                )
            },
            initialPreferences: preferenceRepository.load(),
            notificationTracker: SoundNotificationTracker(initialSeenEventIDs: history.load()),
            onNotification: { event in
                player.play(event)
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
            ContentView(store: store, previewSound: soundPlayer.preview)
                .frame(minWidth: 360, minHeight: 240)
        }
        .defaultSize(width: 420, height: 360)
        .windowResizability(.contentMinSize)
    }
}

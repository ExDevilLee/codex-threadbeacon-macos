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

    init() {
        let repository = SQLiteThreadRepository(databaseURL: CodexPaths.stateDatabaseURL)
        let loader = ThreadStatusLoader(repository: repository)
        _store = StateObject(wrappedValue: ThreadStatusStore {
            try await loader.load(limit: 8)
        })
    }

    var body: some Scene {
        WindowGroup("ThreadBeacon") {
            ContentView(store: store)
                .frame(minWidth: 360, minHeight: 240)
        }
        .defaultSize(width: 420, height: 360)
        .windowResizability(.contentMinSize)
    }
}

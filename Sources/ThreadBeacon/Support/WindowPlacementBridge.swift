import AppKit
import ThreadBeaconCore
import SwiftUI

struct WindowPlacementBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowPlacementView {
        WindowPlacementView()
    }

    func updateNSView(_ nsView: WindowPlacementView, context: Context) {}
}

@MainActor
final class WindowPlacementView: NSView {
    private let repository: WindowPlacementRepository
    private weak var observedWindow: NSWindow?
    private var hasRestored = false

    init(repository: WindowPlacementRepository = WindowPlacementRepository()) {
        self.repository = repository
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else { return }

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            self.restoreIfNeeded(window)
            self.startObserving(window)
        }
    }

    private func restoreIfNeeded(_ window: NSWindow) {
        guard !hasRestored else { return }
        hasRestored = true
        guard let placement = repository.load() else { return }

        let displays = NSScreen.screens.map(\.threadBeaconGeometry)
        let fallbackIdentifier = NSScreen.main?.threadBeaconIdentifier
        guard let restored = WindowPlacementResolver.resolve(
            placement,
            displays: displays,
            fallbackDisplayIdentifier: fallbackIdentifier
        ) else { return }

        window.setFrame(restored.frame.nsRect, display: true)
        repository.save(restored)
    }

    private func startObserving(_ window: NSWindow) {
        observedWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowFrameDidChange(_:)),
            name: NSWindow.didMoveNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowFrameDidChange(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    private func stopObserving() {
        if let observedWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didMoveNotification,
                object: observedWindow
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResizeNotification,
                object: observedWindow
            )
        }
        observedWindow = nil
    }

    @objc
    private func windowFrameDidChange(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === observedWindow,
              let screen = window.screen else {
            return
        }
        repository.save(
            WindowPlacement(
                displayIdentifier: screen.threadBeaconIdentifier,
                frame: WindowGeometry(window.frame)
            )
        )
    }
}

private extension NSScreen {
    var threadBeaconIdentifier: String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return "display-\(Int(frame.minX))-\(Int(frame.minY))-\(Int(frame.width))x\(Int(frame.height))"
    }

    var threadBeaconGeometry: DisplayGeometry {
        DisplayGeometry(
            identifier: threadBeaconIdentifier,
            visibleFrame: WindowGeometry(visibleFrame)
        )
    }
}

private extension WindowGeometry {
    init(_ rect: NSRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    var nsRect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}

import AppKit
import CodexThreadStatusCore
import SwiftUI

struct WindowLevelBridge: NSViewRepresentable {
    let mode: WindowPinMode

    func makeNSView(context: Context) -> WindowLevelView {
        WindowLevelView(mode: mode)
    }

    func updateNSView(_ nsView: WindowLevelView, context: Context) {
        nsView.mode = mode
    }
}

final class WindowLevelView: NSView {
    var mode: WindowPinMode {
        didSet { applyWindowLevel() }
    }

    init(mode: WindowPinMode) {
        self.mode = mode
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowLevel()
    }

    private func applyWindowLevel() {
        window?.level = mode == .floating ? .floating : .normal
    }
}

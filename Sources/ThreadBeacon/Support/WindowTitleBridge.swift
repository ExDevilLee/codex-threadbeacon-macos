import AppKit
import SwiftUI

struct WindowTitleBridge: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> WindowTitleView {
        WindowTitleView(title: title)
    }

    func updateNSView(_ nsView: WindowTitleView, context: Context) {
        nsView.title = title
    }
}

@MainActor
final class WindowTitleView: NSView {
    var title: String {
        didSet { applyTitle() }
    }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTitle()
    }

    private func applyTitle() {
        window?.title = title
    }
}

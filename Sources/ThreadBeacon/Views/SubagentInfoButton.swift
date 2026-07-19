import ThreadBeaconCore
import SwiftUI

struct SubagentInfoButton: View {
    @Environment(\.locale) private var locale
    let snapshot: SubagentSnapshot

    @State private var isHoverPresented = false
    @State private var isPinned = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Button {
            isPinned.toggle()
            isHoverPresented = isPinned
            cancelScheduledTasks()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("查看 Subagent 详情")
        .accessibilityLabel("查看 Subagent 详情")
        .onHover(perform: handleTriggerHover)
        .popover(isPresented: presentationBinding, arrowEdge: .trailing) {
            SubagentDetailPopoverView(snapshot: snapshot)
                .environment(\.locale, locale)
                .onHover(perform: handlePopoverHover)
        }
        .onDisappear(perform: cancelScheduledTasks)
    }

    private var presentationBinding: Binding<Bool> {
        Binding(
            get: { isPinned || isHoverPresented },
            set: { isPresented in
                if !isPresented {
                    isPinned = false
                    isHoverPresented = false
                    cancelScheduledTasks()
                }
            }
        )
    }

    private func handleTriggerHover(_ isHovering: Bool) {
        hoverTask?.cancel()
        dismissTask?.cancel()
        if isHovering {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isHoverPresented = true
            }
        } else if !isPinned {
            scheduleDismissal()
        }
    }

    private func handlePopoverHover(_ isHovering: Bool) {
        dismissTask?.cancel()
        if isHovering {
            hoverTask?.cancel()
        } else if !isPinned {
            scheduleDismissal()
        }
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, !isPinned else { return }
            isHoverPresented = false
        }
    }

    private func cancelScheduledTasks() {
        hoverTask?.cancel()
        dismissTask?.cancel()
        hoverTask = nil
        dismissTask = nil
    }
}

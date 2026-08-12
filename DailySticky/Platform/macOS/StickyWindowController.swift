import AppKit
import Combine
import SwiftUI

private final class StickyWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

@MainActor
final class StickyWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let onToggleNoteSearch: () -> Void
    private let onNoteSearchAnchorChange: (NSRect) -> Void
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(
        appState: AppState,
        onToggleNoteSearch: @escaping () -> Void,
        onNoteSearchAnchorChange: @escaping (NSRect) -> Void
    ) {
        self.appState = appState
        self.onToggleNoteSearch = onToggleNoteSearch
        self.onNoteSearchAnchorChange = onNoteSearchAnchorChange
        super.init()
        observePinState()
        observeOpacity()
    }

    var currentWindowFrame: NSRect? {
        window?.frame
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = makeWindow()
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let frame = WindowFrameStore.usableFrame(from: appState.data.settings.windowFrame)
        let rootView = StickyRootView(
            onToggleNoteSearch: onToggleNoteSearch,
            onNoteSearchAnchorChange: onNoteSearchAnchorChange
        )
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)

        let window = StickyWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Pinaday"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = WindowFrameStore.minimumSize
        window.contentMinSize = WindowFrameStore.minimumSize
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.contentView = hostingView
        window.setFrame(frame, display: false)
        window.delegate = self

        // The sticky note owns its own controls, so AppKit chrome stays out of the way.
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        PinWindowService.apply(isPinned: appState.isPinned, to: window)
        window.alphaValue = appState.noteOpacity
        return window
    }

    private func observePinState() {
        appState.$isPinned
            .sink { [weak self] isPinned in
                Task { @MainActor in
                    self?.applyPinState(isPinned)
                }
            }
            .store(in: &cancellables)
    }

    private func observeOpacity() {
        appState.$noteOpacity
            .sink { [weak self] noteOpacity in
                Task { @MainActor in
                    self?.window?.alphaValue = noteOpacity
                }
            }
            .store(in: &cancellables)
    }

    private func applyPinState(_ isPinned: Bool) {
        guard let window else {
            return
        }

        PinWindowService.apply(isPinned: isPinned, to: window)
    }

    func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    func windowDidResize(_ notification: Notification) {
        persistFrame()
    }

    func windowWillClose(_ notification: Notification) {
        appState.saveImmediately()
    }

    private func persistFrame() {
        guard let window else {
            return
        }

        appState.updateWindowFrame(WindowFrameStore.storedFrame(from: window.frame))
    }
}

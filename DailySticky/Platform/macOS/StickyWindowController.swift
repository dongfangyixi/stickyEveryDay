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
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        super.init()
        observePinState()
        observeOpacity()
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
        let rootView = StickyRootView()
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: rootView)

        let window = StickyWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "DailySticky"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 280)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.contentView = hostingView
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

import AppKit
import Combine
import SwiftUI

private final class StickyWindow: NSWindow {
    private struct HoverResizeEdges: OptionSet {
        let rawValue: Int

        static let top = HoverResizeEdges(rawValue: 1 << 0)
        static let left = HoverResizeEdges(rawValue: 1 << 1)
        static let bottom = HoverResizeEdges(rawValue: 1 << 2)
        static let right = HoverResizeEdges(rawValue: 1 << 3)
    }

    private let resizeHitThickness: CGFloat = 10
    private var isShowingResizeCursor = false

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved, .cursorUpdate:
            let edges = hoverResizeEdges(at: event.locationInWindow)
            if !edges.isEmpty {
                resizeCursor(for: edges).set()
                isShowingResizeCursor = true
                return
            }
            resetResizeCursorIfNeeded()
        default:
            break
        }

        super.sendEvent(event)
    }

    private func resetResizeCursorIfNeeded() {
        guard isShowingResizeCursor else {
            return
        }

        NSCursor.arrow.set()
        isShowingResizeCursor = false
    }

    private func hoverResizeEdges(at point: NSPoint) -> HoverResizeEdges {
        var edges: HoverResizeEdges = []
        let size = frame.size

        guard point.x >= 0,
              point.y >= 0,
              point.x <= size.width,
              point.y <= size.height
        else {
            return []
        }

        if point.y >= size.height - resizeHitThickness {
            edges.insert(.top)
        }
        if point.x <= resizeHitThickness {
            edges.insert(.left)
        }
        if point.y <= resizeHitThickness {
            edges.insert(.bottom)
        }
        if point.x >= size.width - resizeHitThickness {
            edges.insert(.right)
        }

        return edges
    }

    private func resizeCursor(for edges: HoverResizeEdges) -> NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(position: frameResizePosition(for: edges), directions: .all)
        }

        if edges.contains(.top) || edges.contains(.bottom) {
            return .resizeUpDown
        }

        return .resizeLeftRight
    }

    @available(macOS 15.0, *)
    private func frameResizePosition(for edges: HoverResizeEdges) -> NSCursor.FrameResizePosition {
        if edges.contains(.top) && edges.contains(.left) {
            return .topLeft
        }
        if edges.contains(.top) && edges.contains(.right) {
            return .topRight
        }
        if edges.contains(.bottom) && edges.contains(.left) {
            return .bottomLeft
        }
        if edges.contains(.bottom) && edges.contains(.right) {
            return .bottomRight
        }
        if edges.contains(.top) {
            return .top
        }
        if edges.contains(.left) {
            return .left
        }
        if edges.contains(.bottom) {
            return .bottom
        }
        return .right
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
        let rootView = StickyRootView()
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)

        let window = StickyWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Pinaday"
        window.isMovableByWindowBackground = true
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

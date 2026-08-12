import AppKit
import SwiftUI

struct DateHeaderView: View {
    @EnvironmentObject private var appState: AppState
    let onToggleNoteSearch: () -> Void
    let onNoteSearchAnchorChange: (NSRect) -> Void

    var body: some View {
        let palette = appState.themePalette

        GeometryReader { proxy in
            let isCompact = proxy.size.width < 400

            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Button {
                        appState.goToPreviousDay()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(StickyIconButtonStyle(palette: palette))
                    .help("Previous day")

                    Group {
                        if isCompact {
                            Text(appState.currentShortDateTitle)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                Text(appState.currentDateTitle)
                                    .fixedSize(horizontal: true, vertical: false)
                                Text(appState.currentCompactDateTitle)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                    .background { WindowDragArea() }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: StickyHeaderControlMetrics.height)

                    Button {
                        appState.goToNextDay()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(StickyIconButtonStyle(palette: palette))
                    .help("Next day")
                }
                .layoutPriority(2)

                WindowDragArea()
                    .frame(minWidth: 4, maxWidth: .infinity)
                    .frame(height: StickyHeaderControlMetrics.height)
                    .layoutPriority(-1)

                HStack(spacing: isCompact ? 5 : 8) {
                    returnChip(isCompact: isCompact, palette: palette)

                    Button {
                        onToggleNoteSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(
                        StickyIconButtonStyle(
                            isActive: appState.isNoteSearchPresented,
                            palette: palette
                        )
                    )
                    .accessibilityLabel("Search notes")
                    .help("Search notes")
                    .background {
                        SearchPanelAnchorReader { screenRect in
                            onNoteSearchAnchorChange(screenRect)
                        }
                        .allowsHitTesting(false)
                    }

                    WindowControlsView()
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
            .padding(.horizontal, isCompact ? 8 : 12)
            .padding(.vertical, 8)
        }
        .frame(height: StickyHeaderControlMetrics.height + 16)
    }

    @ViewBuilder
    private func returnChip(isCompact: Bool, palette: AppTheme.Palette) -> some View {
        switch appState.headerReturnState {
        case .none:
            EmptyView()
        case .today:
            Button {
                appState.jumpToToday()
            } label: {
                Text(String(localized: "Today"))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(StickyHeaderChipButtonStyle(isCompact: isCompact, palette: palette))
            .accessibilityLabel("Back to today")
            .help("Back to today")
        case let .searchOrigin(dateKey):
            let shortTitle = appState.shortDisplayTitle(for: dateKey)
            let accessibleTitle = appState.accessibleShortDisplayTitle(for: dateKey)

            Button {
                appState.returnToSearchOrigin()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .regular))
                    Text(shortTitle)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(StickyHeaderChipButtonStyle(isCompact: isCompact, palette: palette))
            .accessibilityLabel("Return to \(accessibleTitle)")
            .help("Return to \(shortTitle) — the day you searched from")
        }
    }
}

private struct SearchPanelAnchorReader: NSViewRepresentable {
    let onFrameChange: (NSRect) -> Void

    func makeNSView(context: Context) -> SearchPanelAnchorView {
        SearchPanelAnchorView(onFrameChange: onFrameChange)
    }

    func updateNSView(_ nsView: SearchPanelAnchorView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.publishFrame()
    }
}

private final class SearchPanelAnchorView: NSView {
    var onFrameChange: (NSRect) -> Void
    private var windowObservers: [NSObjectProtocol] = []

    init(onFrameChange: @escaping (NSRect) -> Void) {
        self.onFrameChange = onFrameChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowFrameChanges()
        publishFrame()
    }

    override func layout() {
        super.layout()
        publishFrame()
    }

    func publishFrame() {
        guard let window else {
            return
        }

        let screenRect = window.convertToScreen(convert(bounds, to: nil))
        guard !screenRect.isEmpty else {
            return
        }
        onFrameChange(screenRect)
    }

    private func observeWindowFrameChanges() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        guard let window else {
            return
        }

        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            windowObservers.append(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.publishFrame()
                }
            )
        }
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

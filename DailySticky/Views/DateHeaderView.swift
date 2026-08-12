import AppKit
import SwiftUI

struct DateHeaderView: View {
    @EnvironmentObject private var appState: AppState
    let onToggleNoteSearch: () -> Void
    let onNoteSearchAnchorChange: (NSRect) -> Void

    var body: some View {
        let palette = appState.themePalette

        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    appState.goToPreviousDay()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(StickyIconButtonStyle(palette: palette))
                .help("Previous day")

                ViewThatFits(in: .horizontal) {
                    Text(appState.currentDateTitle)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(appState.currentCompactDateTitle)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .background { WindowDragArea() }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .frame(height: 28)

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
                .frame(height: 28)
                .layoutPriority(-1)

            HStack(spacing: 8) {
                if appState.hasSearchReturnDestination,
                   let buttonTitle = appState.searchReturnButtonTitle,
                   let dayNumber = appState.searchReturnDayNumber {
                    Button {
                        appState.returnToSearchOrigin()
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 4) {
                                Text(buttonTitle)
                                    .lineLimit(1)
                                CalendarDateIcon(dayNumber: dayNumber)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "return")
                                CalendarDateIcon(dayNumber: dayNumber)
                            }
                        }
                    }
                    .buttonStyle(StickyTextButtonStyle(palette: palette))
                    .accessibilityLabel(buttonTitle)
                    .help(buttonTitle)
                } else if !appState.isShowingToday {
                    Button {
                        appState.jumpToToday()
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 4) {
                                Text("Back to Today")
                                    .lineLimit(1)
                                CalendarDateIcon(dayNumber: todayDayNumber)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "return")
                                CalendarDateIcon(dayNumber: todayDayNumber)
                            }
                        }
                    }
                    .buttonStyle(StickyTextButtonStyle(palette: palette))
                    .accessibilityLabel("Back to Today")
                    .help("Back to today")
                }

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
            .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var todayDayNumber: String {
        String(Calendar.autoupdatingCurrent.component(.day, from: Date()))
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

private struct CalendarDateIcon: View {
    let dayNumber: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                .stroke(lineWidth: 1.55)
                .frame(width: 13.4, height: 11.4)
                .offset(y: 1.35)

            Path { path in
                path.move(to: CGPoint(x: 4.3, y: 1.2))
                path.addLine(to: CGPoint(x: 4.3, y: 4.15))
                path.move(to: CGPoint(x: 10.7, y: 1.2))
                path.addLine(to: CGPoint(x: 10.7, y: 4.15))
                path.move(to: CGPoint(x: 1.3, y: 5.35))
                path.addLine(to: CGPoint(x: 13.7, y: 5.35))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round))

            Text(dayNumber)
                .font(.system(size: 6.7, weight: .black, design: .rounded))
                .monospacedDigit()
                .offset(y: 3.1)
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }
}

import AppKit
import SwiftUI

enum DateHeaderActionControlMode: Equatable {
    case individual
    case moreMenu
}

enum DateHeaderLayout {
    static let height: CGFloat = 56
    static let verticalPadding: CGFloat = 8
    static let horizontalPadding: CGFloat = 8
    static let controlSize: CGFloat = 34
    static let controlSpacing: CGFloat = 6
    static let wideReturnWidth: CGFloat = 84
    static let compactReturnWidth: CGFloat = 34
    static let moreMenuHeaderWidth: CGFloat = 360

    static func actionControlMode(
        forHeaderWidth headerWidth: CGFloat
    ) -> DateHeaderActionControlMode {
        headerWidth <= moreMenuHeaderWidth ? .moreMenu : .individual
    }

    static func controlClusterWidth(
        isCompact: Bool,
        hasSearchReturn: Bool,
        actionControlMode: DateHeaderActionControlMode
    ) -> CGFloat {
        let returnWidth = hasSearchReturn
            ? (isCompact ? compactReturnWidth : wideReturnWidth)
            : 0
        let actionWidth = actionControlMode == .moreMenu
            ? controlSize
            : 2 * controlSize + controlSpacing
        return returnWidth
            + actionWidth
            + (hasSearchReturn ? controlSpacing : 0)
    }

    static func tickerWidth(headerWidth: CGFloat, controlClusterWidth: CGFloat) -> CGFloat {
        let available = headerWidth - 2 * horizontalPadding - controlClusterWidth
        return min(
            DateTickerLayout.maximumWidth,
            max(DateTickerLayout.minimumWidth, available - controlSpacing)
        )
    }

    static func windowDragGapWidth(headerWidth: CGFloat, controlClusterWidth: CGFloat) -> CGFloat {
        max(
            0,
            headerWidth
                - 2 * horizontalPadding
                - controlClusterWidth
                - tickerWidth(
                    headerWidth: headerWidth,
                    controlClusterWidth: controlClusterWidth
                )
        )
    }
}

struct DateHeaderView: View {
    @EnvironmentObject private var appState: AppState
    let onToggleNoteSearch: () -> Void
    let onNoteSearchAnchorChange: (NSRect) -> Void

    var body: some View {
        let headerTheme = DateTickerTheme.palette(for: appState.themePalette.kind)

        GeometryReader { proxy in
            let isCompact = proxy.size.width <= DateTickerLayout.compactHeaderWidth
            let hasSearchReturn = appState.headerReturnState.isSearchOrigin
            let actionControlMode = DateHeaderLayout.actionControlMode(
                forHeaderWidth: proxy.size.width
            )
            let controlClusterWidth = DateHeaderLayout.controlClusterWidth(
                isCompact: isCompact,
                hasSearchReturn: hasSearchReturn,
                actionControlMode: actionControlMode
            )
            let tickerWidth = DateHeaderLayout.tickerWidth(
                headerWidth: proxy.size.width,
                controlClusterWidth: controlClusterWidth
            )
            let dragGapWidth = DateHeaderLayout.windowDragGapWidth(
                headerWidth: proxy.size.width,
                controlClusterWidth: controlClusterWidth
            )

            VStack(spacing: 0) {
                WindowDragArea()
                    .frame(maxWidth: .infinity)
                    .frame(height: DateHeaderLayout.verticalPadding)

                HStack(spacing: 0) {
                    DateTickerView(headerWidth: proxy.size.width)
                        .frame(width: tickerWidth, height: DateTickerLayout.bandHeight)

                    WindowDragArea()
                        .frame(width: dragGapWidth, height: DateTickerLayout.bandHeight)

                    HStack(spacing: DateHeaderLayout.controlSpacing) {
                        returnChip(isCompact: isCompact, theme: headerTheme)

                        actionControls(
                            mode: actionControlMode,
                            theme: headerTheme
                        )
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, DateHeaderLayout.horizontalPadding)

                WindowDragArea()
                    .frame(maxWidth: .infinity)
                    .frame(height: DateHeaderLayout.verticalPadding)
            }
            .background(headerTheme.bar)
        }
        .frame(height: DateHeaderLayout.height)
    }

    @ViewBuilder
    private func actionControls(
        mode: DateHeaderActionControlMode,
        theme: DateTickerTheme
    ) -> some View {
        switch mode {
        case .individual:
            goToButton(theme: theme)

            WindowControlsView(
                controlSize: DateHeaderLayout.controlSize,
                cornerRadius: 9
            )
        case .moreMenu:
            Menu {
                Button {
                    onToggleNoteSearch()
                } label: {
                    Label(
                        appState.localized("Go to note"),
                        systemImage: "magnifyingglass"
                    )
                }

                Divider()

                Button {
                    appState.togglePinned()
                } label: {
                    Label(
                        appState.localized(
                            appState.isPinned ? "Unpin window" : "Pin window"
                        ),
                        systemImage: appState.isPinned ? "pin.slash" : "pin"
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.icon)
                    .frame(
                        width: DateHeaderLayout.controlSize,
                        height: DateHeaderLayout.controlSize
                    )
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(theme.pill)
                    }
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(appState.localized("More"))
            .help(appState.localized("More"))
            .background {
                SearchPanelAnchorReader { screenRect in
                    onNoteSearchAnchorChange(screenRect)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func goToButton(theme: DateTickerTheme) -> some View {
        Button {
            onToggleNoteSearch()
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .buttonStyle(
            TickerHeaderControlButtonStyle(
                background: theme.pill,
                foreground: theme.icon,
                size: DateHeaderLayout.controlSize,
                cornerRadius: 9
            )
        )
        .accessibilityLabel(appState.localized("Go to note"))
        .help(appState.localized("Go to note"))
        .background {
            SearchPanelAnchorReader { screenRect in
                onNoteSearchAnchorChange(screenRect)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func returnChip(isCompact: Bool, theme: DateTickerTheme) -> some View {
        switch appState.headerReturnState {
        case .none, .today:
            EmptyView()
        case let .searchOrigin(dateKey):
            let shortTitle = appState.shortDisplayTitle(for: dateKey)
            let accessibleTitle = appState.accessibleShortDisplayTitle(for: dateKey)

            Button {
                appState.returnToSearchOrigin()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .regular))
                    if !isCompact {
                        Text(shortTitle)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(
                TickerHeaderChipButtonStyle(
                    theme: theme,
                    width: isCompact ? 34 : 84
                )
            )
            .accessibilityLabel(appState.language.returnAccessibilityLabel(date: accessibleTitle))
            .help(appState.language.returnTooltip(date: shortTitle))
        }
    }
}

private extension HeaderReturnState {
    var isSearchOrigin: Bool {
        if case .searchOrigin = self {
            return true
        }
        return false
    }
}

struct TickerHeaderControlButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color
    let size: CGFloat
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(background)
                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(foreground.opacity(0.10))
                    }
                }
            }
            .contentShape(Rectangle())
    }
}

private struct TickerHeaderChipButtonStyle: ButtonStyle {
    let theme: DateTickerTheme
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.text)
            .frame(width: width, height: 34)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(theme.pill)
                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(theme.text.opacity(0.08))
                    }
                }
            }
            .contentShape(Rectangle())
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

final class WindowDragNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

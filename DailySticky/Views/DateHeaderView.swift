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
                    .help(appState.localized("Previous day"))

                    Group {
                        if isCompact {
                            stableDateTitle(
                                appState.currentShortDateTitle,
                                tier: .navigation
                            )
                        } else {
                            ViewThatFits(in: .horizontal) {
                                stableDateTitle(
                                    appState.currentDateTitle,
                                    tier: .full
                                )
                                stableDateTitle(
                                    appState.currentCompactDateTitle,
                                    tier: .compact
                                )
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
                    .help(appState.localized("Next day"))
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
                    .accessibilityLabel(appState.localized("Go to note"))
                    .help(appState.localized("Go to note"))
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

    private func stableDateTitle(
        _ title: String,
        tier: DateHeaderTitleTier
    ) -> some View {
        Text(title)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(
                width: DateHeaderTitleMetrics.reservedWidth(
                    for: tier,
                    locale: appState.language.locale
                )
            )
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
                Text(appState.localized("Today"))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(StickyHeaderChipButtonStyle(isCompact: isCompact, palette: palette))
            .accessibilityLabel(appState.localized("Back to today"))
            .help(appState.localized("Back to today"))
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
            .accessibilityLabel(appState.language.returnAccessibilityLabel(date: accessibleTitle))
            .help(appState.language.returnTooltip(date: shortTitle))
        }
    }
}

enum DateHeaderTitleTier: String, CaseIterable {
    case full
    case compact
    case navigation

    var dateFormatTemplate: String {
        switch self {
        case .full:
            return "yMMMMEEEEd"
        case .compact:
            return "yMMMd"
        case .navigation:
            return "MMMdEEE"
        }
    }
}

enum DateHeaderTitleMetrics {
    private static let fontSize: CGFloat = 14
    private static let safetyPadding: CGFloat = 6
    private static let cache = NSCache<NSString, NSNumber>()

    static func reservedWidth(for tier: DateHeaderTitleTier, locale: Locale) -> CGFloat {
        let locale = normalizedLocale(locale)
        let cacheKey = "\(locale.identifier)|\(tier.rawValue)" as NSString
        if let cachedWidth = cache.object(forKey: cacheKey) {
            return CGFloat(cachedWidth.doubleValue)
        }

        let formatter = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(tier.dateFormatTemplate)

        let startDate = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let dayCount = calendar.range(of: .day, in: .year, for: startDate)?.count ?? 366
        var widestTitle: CGFloat = 0

        for dayOffset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else {
                continue
            }
            widestTitle = max(widestTitle, measuredWidth(of: formatter.string(from: date)))
        }

        let reservedWidth = ceil(widestTitle + safetyPadding)
        cache.setObject(NSNumber(value: Double(reservedWidth)), forKey: cacheKey)
        return reservedWidth
    }

    static func measuredWidth(of title: String) -> CGFloat {
        let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let font: NSFont
        if let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded),
           let roundedFont = NSFont(descriptor: roundedDescriptor, size: fontSize) {
            font = roundedFont
        } else {
            font = baseFont
        }

        return ceil((title as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func normalizedLocale(_ locale: Locale) -> Locale {
        guard locale.language.languageCode?.identifier == "en" else {
            return locale
        }
        return Locale(identifier: "en_US")
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

import AppKit
import SwiftUI

@MainActor
final class NoteSearchPanelController: NSObject, NSWindowDelegate {
    private static let panelSize = NSSize(width: 360, height: 351)

    private let appState: AppState
    private let searchController = NoteSearchController()
    private var panel: NoteSearchPanel?
    private var anchorScreenRect: NSRect?
    private var outsideClickMonitor: Any?
    private var appResignObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        installDismissalObservers()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var currentPanelFrame: NSRect? {
        panel?.frame
    }

    deinit {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
        }
    }

    func show(relativeTo anchorScreenRect: NSRect?, noteWindowFrame: NSRect?) {
        if let anchorScreenRect {
            self.anchorScreenRect = anchorScreenRect
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        searchController.reset()
        searchController.rebuildIndex(with: appState.data.pages)
        appState.presentNoteSearch()
        position(panel, noteWindowFrame: noteWindowFrame)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        searchController.releaseIndex()
        appState.dismissNoteSearch()
    }

    func windowWillClose(_ notification: Notification) {
        searchController.releaseIndex()
        appState.dismissNoteSearch()
    }

    private func makePanel() -> NoteSearchPanel {
        let panel = NoteSearchPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.title = "Search Notes"
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self

        let hostingView = NSHostingView(
            rootView: NoteSearchPanelView(
                controller: searchController,
                onSelect: { [weak self] result in
                    guard let self else {
                        return
                    }
                    self.appState.openSearchResult(result.dateKey)
                    self.dismiss()
                },
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )
            .environmentObject(appState)
        )
        hostingView.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = hostingView
        return panel
    }

    private func position(_ panel: NSPanel, noteWindowFrame: NSRect?) {
        let referenceFrame = anchorScreenRect ?? noteWindowFrame ?? NSScreen.main?.visibleFrame
        guard let referenceFrame,
              let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(referenceFrame) })
                ?? NSScreen.main
        else {
            panel.center()
            return
        }

        let anchor = anchorScreenRect ?? NSRect(
            x: referenceFrame.midX,
            y: referenceFrame.maxY - 36,
            width: 1,
            height: 1
        )
        panel.setFrame(
            NoteSearchPanelPlacement.frame(
                panelSize: Self.panelSize,
                anchorRect: anchor,
                visibleFrame: screen.visibleFrame
            ),
            display: false
        )
    }

    private func installDismissalObservers() {
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self,
                  self.appState.isNoteSearchPresented,
                  event.window !== self.panel
            else {
                return event
            }

            if let anchorScreenRect = self.anchorScreenRect,
               anchorScreenRect.contains(NSEvent.mouseLocation) {
                return event
            }

            self.dismiss()
            return event
        }

        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }
}

private final class NoteSearchPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

enum NoteSearchPanelPlacement {
    static func frame(
        panelSize: NSSize,
        anchorRect: NSRect,
        visibleFrame: NSRect,
        gap: CGFloat = 6,
        edgePadding: CGFloat = 8
    ) -> NSRect {
        let minimumX = visibleFrame.minX + edgePadding
        let maximumX = visibleFrame.maxX - panelSize.width - edgePadding
        let x = min(
            max(anchorRect.midX - panelSize.width / 2, minimumX),
            max(minimumX, maximumX)
        )

        let belowY = anchorRect.minY - gap - panelSize.height
        let aboveY = anchorRect.maxY + gap
        let minimumY = visibleFrame.minY + edgePadding
        let maximumY = visibleFrame.maxY - panelSize.height - edgePadding
        let preferredY = belowY >= minimumY ? belowY : aboveY
        let y = min(max(preferredY, minimumY), max(minimumY, maximumY))

        return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
    }
}

struct NoteSearchPanelView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var controller: NoteSearchController
    let onSelect: (NoteSearchResult) -> Void
    let onDismiss: () -> Void

    @State private var searchFieldIsFocused = false
    @State private var resultFrames: [String: CGRect] = [:]
    @State private var resultsViewportFrame: CGRect = .zero
    @State private var keyboardScrollRequest: NoteSearchKeyboardScrollRequest?
    @State private var keyboardNavigationPointerLocation: CGPoint?

    private let resultsViewportHeight: CGFloat = 300

    var body: some View {
        let palette = appState.themePalette

        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)

                NoteSearchField(
                    text: $controller.query,
                    isFocused: searchFieldIsFocused,
                    palette: palette,
                    onMoveSelection: moveKeyboardSelection,
                    onSubmit: openSelectedResult,
                    onCancel: handleEscape
                )

                if !controller.query.isEmpty {
                    Button {
                        controller.clearQuery()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
            .frame(height: 30)
            .padding(10)

            Divider()
                .overlay(palette.separator)

            resultsContent(palette: palette)
                .frame(height: resultsViewportHeight)
        }
        .frame(width: 360)
        .background(palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.separator, lineWidth: 1)
        }
        .foregroundStyle(palette.text)
        .onAppear {
            DispatchQueue.main.async {
                searchFieldIsFocused = true
            }
        }
    }

    @ViewBuilder
    private func resultsContent(palette: AppTheme.Palette) -> some View {
        if controller.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchStatus(
                icon: "magnifyingglass",
                title: "Search notes",
                palette: palette
            )
        } else if controller.results.isEmpty {
            searchStatus(
                icon: "text.magnifyingglass",
                title: "No matching notes",
                palette: palette
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(controller.results.enumerated()), id: \.element.id) { index, result in
                            Button {
                                onSelect(result)
                            } label: {
                                resultRow(
                                    result,
                                    isSelected: index == controller.selectedResultIndex,
                                    palette: palette
                                )
                            }
                            .buttonStyle(.plain)
                            .id(result.id)
                            .onContinuousHover { phase in
                                if case .active = phase {
                                    selectHoveredResult(result.id)
                                }
                            }
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: NoteSearchResultFramesKey.self,
                                        value: [
                                            result.id: geometry.frame(
                                                in: .global
                                            )
                                        ]
                                    )
                                }
                            }
                            if index < controller.results.count - 1 {
                                Divider()
                                    .overlay(palette.separator)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: NoteSearchViewportFrameKey.self,
                            value: geometry.frame(in: .global)
                        )
                    }
                }
                .onPreferenceChange(NoteSearchResultFramesKey.self) { frames in
                    resultFrames = frames
                }
                .onPreferenceChange(NoteSearchViewportFrameKey.self) { frame in
                    resultsViewportFrame = frame
                }
                .onChange(of: keyboardScrollRequest) { request in
                    guard let request else {
                        return
                    }

                    DispatchQueue.main.async {
                        revealKeyboardSelection(request, using: proxy)
                    }
                }
            }
        }
    }

    private func searchStatus(
        icon: String,
        title: String,
        palette: AppTheme.Palette
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(palette.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultRow(
        _ result: NoteSearchResult,
        isSelected: Bool,
        palette: AppTheme.Palette
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)

                Text(appState.displayTitle(for: result.dateKey))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(result.matchCountLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
            }

            Text(result.snippet)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? palette.text : palette.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(isSelected ? palette.accent.opacity(0.17) : Color.clear)
        .contentShape(Rectangle())
    }

    private func openSelectedResult() {
        guard let result = controller.selectedResult else {
            return
        }
        onSelect(result)
    }

    private func moveKeyboardSelection(by offset: Int) {
        guard controller.moveSelection(by: offset) else {
            return
        }
        keyboardNavigationPointerLocation = NSEvent.mouseLocation
        guard let result = controller.selectedResult else {
            return
        }

        keyboardScrollRequest = NoteSearchKeyboardScrollRequest(
            resultID: result.id,
            direction: offset
        )
    }

    private func selectHoveredResult(_ resultID: String) {
        let screenPointerLocation = NSEvent.mouseLocation
        guard NoteSearchPointerSelectionPolicy.shouldSelectHoveredResult(
            keyboardPointerLocation: keyboardNavigationPointerLocation,
            currentPointerLocation: screenPointerLocation
        ) else {
            return
        }

        keyboardNavigationPointerLocation = nil
        controller.selectResult(id: resultID)
    }

    private func revealKeyboardSelection(
        _ request: NoteSearchKeyboardScrollRequest,
        using proxy: ScrollViewProxy
    ) {
        guard let alignment = NoteSearchScrollPolicy.alignment(
            for: resultFrames[request.resultID],
            viewportFrame: resultsViewportFrame,
            direction: request.direction
        ) else {
            return
        }

        proxy.scrollTo(
            request.resultID,
            anchor: alignment == .top ? .top : .bottom
        )
    }

    private func handleEscape() {
        if !controller.handleEscape() {
            onDismiss()
        }
    }
}

struct NoteSearchKeyboardScrollRequest: Equatable {
    let token = UUID()
    let resultID: String
    let direction: Int

    static func == (
        lhs: NoteSearchKeyboardScrollRequest,
        rhs: NoteSearchKeyboardScrollRequest
    ) -> Bool {
        lhs.token == rhs.token
    }
}

enum NoteSearchScrollAlignment: Equatable {
    case top
    case bottom
}

enum NoteSearchScrollPolicy {
    static func alignment(
        for frame: CGRect?,
        viewportFrame: CGRect,
        direction: Int
    ) -> NoteSearchScrollAlignment? {
        guard let frame, !viewportFrame.isEmpty else {
            return direction < 0 ? .top : .bottom
        }
        if frame.minY < viewportFrame.minY {
            return .top
        }
        if frame.maxY > viewportFrame.maxY {
            return .bottom
        }
        return nil
    }
}

enum NoteSearchPointerSelectionPolicy {
    static func shouldSelectHoveredResult(
        keyboardPointerLocation: CGPoint?,
        currentPointerLocation: CGPoint,
        movementTolerance: CGFloat = 1
    ) -> Bool {
        guard let keyboardPointerLocation else {
            return true
        }

        return hypot(
            currentPointerLocation.x - keyboardPointerLocation.x,
            currentPointerLocation.y - keyboardPointerLocation.y
        ) > movementTolerance
    }
}

private struct NoteSearchResultFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct NoteSearchViewportFrameKey: PreferenceKey {
    static var defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct NoteSearchField: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let palette: AppTheme.Palette
    let onMoveSelection: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if let searchCell = field.cell as? NSSearchFieldCell {
            searchCell.searchButtonCell = nil
            searchCell.cancelButtonCell = nil
        }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        field.textColor = palette.textNS
        field.placeholderAttributedString = NSAttributedString(
            string: "Search notes",
            attributes: [.foregroundColor: palette.secondaryTextNS]
        )
        if field.stringValue != text {
            field.stringValue = text
        }

        if isFocused, field.window?.firstResponder !== field.currentEditor() {
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NoteSearchField

        init(parent: NoteSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else {
                return
            }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard let command = NoteSearchFieldCommand.resolve(commandSelector) else {
                return false
            }

            switch command {
            case let .moveSelection(offset):
                parent.onMoveSelection(offset)
            case .submit:
                parent.onSubmit()
            case .cancel:
                parent.onCancel()
            }
            return true
        }
    }
}

enum NoteSearchFieldCommand: Equatable {
    case moveSelection(offset: Int)
    case submit
    case cancel

    static func resolve(_ selector: Selector) -> NoteSearchFieldCommand? {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            return .moveSelection(offset: 1)
        case #selector(NSResponder.moveUp(_:)):
            return .moveSelection(offset: -1)
        case #selector(NSResponder.insertNewline(_:)):
            return .submit
        case #selector(NSResponder.cancelOperation(_:)):
            return .cancel
        default:
            return nil
        }
    }
}

import AppKit
import SwiftUI
import Vision
import VisionKit

private enum TodoLayout {
    static let checkboxFrameWidth: CGFloat = 26
    static let checkboxFrameHeight: CGFloat = 22
    static let checkboxVisualSize: CGFloat = 16
    static let checkboxTextGap: CGFloat = 8
    static let markdownIndentColumnsPerLevel: CGFloat = 4

    static var checkboxDrawInset: CGFloat {
        (checkboxFrameWidth - checkboxVisualSize) / 2
    }

    static var taskTextOffset: CGFloat {
        checkboxVisualSize + checkboxTextGap
    }

    static var levelIndent: CGFloat {
        taskTextOffset
    }
}

struct DailyNoteEditorView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        InlineTodoTextEditor(
            palette: palette,
            dateKey: appState.currentDateKey,
            text: Binding(
                get: {
                    appState.currentPage.noteText
                },
                set: { newValue in
                    appState.updateNoteText(newValue)
                }
            )
        )
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.paperInset.opacity(0.76))
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
}

private struct InlineTodoTextEditor: NSViewRepresentable {
    var palette: AppTheme.Palette
    var dateKey: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> InlineTodoTextEditorContainer {
        let view = InlineTodoTextEditorContainer(palette: palette, dateKey: dateKey)
        view.onTextChange = { [coordinator = context.coordinator] newText in
            coordinator.text.wrappedValue = newText
        }
        view.setText(text)
        return view
    }

    func updateNSView(_ nsView: InlineTodoTextEditorContainer, context: Context) {
        context.coordinator.text = $text
        nsView.setTheme(palette)
        nsView.setDateKey(dateKey)

        guard nsView.canApplyExternalTextUpdate else {
            return
        }

        if nsView.text != text {
            nsView.setText(text)
        }
    }

    final class Coordinator {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }
    }
}

private final class InlineTodoTextEditorContainer: NSView, NSTextViewDelegate {
    private enum LineKind: Equatable {
        case normal
        case task(indentColumns: Int, isCompleted: Bool)
        case bullet(indentColumns: Int)
        case numbered(indentColumns: Int, number: Int)
        case quote
        case codeBlock(language: String?)
        case horizontalRule
        case tableRow(isHeader: Bool, columnCount: Int)
        case continuation(indentColumns: Int)

        var indentColumns: Int {
            switch self {
            case .normal, .quote, .codeBlock, .horizontalRule, .tableRow:
                return 0
            case .task(let indentColumns, _),
                 .bullet(let indentColumns),
                 .numbered(let indentColumns, _),
                 .continuation(let indentColumns):
                return indentColumns
            }
        }

        var isTask: Bool {
            if case .task = self {
                return true
            }

            return false
        }

        var isCodeBlock: Bool {
            if case .codeBlock = self {
                return true
            }

            return false
        }

        var isStructured: Bool {
            switch self {
            case .normal:
                return false
            case .task, .bullet, .numbered, .quote, .codeBlock, .horizontalRule, .tableRow, .continuation:
                return true
            }
        }

        var supportsSoftLineBreak: Bool {
            switch self {
            case .normal, .horizontalRule, .tableRow:
                return false
            case .task, .bullet, .numbered, .quote, .codeBlock, .continuation:
                return true
            }
        }
    }

    private struct DisplayDocument {
        var text: String
        var lineKinds: [LineKind]
    }

    private struct DisplayLineInfo {
        var index: Int
        var lineRange: NSRange
        var contentRange: NSRange
        var text: String
    }

    private struct MarkdownImageReference {
        var altText: String
        var path: String
        var width: CGFloat?
    }

    private enum HorizontalMovementDirection {
        case left
        case right
    }

    private enum ImageCaretEdge {
        case leading
        case trailing
    }

    private enum SlashCommand: String, CaseIterable {
        case todo
        case heading1
        case heading2
        case heading3
        case heading4
        case bulletedList
        case numberedList
        case quote
        case codeBlock
        case divider

        var title: String {
            switch self {
            case .todo:
                return "Todo list"
            case .heading1:
                return "Heading 1"
            case .heading2:
                return "Heading 2"
            case .heading3:
                return "Heading 3"
            case .heading4:
                return "Heading 4"
            case .bulletedList:
                return "Bulleted list"
            case .numberedList:
                return "Numbered list"
            case .quote:
                return "Quote"
            case .codeBlock:
                return "Code block"
            case .divider:
                return "Divider"
            }
        }

        var syntaxHint: String {
            switch self {
            case .todo:
                return "- [ ]"
            case .heading1:
                return "#"
            case .heading2:
                return "##"
            case .heading3:
                return "###"
            case .heading4:
                return "####"
            case .bulletedList:
                return "-"
            case .numberedList:
                return "1."
            case .quote:
                return ">"
            case .codeBlock:
                return "```lang"
            case .divider:
                return "---"
            }
        }

        var prefix: String {
            switch self {
            case .todo:
                return ""
            case .heading1:
                return "# "
            case .heading2:
                return "## "
            case .heading3:
                return "### "
            case .heading4:
                return "#### "
            case .bulletedList:
                return "- "
            case .numberedList:
                return "1. "
            case .quote:
                return "> "
            case .codeBlock:
                return "```\n\n```"
            case .divider:
                return "---"
            }
        }

        func matches(query: String) -> Bool {
            let normalizedQuery = query
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !normalizedQuery.isEmpty else {
                return self == .todo
            }

            switch self {
            case .todo:
                return ["todo", "task", "check", "checkbox"].contains(normalizedQuery)
            case .heading1:
                return ["h1", "heading1", "heading 1", "title"].contains(normalizedQuery)
            case .heading2:
                return ["h2", "heading2", "heading 2"].contains(normalizedQuery)
            case .heading3:
                return ["h3", "heading3", "heading 3"].contains(normalizedQuery)
            case .heading4:
                return ["h4", "heading4", "heading 4"].contains(normalizedQuery)
            case .bulletedList:
                return ["bullet", "bulleted", "bulletedlist", "bulleted list", "ul", "list"].contains(normalizedQuery)
            case .numberedList:
                return ["number", "numbered", "numberedlist", "numbered list", "ol"].contains(normalizedQuery)
            case .quote:
                return ["quote", "blockquote"].contains(normalizedQuery)
            case .codeBlock:
                return normalizedQuery == "code"
                    || normalizedQuery == "codeblock"
                    || normalizedQuery == "code block"
                    || normalizedQuery.hasPrefix("code ")
                    || normalizedQuery.hasPrefix("```")
            case .divider:
                return ["divider", "separator", "splitter", "spliter", "hr", "rule", "---"].contains(normalizedQuery)
            }
        }
    }

    private struct SlashCommandContext {
        var slashRange: NSRange
        var lineIndex: Int
        var query: String
    }

    private struct MarkdownTableRenderBlock {
        var rawLineRange: Range<Int>
        var rowLineIndices: [Int]
        var rows: [[String]]
        var columnCount: Int
    }

    private struct RenderedMarkdownTableRow {
        var isHeader: Bool
        var cells: [String]
        var columnCount: Int
        var rowIndex: Int
        var rowCount: Int
    }

    private struct MarkdownCodeRenderBlock {
        var lineRange: Range<Int>
        var language: String?
    }

    private struct EditorSnapshot {
        var text: String
        var lineKinds: [LineKind]
        var selectedRange: NSRange

        func isSame(as other: EditorSnapshot) -> Bool {
            text == other.text
                && lineKinds == other.lineKinds
                && NSEqualRanges(selectedRange, other.selectedRange)
        }
    }

    private struct PendingDefaultTextEdit {
        var text: String
        var lineKinds: [LineKind]
        var range: NSRange
        var replacement: String
    }

    private let scrollView = NSScrollView()
    private let textView = TodoTextView()
    private let overlayView = TodoCheckboxOverlayView()
    private let imageInteractionView = MarkdownImageInteractionOverlayView()
    private let imageOverlayView = MarkdownImageOverlayView()
    private let slashPaletteView = SlashCommandPaletteView()
    private let baseFont = NSFont.systemFont(ofSize: 14)
    private var palette: AppTheme.Palette
    private var dateKey: String
    private var imageCache: [String: NSImage] = [:]
    private var resizingImagePreview: (lineIndex: Int, width: CGFloat)?
    private var lastAppliedImageLayoutWidth: CGFloat?
    private var lineKinds: [LineKind] = [.normal]
    private var isApplyingProgrammaticChange = false
    private var isRestoringUndoSnapshot = false
    private var preservesEmptyStructuredLine = false
    private var preservesEmptyStructuredLineOnNextTextChange = false
    private var pendingUndoSnapshot: EditorSnapshot?
    private var pendingDefaultTextEdit: PendingDefaultTextEdit?
    private var isRefreshingSelectionDisplay = false
    private var slashCommandContext: SlashCommandContext?
    private var selectedSlashCommandIndex = 0

    var onTextChange: ((String) -> Void)?

    var text: String {
        markdownText()
    }

    var canApplyExternalTextUpdate: Bool {
        !isComposingMarkedText
    }

    init(frame frameRect: NSRect = .zero, palette: AppTheme.Palette = AppTheme.yellow, dateKey: String = "") {
        self.palette = palette
        self.dateKey = dateKey
        super.init(frame: frameRect)
        configureViews()
    }

    required init?(coder: NSCoder) {
        self.palette = AppTheme.yellow
        self.dateKey = ""
        super.init(coder: coder)
        configureViews()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if !slashPaletteView.isHidden {
            let palettePoint = slashPaletteView.convert(point, from: self)
            if slashPaletteView.bounds.contains(palettePoint) {
                return slashPaletteView.hitTest(palettePoint) ?? slashPaletteView
            }
        }

        return super.hitTest(point)
    }

    func setTheme(_ palette: AppTheme.Palette) {
        guard self.palette != palette else {
            return
        }

        self.palette = palette
        applyTheme()
        refreshEditor()
    }

    func setDateKey(_ dateKey: String) {
        if self.dateKey != dateKey {
            imageInteractionView.clearAnalysisCache()
        }
        self.dateKey = dateKey
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setText(_ text: String) {
        guard !isComposingMarkedText else {
            return
        }

        lastAppliedImageLayoutWidth = nil
        clearEditorUndoHistory()
        pendingUndoSnapshot = nil
        let document = Self.displayDocument(from: text)
        lineKinds = document.lineKinds

        guard textView.string != document.text else {
            refreshEditor()
            return
        }

        isApplyingProgrammaticChange = true
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: document.text, attributes: baseAttributes())
        )
        textView.setSelectedRange(
            NSRange(location: min(textView.selectedRange().location, (document.text as NSString).length), length: 0)
        )
        isApplyingProgrammaticChange = false
        refreshEditor()
    }

    func textDidChange(_ notification: Notification) {
        guard !isApplyingProgrammaticChange else {
            return
        }

        let undoSnapshot = pendingUndoSnapshot
        pendingUndoSnapshot = nil
        let defaultTextEdit = pendingDefaultTextEdit
        pendingDefaultTextEdit = nil

        let shouldPreserveEmptyStructuredLine = preservesEmptyStructuredLineOnNextTextChange
            && textView.string.isEmpty
        preservesEmptyStructuredLineOnNextTextChange = false

        if shouldPreserveEmptyStructuredLine {
            preservesEmptyStructuredLine = true
        }
        defer {
            if shouldPreserveEmptyStructuredLine {
                preservesEmptyStructuredLine = false
            }
        }

        if let defaultTextEdit {
            lineKinds = lineKindsAfterDefaultTextEdit(defaultTextEdit)
        }

        reconcileLineKinds()
        if isComposingMarkedText {
            refreshOverlay()
            return
        }

        if promoteTypedMarkdownTaskIfNeeded() {
            registerUndoSnapshotIfChanged(from: undoSnapshot)
            return
        }

        if promoteTypedMarkdownStructureIfNeeded() {
            registerUndoSnapshotIfChanged(from: undoSnapshot)
            return
        }

        notifyTextChangedAndRefresh(scrollSelection: true)
        registerUndoSnapshotIfChanged(from: undoSnapshot)
        showSlashCommandMenuIfNeeded()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isRefreshingSelectionDisplay,
              !isComposingMarkedText
        else {
            return
        }

        isRefreshingSelectionDisplay = true
        snapSelectionAroundImageIfNeeded()
        if NSApp.currentEvent?.type != .leftMouseDragged {
            applyDisplayAttributes()
        }
        refreshOverlay()
        if slashCommandContextForCurrentSelection() == nil {
            hideSlashCommandPalette()
        }
        isRefreshingSelectionDisplay = false
    }

    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        if !isApplyingProgrammaticChange && !isRestoringUndoSnapshot && pendingUndoSnapshot == nil {
            pendingUndoSnapshot = editorSnapshot()
        }

        if !isApplyingProgrammaticChange && !isRestoringUndoSnapshot {
            pendingDefaultTextEdit = PendingDefaultTextEdit(
                text: textView.string,
                lineKinds: lineKinds,
                range: affectedCharRange,
                replacement: replacementString ?? ""
            )
        }

        return true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewline(_:)):
            if applySlashCommandBeforeReturnIfNeeded() {
                return true
            }

            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                return insertSoftLineBreak()
            }

            return insertReturn()

        case #selector(NSResponder.insertTab(_:)):
            if textView.selectedRange().length > 0 {
                return adjustSelectedLinesIndent(by: 4)
            }
            return adjustCaretIndent(by: 4)

        case #selector(NSResponder.insertBacktab(_:)):
            if textView.selectedRange().length > 0 {
                return adjustSelectedLinesIndent(by: -4)
            }
            return adjustCaretIndent(by: -4)

        case #selector(NSResponder.moveUp(_:)):
            return moveSlashCommandSelection(by: -1)

        case #selector(NSResponder.moveDown(_:)):
            return moveSlashCommandSelection(by: 1)

        case #selector(NSResponder.cancelOperation(_:)):
            if slashCommandContext != nil {
                hideSlashCommandPalette()
                return true
            }

            return false

        case #selector(NSResponder.deleteBackward(_:)):
            if textView.selectedRange().length > 0 {
                return deleteSelectionPreservingLineKinds()
            }

            if deleteImageBeforeCaret() {
                return true
            }

            return handleDeleteBackward()

        case #selector(NSResponder.deleteForward(_:)):
            if textView.selectedRange().length > 0 {
                return deleteSelectionPreservingLineKinds()
            }

            return deleteImageAfterCaret()

        case #selector(NSResponder.moveRight(_:)):
            return moveAcrossImageIfNeeded(direction: .right)

        case #selector(NSResponder.moveLeft(_:)):
            return moveAcrossImageIfNeeded(direction: .left)

        case #selector(NSResponder.moveWordRight(_:)),
             #selector(NSResponder.moveToRightEndOfLine(_:)):
            return moveAcrossImageIfNeeded(direction: .right)

        case #selector(NSResponder.moveWordLeft(_:)),
             #selector(NSResponder.moveToLeftEndOfLine(_:)):
            return moveAcrossImageIfNeeded(direction: .left)

        default:
            return false
        }
    }

    override func layout() {
        super.layout()
        synchronizeImageLineHeightsIfNeeded()
        refreshOverlay()
        if slashCommandContext != nil {
            positionSlashCommandPalette()
        }
    }

    private func synchronizeImageLineHeightsIfNeeded() {
        guard !isComposingMarkedText,
              lineInfos().contains(where: { imageReference(in: $0.text) != nil })
        else {
            return
        }

        let usableWidth = max(0, textView.bounds.width - textView.textContainerInset.width * 2)
        guard usableWidth > 0,
              lastAppliedImageLayoutWidth.map({ abs($0 - usableWidth) > 0.5 }) ?? true
        else {
            return
        }

        lastAppliedImageLayoutWidth = usableWidth
        applyDisplayAttributes()

        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
    }

    private func configureViews() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: lineHeight(), right: 0)

        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.font = baseFont
        textView.defaultParagraphStyle = baseParagraphStyle()
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.copyHandler = { [weak self] in
            self?.copySelectionToPasteboard() ?? false
        }
        textView.cutHandler = { [weak self] in
            self?.cutSelectionToPasteboard() ?? false
        }
        textView.pasteHandler = { [weak self] in
            guard let self else {
                return false
            }

            return self.pasteImageFromPasteboard()
                || self.pasteMarkdownTasksFromPasteboard()
        }
        textView.canPasteHandler = {
            Self.canPasteImage(from: .general) || NSPasteboard.general.string(forType: .string) != nil
        }
        textView.checkboxMouseDownHandler = { [weak self] event in
            self?.handleCheckboxMouseDown(event) ?? false
        }
        textView.selectionDragDidEndHandler = { [weak self] in
            guard let self else { return }
            self.applyDisplayAttributes()
            self.refreshOverlay()
        }
        textView.imageCursorProvider = { [weak self] point in
            guard let self else {
                return nil
            }

            let interactionPoint = self.imageInteractionView.convert(point, from: self.textView)
            return self.imageInteractionView.cursor(at: interactionPoint)
        }

        imageInteractionView.onSelectImage = { [weak self] item, event in
            guard let self else {
                return
            }

            let point = self.imageOverlayView.convert(event.locationInWindow, from: nil)
            self.selectImage(item, at: point)
        }
        imageInteractionView.onResizeImage = { [weak self] item, event in
            guard let self else {
                return
            }

            let point = self.imageOverlayView.convert(event.locationInWindow, from: nil)
            _ = self.resizeImage(item, from: point)
        }

        imageOverlayView.translatesAutoresizingMaskIntoConstraints = false
        imageInteractionView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        slashPaletteView.configure(
            commands: SlashCommand.allCases.map { command in
                (title: command.title, syntaxHint: command.syntaxHint, rawValue: command.rawValue)
            }
        )
        slashPaletteView.onSelect = { [weak self] rawValue in
            guard let command = SlashCommand(rawValue: rawValue) else {
                return
            }

            self?.applySlashCommand(command)
        }
        slashPaletteView.onHover = { [weak self] rawValue in
            guard let command = SlashCommand(rawValue: rawValue),
                  let index = SlashCommand.allCases.firstIndex(of: command)
            else {
                return
            }

            self?.selectedSlashCommandIndex = index
            self?.slashPaletteView.selectedIndex = index
        }
        slashPaletteView.isHidden = true
        applyTheme()

        scrollView.documentView = textView
        addSubview(scrollView)
        addSubview(imageInteractionView)
        addSubview(imageOverlayView)
        addSubview(overlayView)
        addSubview(slashPaletteView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageInteractionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageInteractionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageInteractionView.topAnchor.constraint(equalTo: topAnchor),
            imageInteractionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageOverlayView.topAnchor.constraint(equalTo: topAnchor),
            imageOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(visibleBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    private func applyTheme() {
        textView.textColor = palette.textNS
        updateSelectionAppearance()
        updateInsertionPointColor(showCustomImageCaret: false)
        textView.typingAttributes = baseAttributes()
        overlayView.palette = palette
        imageOverlayView.palette = palette
        slashPaletteView.palette = palette
    }

    private func updateSelectionAppearance() {
        textView.selectedTextAttributes = [
            .backgroundColor: selectedTextBackgroundColor(),
            .foregroundColor: NSColor.white
        ]
        textView.setNeedsDisplay(textView.visibleRect)
    }

    private func selectedTextBackgroundColor() -> NSColor {
        if palette.kind == .dark {
            return NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.45, alpha: 1)
        }

        return palette.accentNS
    }

    private func updateInsertionPointColor(showCustomImageCaret: Bool) {
        textView.insertionPointColor = showCustomImageCaret ? .clear : palette.accentNS
    }

    @objc private func visibleBoundsChanged() {
        refreshOverlay()
    }

    private func insertReturn() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location)
        else {
            return false
        }

        if case .horizontalRule = kind(at: line.index) {
            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .normal
            )
        }

        if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           kind(at: line.index).isStructured,
           case .continuation = kind(at: line.index) {
            // Continuations are handled below because they need to restore the parent block kind.
        } else if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  kind(at: line.index).isStructured {
            let undoSnapshot = editorSnapshot()
            lineKinds[line.index] = .normal
            notifyTextChangedAndRefresh(scrollSelection: true)
            registerUndoSnapshotIfChanged(from: undoSnapshot)
            return true
        }

        switch kind(at: line.index) {
        case .task(let indentColumns, _):
            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .task(indentColumns: indentColumns, isCompleted: false)
            )

        case .bullet(let indentColumns):
            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .bullet(indentColumns: indentColumns)
            )

        case .numbered(let indentColumns, let number):
            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .numbered(indentColumns: indentColumns, number: number + 1)
            )

        case .quote:
            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .quote
            )

        case .codeBlock(let language):
            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .codeBlock(language: language)
            )

        case .continuation(let indentColumns):
            if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let undoSnapshot = editorSnapshot()
                lineKinds[line.index] = structuredKindAfterContinuation(at: line.index, indentColumns: indentColumns)
                notifyTextChangedAndRefresh(scrollSelection: true)
                registerUndoSnapshotIfChanged(from: undoSnapshot)
                return true
            }

            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: structuredKindAfterContinuation(at: line.index, indentColumns: indentColumns)
            )

        case .normal, .tableRow:
            return false
        case .horizontalRule:
            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .normal
            )
        }
    }

    private func insertSoftLineBreak() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location)
        else {
            return false
        }

        switch kind(at: line.index) {
        case .codeBlock(let language):
            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .codeBlock(language: language)
            )

        case let kind where kind.supportsSoftLineBreak:
            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .continuation(indentColumns: kind.indentColumns)
            )

        default:
            return false
        }
    }

    private func structuredKindAfterContinuation(at lineIndex: Int, indentColumns: Int) -> LineKind {
        guard lineIndex > 0 else {
            return .task(indentColumns: indentColumns, isCompleted: false)
        }

        switch kind(at: lineIndex - 1) {
        case .task:
            return .task(indentColumns: indentColumns, isCompleted: false)
        case .bullet:
            return .bullet(indentColumns: indentColumns)
        case .numbered(_, let number):
            return .numbered(indentColumns: indentColumns, number: number + 1)
        case .quote:
            return .quote
        case .codeBlock(let language):
            return .codeBlock(language: language)
        case .horizontalRule, .tableRow:
            return .normal
        case .continuation:
            return structuredKindAfterContinuation(at: lineIndex - 1, indentColumns: indentColumns)
        case .normal:
            return .normal
        }
    }

    private func insertLineBreak(
        at selectedRange: NSRange,
        afterLineIndex lineIndex: Int,
        newLineKind: LineKind
    ) -> Bool {
        applyTextStorageEdit(
            range: selectedRange,
            replacement: "\n",
            selectedRange: NSRange(location: selectedRange.location + 1, length: 0)
        ) {
            lineKinds.insert(newLineKind, at: min(lineIndex + 1, lineKinds.count))
            if case .numbered = newLineKind {
                renumberNumberedLists()
            }
        }
    }

    private func showSlashCommandMenuIfNeeded() {
        guard let context = slashCommandContextForCurrentSelection() else {
            hideSlashCommandPalette()
            return
        }

        slashCommandContext = context
        selectedSlashCommandIndex = 0
        slashPaletteView.isHidden = false
        positionSlashCommandPalette()
        slashPaletteView.resetForOpening()
    }

    private func slashCommandContextForCurrentSelection() -> SlashCommandContext? {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              selectedRange.location > 0,
              let line = lineInfo(at: selectedRange.location)
        else {
            return nil
        }

        let slashLocation = selectedRange.location - 1
        guard slashLocation >= line.contentRange.location,
              slashLocation < NSMaxRange(line.contentRange)
        else {
            return nil
        }

        let nsText = textView.string as NSString
        guard nsText.substring(with: NSRange(location: slashLocation, length: 1)) == "/" else {
            return nil
        }

        let textBeforeSlashLength = slashLocation - line.contentRange.location
        let textBeforeSlash = textBeforeSlashLength > 0
            ? nsText.substring(with: NSRange(location: line.contentRange.location, length: textBeforeSlashLength))
            : ""
        guard textBeforeSlash.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }

        return SlashCommandContext(
            slashRange: NSRange(
                location: line.contentRange.location,
                length: textBeforeSlashLength + 1
            ),
            lineIndex: line.index,
            query: ""
        )
    }

    private func slashCommandMenuPoint() -> NSPoint {
        let selectedRange = textView.selectedRange()
        let screenRect = textView.firstRect(forCharacterRange: selectedRange, actualRange: nil)
        guard let window = textView.window else {
            return NSPoint(x: textView.textContainerInset.width, y: lineHeight())
        }

        let windowPoint = window.convertPoint(fromScreen: NSPoint(x: screenRect.minX, y: screenRect.minY))
        let viewPoint = textView.convert(windowPoint, from: nil)
        return NSPoint(x: max(0, viewPoint.x), y: viewPoint.y + lineHeight())
    }

    private func positionSlashCommandPalette() {
        let pointInTextView = slashCommandMenuPoint()
        let point = convert(pointInTextView, from: textView)
        let size = slashPaletteView.fittingSize
        let width = max(184, size.width)
        let desiredHeight = max(184, size.height)
        let margin: CGFloat = 8
        let spaceBelow = max(0, bounds.height - point.y - margin)
        let spaceAbove = max(0, point.y - margin)
        let opensBelow = spaceBelow >= min(desiredHeight, spaceAbove)
        let availableHeight = opensBelow ? spaceBelow : spaceAbove
        let maxMenuHeight = max(lineHeight(), bounds.height - margin * 2)
        let height = min(desiredHeight, max(lineHeight(), availableHeight), maxMenuHeight)
        let x = min(max(8, point.x), max(8, bounds.width - width - 8))
        let preferredY = opensBelow ? point.y : point.y - height
        let y = min(max(margin, preferredY), max(margin, bounds.height - height - margin))
        slashPaletteView.frame = NSRect(x: x, y: y, width: width, height: height)
        textView.slashCommandCursorRects = [textView.convert(slashPaletteView.bounds, from: slashPaletteView)]
        slashPaletteView.scrollSelectedCommandToVisible()
    }

    private func hideSlashCommandPalette() {
        slashCommandContext = nil
        textView.slashCommandCursorRects = []
        slashPaletteView.isHidden = true
    }

    private func moveSlashCommandSelection(by delta: Int) -> Bool {
        guard slashCommandContext != nil else {
            return false
        }

        let commands = SlashCommand.allCases
        guard !commands.isEmpty else {
            return true
        }

        let previousIndex = selectedSlashCommandIndex
        selectedSlashCommandIndex = (selectedSlashCommandIndex + delta + commands.count) % commands.count
        slashPaletteView.selectedIndex = selectedSlashCommandIndex
        if delta > 0, selectedSlashCommandIndex < previousIndex {
            slashPaletteView.scrollSelectedCommandToTop()
        } else if delta < 0, selectedSlashCommandIndex > previousIndex {
            slashPaletteView.scrollSelectedCommandToBottom()
        }
        return true
    }

    @objc private func applySlashCommandFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let command = SlashCommand(rawValue: rawValue)
        else {
            return
        }

        applySlashCommand(command)
    }

    private func applySlashCommand(_ command: SlashCommand, context providedContext: SlashCommandContext? = nil) {
        guard let context = providedContext ?? slashCommandContext else {
            return
        }

        hideSlashCommandPalette()
        let infos = lineInfos()
        guard infos.indices.contains(context.lineIndex),
              context.slashRange.location >= infos[context.lineIndex].contentRange.location,
              NSMaxRange(context.slashRange) <= NSMaxRange(infos[context.lineIndex].contentRange)
        else {
            return
        }

        switch command {
        case .todo:
            applyStructuredSlashCommand(context, kind: .task(indentColumns: 0, isCompleted: false))
        case .bulletedList:
            applyStructuredSlashCommand(context, kind: .bullet(indentColumns: 0))
        case .numberedList:
            applyStructuredSlashCommand(context, kind: .numbered(indentColumns: 0, number: 1))
        case .quote:
            applyStructuredSlashCommand(context, kind: .quote)
        case .codeBlock:
            applyStructuredSlashCommand(context, kind: .codeBlock(language: codeLanguage(fromSlashQuery: context.query)))
        case .divider:
            applyStructuredSlashCommand(context, kind: .horizontalRule)
        default:
            applyTextSlashCommand(context, replacement: command.prefix, insertedLineKinds: [])
        }
    }

    private func applySlashCommandBeforeReturnIfNeeded() -> Bool {
        guard let context = slashCommandContextForReturn(),
              let command = slashCommand(for: context)
        else {
            return false
        }

        applySlashCommand(command, context: context)
        return true
    }

    private func slashCommand(for context: SlashCommandContext) -> SlashCommand? {
        if context.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let commands = SlashCommand.allCases
            guard commands.indices.contains(selectedSlashCommandIndex) else {
                return .todo
            }

            return commands[selectedSlashCommandIndex]
        }

        return SlashCommand.allCases.first(where: { $0.matches(query: context.query) })
    }

    private func codeLanguage(fromSlashQuery query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let lowercased = trimmed.lowercased()
        let rawLanguage: String
        if lowercased.hasPrefix("code ") {
            rawLanguage = String(trimmed.dropFirst(5))
        } else if lowercased.hasPrefix("```") {
            rawLanguage = String(trimmed.dropFirst(3))
        } else {
            return nil
        }

        let language = rawLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !language.isEmpty,
              language.rangeOfCharacter(from: CharacterSet(charactersIn: "` \t\n")) == nil
        else {
            return nil
        }

        return language
    }

    private func slashCommandContextForReturn() -> SlashCommandContext? {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location),
              selectedRange.location >= line.contentRange.location
        else {
            return nil
        }

        let prefixRange = NSRange(
            location: line.contentRange.location,
            length: selectedRange.location - line.contentRange.location
        )
        let nsText = textView.string as NSString
        let prefixText = nsText.substring(with: prefixRange)
        guard prefixText.hasPrefix("/") else {
            return nil
        }

        let query = String(prefixText.dropFirst())
        guard !query.contains("\n") else {
            return nil
        }

        return SlashCommandContext(
            slashRange: prefixRange,
            lineIndex: line.index,
            query: query
        )
    }

    private func applyStructuredSlashCommand(_ context: SlashCommandContext, kind: LineKind) {
        let selectedLocation = context.slashRange.location
        preservesEmptyStructuredLine = true
        defer {
            preservesEmptyStructuredLine = false
        }

        _ = applyTextStorageEdit(
            range: context.slashRange,
            replacement: "",
            selectedRange: NSRange(location: selectedLocation, length: 0)
        ) {
            lineKinds[context.lineIndex] = kind
        }
    }

    private func applyTextSlashCommand(
        _ context: SlashCommandContext,
        replacement: String,
        insertedLineKinds: [LineKind]
    ) {
        let replacementLength = (replacement as NSString).length
        let selectedLocation: Int
        if replacement == "```\n\n```" {
            selectedLocation = context.slashRange.location + 4
        } else {
            selectedLocation = context.slashRange.location + replacementLength
        }

        _ = applyTextStorageEdit(
            range: context.slashRange,
            replacement: replacement,
            selectedRange: NSRange(location: selectedLocation, length: 0)
        ) {
            lineKinds[context.lineIndex] = .normal
            if !insertedLineKinds.isEmpty {
                lineKinds.insert(
                    contentsOf: insertedLineKinds,
                    at: min(context.lineIndex + 1, lineKinds.count)
                )
            }
        }
    }

    private func adjustCaretIndent(by delta: Int) -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location),
              selectedRange.location >= line.contentRange.location
        else {
            return true
        }

        if delta > 0 {
            let indentation = String(repeating: " ", count: delta)
            return applyTextStorageEdit(
                range: selectedRange,
                replacement: indentation,
                selectedRange: NSRange(
                    location: selectedRange.location + (indentation as NSString).length,
                    length: 0
                )
            ) {}
        }

        let lineStart = line.contentRange.location
        let precedingLength = selectedRange.location - lineStart
        guard precedingLength > 0 else {
            return true
        }

        let nsText = textView.string as NSString
        let previousCharacterRange = NSRange(location: selectedRange.location - 1, length: 1)
        if nsText.substring(with: previousCharacterRange) == "\t" {
            return applyTextStorageEdit(
                range: previousCharacterRange,
                replacement: "",
                selectedRange: NSRange(location: selectedRange.location - 1, length: 0)
            ) {}
        }

        let candidateLength = min(-delta, precedingLength)
        let candidateRange = NSRange(
            location: selectedRange.location - candidateLength,
            length: candidateLength
        )
        let trailingSpaces = nsText.substring(with: candidateRange).reversed().prefix { $0 == " " }.count
        guard trailingSpaces > 0 else {
            return true
        }

        let removalRange = NSRange(
            location: selectedRange.location - trailingSpaces,
            length: trailingSpaces
        )
        return applyTextStorageEdit(
            range: removalRange,
            replacement: "",
            selectedRange: NSRange(location: removalRange.location, length: 0)
        ) {}
    }

    private func adjustSelectedLinesIndent(by delta: Int) -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0 else {
            return false
        }

        let infos = lineInfos()
        let selectionEndLocation = max(selectedRange.location, NSMaxRange(selectedRange) - 1)
        guard let firstLineIndex = lineInfo(at: selectedRange.location)?.index,
              let lastLineIndex = lineInfo(at: selectionEndLocation)?.index,
              infos.indices.contains(firstLineIndex),
              infos.indices.contains(lastLineIndex)
        else {
            return true
        }

        let selectedLineRange = min(firstLineIndex, lastLineIndex)...max(firstLineIndex, lastLineIndex)
        var updatedLines = displayLines()
        var updatedKinds = lineKinds
        var textEdits: [(range: NSRange, insertedLength: Int)] = []
        var didChange = false

        for lineIndex in selectedLineRange {
            guard updatedLines.indices.contains(lineIndex),
                  updatedKinds.indices.contains(lineIndex),
                  infos.indices.contains(lineIndex)
            else {
                continue
            }

            switch updatedKinds[lineIndex] {
            case .task(let indentColumns, let isCompleted):
                let newIndentColumns = max(0, indentColumns + delta)
                guard newIndentColumns != indentColumns else { continue }
                updatedKinds[lineIndex] = .task(
                    indentColumns: newIndentColumns,
                    isCompleted: isCompleted
                )
                didChange = true

            case .bullet(let indentColumns):
                let newIndentColumns = max(0, indentColumns + delta)
                guard newIndentColumns != indentColumns else { continue }
                updatedKinds[lineIndex] = .bullet(indentColumns: newIndentColumns)
                didChange = true

            case .numbered(let indentColumns, let number):
                let newIndentColumns = max(0, indentColumns + delta)
                guard newIndentColumns != indentColumns else { continue }
                updatedKinds[lineIndex] = .numbered(
                    indentColumns: newIndentColumns,
                    number: newIndentColumns == indentColumns ? number : 1
                )
                didChange = true

            case .continuation(let indentColumns):
                let newIndentColumns = max(0, indentColumns + delta)
                guard newIndentColumns != indentColumns else { continue }
                updatedKinds[lineIndex] = .continuation(indentColumns: newIndentColumns)
                didChange = true

            case .normal:
                let originalLine = updatedLines[lineIndex]
                if delta > 0 {
                    updatedLines[lineIndex] = String(repeating: " ", count: delta) + originalLine
                    textEdits.append((
                        range: NSRange(location: infos[lineIndex].contentRange.location, length: 0),
                        insertedLength: delta
                    ))
                    didChange = true
                } else if originalLine.hasPrefix("\t") {
                    updatedLines[lineIndex].removeFirst()
                    textEdits.append((
                        range: NSRange(location: infos[lineIndex].contentRange.location, length: 1),
                        insertedLength: 0
                    ))
                    didChange = true
                } else {
                    let removableSpaces = min(-delta, originalLine.prefix { $0 == " " }.count)
                    if removableSpaces > 0 {
                        updatedLines[lineIndex].removeFirst(removableSpaces)
                        textEdits.append((
                            range: NSRange(
                                location: infos[lineIndex].contentRange.location,
                                length: removableSpaces
                            ),
                            insertedLength: 0
                        ))
                        didChange = true
                    }
                }

            case .quote, .codeBlock, .horizontalRule, .tableRow:
                continue
            }
        }

        guard didChange else {
            return true
        }

        let updatedText = updatedLines.joined(separator: "\n")
        let sortedTextEdits = textEdits.sorted { $0.range.location < $1.range.location }
        let updatedSelectionStart = mappedLocation(
            selectedRange.location,
            through: sortedTextEdits
        )
        let updatedSelectionEnd = mappedLocation(
            NSMaxRange(selectedRange),
            through: sortedTextEdits
        )
        let updatedSelectedRange = NSRange(
            location: updatedSelectionStart,
            length: max(0, updatedSelectionEnd - updatedSelectionStart)
        )
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)

        return applyTextStorageEdit(
            range: fullRange,
            replacement: updatedText,
            selectedRange: updatedSelectedRange
        ) {
            lineKinds = updatedKinds
            renumberNumberedLists()
        }
    }

    private func mappedLocation(
        _ originalLocation: Int,
        through edits: [(range: NSRange, insertedLength: Int)]
    ) -> Int {
        var offset = 0

        for edit in edits {
            let editStart = edit.range.location
            let editEnd = NSMaxRange(edit.range)

            if edit.range.length == 0 {
                if originalLocation >= editStart {
                    offset += edit.insertedLength
                }
                continue
            }

            if originalLocation <= editStart {
                break
            }

            if originalLocation < editEnd {
                return editStart + offset + edit.insertedLength
            }

            offset += edit.insertedLength - edit.range.length
        }

        return originalLocation + offset
    }

    private func renumberNumberedLists() {
        var countersByLevel: [Int: Int] = [:]
        var isInsideNumberedBlock = false

        for index in lineKinds.indices {
            switch lineKinds[index] {
            case .numbered(let indentColumns, let storedNumber):
                let level = max(0, indentColumns / Int(TodoLayout.markdownIndentColumnsPerLevel))
                if !isInsideNumberedBlock {
                    countersByLevel.removeAll()
                }

                let number: Int
                if let previousNumber = countersByLevel[level] {
                    number = previousNumber + 1
                } else if level == 0 {
                    number = max(1, storedNumber)
                } else {
                    number = 1
                }

                countersByLevel[level] = number
                countersByLevel = countersByLevel.filter { $0.key <= level }
                lineKinds[index] = .numbered(indentColumns: indentColumns, number: number)
                isInsideNumberedBlock = true

            case .continuation:
                break

            default:
                countersByLevel.removeAll()
                isInsideNumberedBlock = false
            }
        }
    }

    private func handleDeleteBackward() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location)
        else {
            return false
        }

        if shouldPreserveEmptyTaskWhenDeletingBackward(from: selectedRange, in: line) {
            preservesEmptyStructuredLineOnNextTextChange = true
            return false
        }

        guard selectedRange.location == line.contentRange.location else {
            return false
        }

        switch kind(at: line.index) {
        case .task, .bullet, .numbered, .quote, .codeBlock, .horizontalRule, .tableRow, .continuation:
            let undoSnapshot = editorSnapshot()
            lineKinds[line.index] = .normal
            notifyTextChangedAndRefresh(scrollSelection: true)
            registerUndoSnapshotIfChanged(from: undoSnapshot)
            return true
        case .normal:
            return false
        }
    }

    private func deleteImageBeforeCaret() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location),
              imageReference(in: line.text) != nil,
              selectedRange.location > line.contentRange.location,
              selectedRange.location <= NSMaxRange(line.contentRange)
        else {
            return false
        }

        return deleteImageLine(line)
    }

    private func deleteImageAfterCaret() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location),
              imageReference(in: line.text) != nil,
              selectedRange.location >= line.contentRange.location,
              selectedRange.location < NSMaxRange(line.contentRange)
        else {
            return false
        }

        return deleteImageLine(line)
    }

    private func deleteImageLine(_ line: DisplayLineInfo) -> Bool {
        let infos = lineInfos()
        let deleteRange: NSRange
        let selectedRangeAfterDelete: NSRange

        if infos.count <= 1 {
            deleteRange = line.contentRange
            selectedRangeAfterDelete = NSRange(location: line.contentRange.location, length: 0)
        } else if line.index < infos.count - 1 {
            deleteRange = line.lineRange
            selectedRangeAfterDelete = NSRange(location: line.lineRange.location, length: 0)
        } else {
            let previousNewlineLocation = max(0, line.lineRange.location - 1)
            deleteRange = NSRange(
                location: previousNewlineLocation,
                length: NSMaxRange(line.contentRange) - previousNewlineLocation
            )
            selectedRangeAfterDelete = NSRange(location: previousNewlineLocation, length: 0)
        }

        return applyTextStorageEdit(
            range: deleteRange,
            replacement: "",
            selectedRange: selectedRangeAfterDelete
        ) {
            if infos.count <= 1 {
                lineKinds = [.normal]
            } else if lineKinds.indices.contains(line.index) {
                lineKinds.remove(at: line.index)
            }
        }
    }

    private func moveAcrossImageIfNeeded(direction: HorizontalMovementDirection) -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location),
              imageReference(in: line.text) != nil
        else {
            return false
        }

        let start = line.contentRange.location
        let end = NSMaxRange(line.contentRange)
        let targetLocation: Int?

        switch direction {
        case .right:
            targetLocation = selectedRange.location >= start && selectedRange.location < end ? end : nil
        case .left:
            targetLocation = selectedRange.location > start && selectedRange.location <= end ? start : nil
        }

        guard let targetLocation else {
            return false
        }

        textView.setSelectedRange(NSRange(location: targetLocation, length: 0))
        applyDisplayAttributes()
        refreshOverlay()
        return true
    }

    @discardableResult
    private func snapSelectionAroundImageIfNeeded() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location),
              imageReference(in: line.text) != nil,
              selectedRange.location > line.contentRange.location,
              selectedRange.location < NSMaxRange(line.contentRange)
        else {
            return false
        }

        let midpoint = line.contentRange.location + line.contentRange.length / 2
        let targetLocation = selectedRange.location <= midpoint
            ? line.contentRange.location
            : NSMaxRange(line.contentRange)
        textView.setSelectedRange(NSRange(location: targetLocation, length: 0))
        return true
    }

    private func deleteSelectionPreservingLineKinds() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0 else {
            return false
        }

        guard let structuredDelete = structuredLineDeletionRange(for: selectedRange) else {
            return false
        }

        let structuredIntersection = NSIntersectionRange(selectedRange, structuredDelete.range)
        guard structuredIntersection.length == selectedRange.length else {
            return false
        }

        let selectedRangeAfterDelete = NSRange(location: structuredDelete.range.location, length: 0)
        return applyTextStorageEdit(
            range: structuredDelete.range,
            replacement: "",
            selectedRange: selectedRangeAfterDelete
        ) {
            lineKinds.replaceSubrange(structuredDelete.lineRange, with: [])
            if lineKinds.isEmpty {
                lineKinds = [.normal]
            }
        }
    }

    private func structuredLineDeletionRange(
        for selectedRange: NSRange
    ) -> (range: NSRange, lineRange: Range<Int>)? {
        let infos = lineInfos()
        let selectedEnd = NSMaxRange(selectedRange)
        let fullySelectedStructuredLines = infos.filter { line in
            guard kind(at: line.index).isStructured,
                  selectedRange.location <= line.contentRange.location,
                  selectedEnd >= NSMaxRange(line.contentRange),
                  selectionIncludesLineStructure(selectedRange, for: line)
            else {
                return false
            }

            return selectedRange.intersection(line.lineRange) != nil
        }

        guard let firstLine = fullySelectedStructuredLines.first,
              let lastLine = fullySelectedStructuredLines.last
        else {
            return nil
        }

        let deleteStart = firstLine.lineRange.location
        var deleteEnd = NSMaxRange(lastLine.lineRange)
        if deleteEnd == deleteStart,
           firstLine.index > 0,
           infos.indices.contains(firstLine.index - 1) {
            let previousLine = infos[firstLine.index - 1]
            return (
                range: NSRange(location: NSMaxRange(previousLine.contentRange), length: 1),
                lineRange: firstLine.index..<(lastLine.index + 1)
            )
        }

        if deleteEnd >= (textView.string as NSString).length,
           firstLine.index > 0 {
            deleteEnd = NSMaxRange(lastLine.contentRange)
            let previousNewlineLocation = deleteStart - 1
            return (
                range: NSRange(location: previousNewlineLocation, length: max(0, deleteEnd - previousNewlineLocation)),
                lineRange: firstLine.index..<(lastLine.index + 1)
            )
        }

        return (
            range: NSRange(location: deleteStart, length: max(0, deleteEnd - deleteStart)),
            lineRange: firstLine.index..<(lastLine.index + 1)
        )
    }

    private func selectionIncludesLineStructure(
        _ selectedRange: NSRange,
        for line: DisplayLineInfo
    ) -> Bool {
        selectedRange.location < line.contentRange.location
            || NSMaxRange(selectedRange) > NSMaxRange(line.contentRange)
    }

    private func shouldPreserveEmptyTaskWhenDeletingBackward(
        from selectedRange: NSRange,
        in line: DisplayLineInfo
    ) -> Bool {
        guard selectedRange.location > line.contentRange.location,
              selectedRange.location <= NSMaxRange(line.contentRange),
              line.contentRange.length == 1,
              (textView.string as NSString).length == 1,
              kind(at: line.index).isStructured
        else {
            return false
        }

        return true
    }

    private func copySelectionToPasteboard() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0,
              let markdown = markdownText(in: selectedRange)
        else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        return true
    }

    private func cutSelectionToPasteboard() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0 else {
            return cutCurrentLineToPasteboard()
        }

        guard copySelectionToPasteboard() else {
            return false
        }

        return applyTextStorageEdit(
            range: selectedRange,
            replacement: "",
            selectedRange: NSRange(location: selectedRange.location, length: 0)
        ) {
            if isFullTextRange(selectedRange) {
                lineKinds = [.normal]
            }
        }
    }

    private func cutCurrentLineToPasteboard() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location)
        else {
            return false
        }

        let lineKind = kind(at: line.index)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdownLinePrefix(for: lineKind, at: line.index) + line.text, forType: .string)

        let infos = lineInfos()
        let deleteRange: NSRange
        let selectedRangeAfterDelete: NSRange

        if infos.count <= 1 {
            deleteRange = line.contentRange
            selectedRangeAfterDelete = NSRange(location: line.contentRange.location, length: 0)
        } else if line.index < infos.count - 1 {
            deleteRange = line.lineRange
            selectedRangeAfterDelete = NSRange(location: line.lineRange.location, length: 0)
        } else {
            let previousNewlineLocation = max(0, line.lineRange.location - 1)
            deleteRange = NSRange(
                location: previousNewlineLocation,
                length: NSMaxRange(line.contentRange) - previousNewlineLocation
            )
            selectedRangeAfterDelete = NSRange(location: previousNewlineLocation, length: 0)
        }

        return applyTextStorageEdit(
            range: deleteRange,
            replacement: "",
            selectedRange: selectedRangeAfterDelete
        ) {
            if infos.count <= 1 {
                lineKinds = [.normal]
            } else if lineKinds.indices.contains(line.index) {
                lineKinds.remove(at: line.index)
            }
        }
    }

    private func pasteImageFromPasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        guard let image = Self.image(from: pasteboard) else {
            return false
        }

        do {
            let attachmentPath = try AttachmentStore.savePastedImage(image, dateKey: dateKey)
            return insertMarkdownImage(path: attachmentPath)
        } catch {
            NSSound.beep()
            return true
        }
    }

    private static func canPasteImage(from pasteboard: NSPasteboard) -> Bool {
        image(from: pasteboard) != nil
    }

    private static func image(from pasteboard: NSPasteboard) -> NSImage? {
        if let pngData = pasteboard.data(forType: .png),
           let image = NSImage(data: pngData) {
            return image
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData) {
            return image
        }

        if let image = NSImage(pasteboard: pasteboard) {
            return image
        }

        if let fileURL = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )?.first as? URL,
            let image = NSImage(contentsOf: fileURL) {
            return image
        }

        return nil
    }

    private func insertMarkdownImage(path: String) -> Bool {
        let selectedRange = textView.selectedRange()
        let nsText = textView.string as NSString
        let line = "![Screenshot](\(path))"
        let replacement = imageMarkdownReplacement(line, in: nsText, selectedRange: selectedRange)
        let document = Self.displayDocument(from: replacement)
        let replacementLength = (document.text as NSString).length
        let replacesWholeDocument = isFullTextRange(selectedRange)
            || (nsText.length == 0 && selectedRange.length == 0)

        return applyTextStorageEdit(
            range: selectedRange,
            replacement: document.text,
            selectedRange: NSRange(location: selectedRange.location + replacementLength, length: 0)
        ) {
            if replacesWholeDocument {
                lineKinds = document.lineKinds
            } else {
                replaceLineKindsForPaste(in: selectedRange, with: document.lineKinds)
            }
        }
    }

    private func imageMarkdownReplacement(
        _ markdownLine: String,
        in text: NSString,
        selectedRange: NSRange
    ) -> String {
        guard text.length > 0 else {
            return markdownLine
        }

        let selectionEnd = NSMaxRange(selectedRange)
        let needsLeadingNewline = selectedRange.location > 0
            && text.substring(with: NSRange(location: selectedRange.location - 1, length: 1)) != "\n"
        let needsTrailingNewline = selectionEnd < text.length
            && text.substring(with: NSRange(location: selectionEnd, length: 1)) != "\n"

        return "\(needsLeadingNewline ? "\n" : "")\(markdownLine)\(needsTrailingNewline ? "\n" : "")"
    }

    private func pasteMarkdownTasksFromPasteboard() -> Bool {
        guard let pastedText = NSPasteboard.general.string(forType: .string),
              Self.containsTaskMarkdown(in: pastedText)
        else {
            return false
        }

        let selectedRange = textView.selectedRange()
        let document = Self.displayDocument(from: pastedText)
        let replacementLength = (document.text as NSString).length
        let replacesWholeDocument = isFullTextRange(selectedRange)
            || ((textView.string as NSString).length == 0 && selectedRange.length == 0)

        return applyTextStorageEdit(
            range: selectedRange,
            replacement: document.text,
            selectedRange: NSRange(location: selectedRange.location + replacementLength, length: 0)
        ) {
            if replacesWholeDocument {
                lineKinds = document.lineKinds
            } else {
                replaceLineKindsForPaste(in: selectedRange, with: document.lineKinds)
            }
        }
    }

    private func promoteTypedMarkdownTaskIfNeeded() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location)
        else {
            return false
        }

        let task: (indentColumns: Int, isCompleted: Bool, text: String)
        switch kind(at: line.index) {
        case .normal:
            guard Self.hasTypedTaskSeparator(in: line.text),
                  let parsedTask = Self.parseTaskLine(line.text)
            else {
                return false
            }
            task = parsedTask

        case .bullet(let indentColumns):
            guard let taskContent = Self.parseTypedTaskContent(line.text) else {
                return false
            }
            task = (
                indentColumns: indentColumns,
                isCompleted: taskContent.isCompleted,
                text: taskContent.text
            )

        default:
            return false
        }

        return promoteTypedLine(
            line,
            selectedRange: selectedRange,
            replacement: task.text,
            kind: .task(
                indentColumns: task.indentColumns,
                isCompleted: task.isCompleted
            )
        )
    }

    private func promoteTypedMarkdownStructureIfNeeded() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location),
              kind(at: line.index) == .normal
        else {
            return false
        }

        if Self.isHorizontalRuleLine(line.text) {
            return promoteTypedLine(
                line,
                selectedRange: selectedRange,
                replacement: "",
                kind: .horizontalRule
            )
        }

        if let bullet = Self.parseBulletLine(line.text) {
            return promoteTypedLine(
                line,
                selectedRange: selectedRange,
                replacement: bullet.text,
                kind: .bullet(indentColumns: bullet.indentColumns)
            )
        }

        if let numbered = Self.parseNumberedLine(line.text) {
            return promoteTypedLine(
                line,
                selectedRange: selectedRange,
                replacement: numbered.text,
                kind: .numbered(indentColumns: numbered.indentColumns, number: numbered.number)
            )
        }

        return false
    }

    private func promoteTypedLine(
        _ line: DisplayLineInfo,
        selectedRange: NSRange,
        replacement: String,
        kind: LineKind
    ) -> Bool {
        let oldLineLength = (line.text as NSString).length
        let newLineLength = (replacement as NSString).length
        let removedPrefixLength = oldLineLength - newLineLength
        let selectionOffset = selectedRange.location - line.contentRange.location
        let newSelectionOffset = max(0, min(newLineLength, selectionOffset - removedPrefixLength))

        let shouldPreserveEmptyStructuredLine = replacement.isEmpty
        if shouldPreserveEmptyStructuredLine {
            preservesEmptyStructuredLine = true
        }
        defer {
            if shouldPreserveEmptyStructuredLine {
                preservesEmptyStructuredLine = false
            }
        }

        isApplyingProgrammaticChange = true
        textView.textStorage?.replaceCharacters(in: line.contentRange, with: replacement)
        lineKinds[line.index] = kind
        reconcileLineKinds()
        textView.setSelectedRange(
            NSRange(location: line.contentRange.location + newSelectionOffset, length: 0)
        )
        textView.didChangeText()
        isApplyingProgrammaticChange = false

        notifyTextChangedAndRefresh(scrollSelection: true)
        return true
    }

    private func markdownTableRenderBlocks() -> [MarkdownTableRenderBlock] {
        let lines = displayLines()
        var blocks: [MarkdownTableRenderBlock] = []
        var index = 0

        while index < lines.count {
            guard let table = Self.parseMarkdownTable(
                startingAt: index,
                lines: lines,
                requiresBodyRow: true,
                requiresClosedRows: true
            ) else {
                index += 1
                continue
            }

            let rowLineIndices = [index] + Array((index + 2)..<table.nextIndex)
            blocks.append(
                MarkdownTableRenderBlock(
                    rawLineRange: index..<table.nextIndex,
                    rowLineIndices: rowLineIndices,
                    rows: table.rows,
                    columnCount: table.columnCount
                )
            )
            index = table.nextIndex
        }

        return blocks
    }

    private func markdownCodeRenderBlocks(lineInfos: [DisplayLineInfo]) -> [MarkdownCodeRenderBlock] {
        var blocks: [MarkdownCodeRenderBlock] = []
        var index = 0

        while index < lineInfos.count {
            guard case .codeBlock(let language) = kind(at: lineInfos[index].index) else {
                index += 1
                continue
            }

            let start = index
            index += 1
            while index < lineInfos.count {
                guard case .codeBlock(let nextLanguage) = kind(at: lineInfos[index].index),
                      nextLanguage == language
                else {
                    break
                }
                index += 1
            }

            blocks.append(
                MarkdownCodeRenderBlock(
                    lineRange: start..<index,
                    language: language
                )
            )
        }

        return blocks
    }

    private func isTableBlockActive(_ block: MarkdownTableRenderBlock, selectedRange: NSRange, lineInfos: [DisplayLineInfo]) -> Bool {
        guard lineInfos.indices.contains(block.rawLineRange.lowerBound),
              lineInfos.indices.contains(block.rawLineRange.upperBound - 1)
        else {
            return false
        }

        let first = lineInfos[block.rawLineRange.lowerBound]
        let last = lineInfos[block.rawLineRange.upperBound - 1]
        let tableRange = NSRange(
            location: first.lineRange.location,
            length: NSMaxRange(last.lineRange) - first.lineRange.location
        )

        if selectedRange.length > 0 {
            return selectedRange.intersection(tableRange) != nil
        }

        return selectedRange.location >= tableRange.location
            && selectedRange.location <= NSMaxRange(tableRange)
    }

    private func inactiveMarkdownTableRows(
        selectedRange: NSRange,
        lineInfos: [DisplayLineInfo]
    ) -> (
        rows: [Int: RenderedMarkdownTableRow],
        syntaxLineIndices: Set<Int>,
        collapsedLineIndices: Set<Int>
    ) {
        var rows: [Int: RenderedMarkdownTableRow] = [:]
        var syntaxLineIndices = Set<Int>()
        var collapsedLineIndices = Set<Int>()
        let blocks = markdownTableRenderBlocks()

        for block in blocks where !isTableBlockActive(block, selectedRange: selectedRange, lineInfos: lineInfos) {
            syntaxLineIndices.formUnion(block.rawLineRange)
            collapsedLineIndices.insert(block.rawLineRange.lowerBound + 1)
            for (rowOffset, lineIndex) in block.rowLineIndices.enumerated()
                where block.rows.indices.contains(rowOffset) {
                rows[lineIndex] = RenderedMarkdownTableRow(
                    isHeader: rowOffset == 0,
                    cells: block.rows[rowOffset],
                    columnCount: block.columnCount,
                    rowIndex: rowOffset,
                    rowCount: block.rows.count
                )
            }
        }

        return (rows, syntaxLineIndices, collapsedLineIndices)
    }

    private func applyTextStorageEdit(
        range: NSRange,
        replacement: String,
        selectedRange: NSRange,
        updateLineKinds: () -> Void
    ) -> Bool {
        let undoSnapshot = editorSnapshot()
        isApplyingProgrammaticChange = true
        guard textView.shouldChangeText(in: range, replacementString: replacement) else {
            isApplyingProgrammaticChange = false
            return true
        }

        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        updateLineKinds()
        reconcileLineKinds()
        textView.setSelectedRange(selectedRange)
        textView.didChangeText()
        isApplyingProgrammaticChange = false
        notifyTextChangedAndRefresh(scrollSelection: true)
        registerUndoSnapshotIfChanged(from: undoSnapshot)
        return true
    }

    private func handleCheckboxMouseDown(_ event: NSEvent) -> Bool {
        let point = overlayView.convert(event.locationInWindow, from: nil)
        guard let lineIndex = overlayView.lineIndex(at: point) else {
            return false
        }

        guard case .task(let indentColumns, let isCompleted) = kind(at: lineIndex) else {
            return false
        }

        let undoSnapshot = editorSnapshot()
        lineKinds[lineIndex] = .task(indentColumns: indentColumns, isCompleted: !isCompleted)
        notifyTextChangedAndRefresh(scrollSelection: false)
        registerUndoSnapshotIfChanged(from: undoSnapshot)
        return true
    }

    private func selectImage(_ item: MarkdownImageOverlayItem, at point: NSPoint) {
        let infos = lineInfos()
        guard infos.indices.contains(item.lineIndex) else {
            return
        }

        let line = infos[item.lineIndex]
        let targetLocation = point.x <= item.frame.midX
            ? line.contentRange.location
            : NSMaxRange(line.contentRange)
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: targetLocation, length: 0))
        refreshEditor()
    }

    private func resizeImage(_ item: MarkdownImageOverlayItem, from point: NSPoint) -> Bool {
        let startPoint = point
        let startWidth = item.frame.width
        let minWidth: CGFloat = 80
        let maxWidth = max(minWidth, textView.bounds.width - textView.textContainerInset.width * 2)
        var currentWidth = startWidth

        resizingImagePreview = (lineIndex: item.lineIndex, width: currentWidth)
        refreshEditor()

        while let nextEvent = window?.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            let currentPoint = imageOverlayView.convert(nextEvent.locationInWindow, from: nil)
            currentWidth = max(minWidth, min(maxWidth, startWidth + currentPoint.x - startPoint.x))

            if nextEvent.type == .leftMouseDragged {
                resizingImagePreview = (lineIndex: item.lineIndex, width: currentWidth)
                refreshEditor()
                continue
            }

            resizingImagePreview = nil
            updateImageWidth(currentWidth, lineIndex: item.lineIndex)
            return true
        }

        resizingImagePreview = nil
        refreshEditor()
        return true
    }

    private func updateImageWidth(_ width: CGFloat, lineIndex: Int) {
        let infos = lineInfos()
        guard infos.indices.contains(lineIndex),
              let reference = imageReference(in: infos[lineIndex].text)
        else {
            refreshEditor()
            return
        }

        let line = infos[lineIndex]
        let replacement = markdownImageLine(for: reference, width: width)
        let selectedRange = textView.selectedRange()
        let selectedLocation: Int
        if selectedRange.location <= line.contentRange.location {
            selectedLocation = line.contentRange.location
        } else {
            selectedLocation = line.contentRange.location + (replacement as NSString).length
        }

        _ = applyTextStorageEdit(
            range: line.contentRange,
            replacement: replacement,
            selectedRange: NSRange(location: selectedLocation, length: 0)
        ) {
            lineKinds = normalizedLineKinds(lineKinds, for: textView.string)
        }
    }

    private func editorSnapshot() -> EditorSnapshot {
        EditorSnapshot(
            text: textView.string,
            lineKinds: lineKinds,
            selectedRange: textView.selectedRange()
        )
    }

    private func clearEditorUndoHistory() {
        snapshotUndoManager?.removeAllActions(withTarget: self)
    }

    private var snapshotUndoManager: UndoManager? {
        textView.undoManager ?? window?.undoManager
    }

    private func registerUndoSnapshotIfChanged(from undoSnapshot: EditorSnapshot?) {
        guard let undoSnapshot,
              !isRestoringUndoSnapshot,
              !undoSnapshot.isSame(as: editorSnapshot())
        else {
            return
        }

        registerUndoRestore(to: undoSnapshot)
    }

    private func registerUndoRestore(to snapshot: EditorSnapshot) {
        snapshotUndoManager?.registerUndo(withTarget: self) { target in
            target.restoreUndoSnapshot(snapshot)
        }
    }

    private func restoreUndoSnapshot(_ snapshot: EditorSnapshot) {
        let redoSnapshot = editorSnapshot()
        isRestoringUndoSnapshot = true
        applyEditorSnapshot(snapshot)
        isRestoringUndoSnapshot = false
        registerUndoRestore(to: redoSnapshot)
    }

    private func applyEditorSnapshot(_ snapshot: EditorSnapshot) {
        let shouldPreserveEmptyStructuredLine = snapshot.text.isEmpty
            && snapshot.lineKinds.first?.isStructured == true

        if shouldPreserveEmptyStructuredLine {
            preservesEmptyStructuredLine = true
        }
        defer {
            if shouldPreserveEmptyStructuredLine {
                preservesEmptyStructuredLine = false
            }
        }

        isApplyingProgrammaticChange = true
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: snapshot.text, attributes: baseAttributes())
        )
        lineKinds = normalizedLineKinds(snapshot.lineKinds, for: snapshot.text)
        let textLength = (snapshot.text as NSString).length
        let selectedLocation = max(0, min(snapshot.selectedRange.location, textLength))
        textView.setSelectedRange(
            NSRange(
                location: selectedLocation,
                length: min(snapshot.selectedRange.length, max(0, textLength - selectedLocation))
            )
        )
        isApplyingProgrammaticChange = false
        notifyTextChangedAndRefresh(scrollSelection: true)
    }

    private func notifyTextChangedAndRefresh(scrollSelection: Bool) {
        reconcileLineKinds()
        updateTypingAttributesForCurrentSelection()
        applyDisplayAttributes()

        if scrollSelection {
            scrollSelectionToVisible()
        }

        refreshOverlay()
        onTextChange?(markdownText())
    }

    private func refreshEditor() {
        reconcileLineKinds()
        updateTypingAttributesForCurrentSelection()
        applyDisplayAttributes()
        refreshOverlay()
    }

    private func isFullTextRange(_ range: NSRange) -> Bool {
        range.location == 0 && range.length == (textView.string as NSString).length
    }

    private func markdownText(in selectedRange: NSRange) -> String? {
        guard selectedRange.length > 0 else {
            return nil
        }

        if isFullTextRange(selectedRange) {
            return markdownText()
        }

        var markdownLines: [String] = []
        let nsText = textView.string as NSString

        for line in lineInfos() {
            guard let intersection = line.contentRange.intersection(selectedRange) else {
                if selectedRange.contains(line.lineRange.location),
                   line.contentRange.length == 0 {
                    markdownLines.append(markdownLinePrefix(for: kind(at: line.index), at: line.index))
                }
                continue
            }

            let selectedText = nsText.substring(with: intersection)
            let includesLineStart = selectedRange.location <= line.contentRange.location
            let prefix = includesLineStart ? markdownLinePrefix(for: kind(at: line.index), at: line.index) : ""
            markdownLines.append(prefix + selectedText)
        }

        guard !markdownLines.isEmpty else {
            return nil
        }

        return markdownLines.joined(separator: "\n")
    }

    private func markdownLinePrefix(for kind: LineKind, at lineIndex: Int) -> String {
        switch kind {
        case .normal:
            return ""
        case .task(let indentColumns, let isCompleted):
            return String(repeating: " ", count: indentColumns) + (isCompleted ? "- [x] " : "- [ ] ")
        case .bullet(let indentColumns):
            return String(repeating: " ", count: indentColumns) + "- "
        case .numbered(let indentColumns, let number):
            return String(repeating: " ", count: indentColumns) + "\(number). "
        case .quote:
            return "> "
        case .codeBlock:
            return ""
        case .horizontalRule:
            return "---"
        case .tableRow:
            return ""
        case .continuation(let indentColumns):
            return continuationMarkdownPrefix(forLineAt: lineIndex, indentColumns: indentColumns)
        }
    }

    private func continuationMarkdownPrefix(forLineAt lineIndex: Int, indentColumns: Int) -> String {
        switch previousStructuredKind(before: lineIndex) {
        case .task(let parentIndentColumns, _):
            return String(repeating: " ", count: parentIndentColumns + 6)
        case .bullet(let parentIndentColumns):
            return String(repeating: " ", count: parentIndentColumns + 2)
        case .numbered(let parentIndentColumns, let number):
            return String(repeating: " ", count: parentIndentColumns + "\(number). ".count)
        case .quote:
            return "> "
        case .codeBlock:
            return ""
        case .normal, .horizontalRule, .tableRow, .continuation:
            return String(repeating: " ", count: indentColumns)
        }
    }

    private func previousStructuredKind(before lineIndex: Int) -> LineKind {
        guard lineIndex > 0 else {
            return .normal
        }

        for index in stride(from: lineIndex - 1, through: 0, by: -1) {
            let previousKind = kind(at: index)
            if case .continuation = previousKind {
                continue
            }

            return previousKind
        }

        return .normal
    }

    private func replaceLineKindsForPaste(in selectedRange: NSRange, with replacementKinds: [LineKind]) {
        let textLength = (textView.string as NSString).length
        lineKinds = normalizedLineKinds(lineKinds, for: textView.string)

        guard !replacementKinds.isEmpty else {
            return
        }

        if textLength == 0 {
            lineKinds = replacementKinds
            return
        }

        let startLine = lineInfo(at: selectedRange.location)?.index ?? 0
        let removedLineCount: Int
        if selectedRange.length == 0 {
            removedLineCount = 0
        } else {
            let endLocation = max(selectedRange.location, NSMaxRange(selectedRange) - 1)
            let endLine = lineInfo(at: endLocation)?.index ?? startLine
            removedLineCount = max(1, endLine - startLine + 1)
        }

        let safeStart = min(startLine, lineKinds.count)
        let safeEnd = min(lineKinds.count, safeStart + removedLineCount)
        lineKinds.replaceSubrange(safeStart..<safeEnd, with: replacementKinds)
    }

    private func refreshOverlay() {
        overlayView.setItems([])
        imageOverlayView.setItems([], caret: nil)
        updateInsertionPointColor(showCustomImageCaret: false)

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else {
            imageInteractionView.setItems([])
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let visibleBounds = scrollView.contentView.bounds
        let textContainerOrigin = textView.textContainerOrigin
        var checkboxItems: [TodoCheckboxOverlayItem] = []
        var markerItems: [LineMarkerOverlayItem] = []
        var imageItems: [MarkdownImageOverlayItem] = []
        var imageCaret: MarkdownImageCaretItem?
        let selectedRange = textView.selectedRange()
        let displayLineInfos = lineInfos()
        let renderedTables = inactiveMarkdownTableRows(
            selectedRange: selectedRange,
            lineInfos: displayLineInfos
        )
        for block in markdownCodeRenderBlocks(lineInfos: displayLineInfos) {
            guard displayLineInfos.indices.contains(block.lineRange.lowerBound),
                  displayLineInfos.indices.contains(block.lineRange.upperBound - 1),
                  let firstRect = lineFragmentRect(for: displayLineInfos[block.lineRange.lowerBound], layoutManager: layoutManager),
                  let lastRect = lineFragmentRect(for: displayLineInfos[block.lineRange.upperBound - 1], layoutManager: layoutManager)
            else {
                continue
            }

            let blockY = textContainerOrigin.y + firstRect.minY - visibleBounds.origin.y - 5
            let blockBottom = textContainerOrigin.y + lastRect.maxY - visibleBounds.origin.y + 5
            guard blockBottom > -24, blockY < bounds.height + 24 else {
                continue
            }

            markerItems.append(
                LineMarkerOverlayItem(
                    kind: .codeBlock(language: block.language),
                    frame: NSRect(
                        x: max(0, textContainerOrigin.x - visibleBounds.origin.x + 1),
                        y: blockY,
                        width: max(80, textView.bounds.width - textView.textContainerInset.width * 2 - 2),
                        height: max(lineHeight() + 10, blockBottom - blockY)
                    )
                )
            )
        }

        for line in displayLineInfos {
            guard let lineRect = lineFragmentRect(for: line, layoutManager: layoutManager) else {
                continue
            }

            let y = textContainerOrigin.y + lineRect.minY - visibleBounds.origin.y + 1

            if let reference = imageReference(in: line.text),
               let image = image(for: reference) {
                let previewSize = imagePreviewSize(for: image, reference: reference, lineIndex: line.index)
                let imageY = textContainerOrigin.y + lineRect.minY - visibleBounds.origin.y + 6
                let imageFrame = NSRect(
                    x: max(0, textContainerOrigin.x - visibleBounds.origin.x),
                    y: imageY,
                    width: previewSize.width,
                    height: previewSize.height
                )
                if imageY > -previewSize.height - 24, imageY < bounds.height + 24 {
                    let isSelected = selectedRange.length == 0
                        && selectedRange.location >= line.contentRange.location
                        && selectedRange.location <= NSMaxRange(line.contentRange)
                    imageItems.append(
                        MarkdownImageOverlayItem(
                            attachmentPath: reference.path,
                            image: image,
                            altText: reference.altText,
                            frame: imageFrame,
                            lineIndex: line.index,
                            isSelected: isSelected
                        )
                    )
                }

                if selectedRange.length == 0,
                   imageCaret == nil,
                   selectedRange.location == line.contentRange.location
                    || selectedRange.location == NSMaxRange(line.contentRange) {
                    let edge: ImageCaretEdge = selectedRange.location == line.contentRange.location
                        ? .leading
                        : .trailing
                    imageCaret = imageCaretItem(edge: edge, imageFrame: imageFrame)
                }
            }

            let lineKind = kind(at: line.index)
            guard y > -24, y < bounds.height + 24 else {
                continue
            }

            switch lineKind {
            case .task(let indentColumns, let isCompleted):
                let checkboxLeftX = taskCheckboxIndent(for: indentColumns)
                let x = max(0, textContainerOrigin.x + checkboxLeftX - visibleBounds.origin.x - TodoLayout.checkboxDrawInset)
                checkboxItems.append(
                    TodoCheckboxOverlayItem(
                        frame: NSRect(
                            x: x,
                            y: y - 3,
                            width: TodoLayout.checkboxFrameWidth,
                            height: TodoLayout.checkboxFrameHeight
                        ),
                        isChecked: isCompleted,
                        lineIndex: line.index
                    )
                )

            case .bullet(let indentColumns):
                markerItems.append(
                    LineMarkerOverlayItem(
                        kind: .bullet(level: listLevel(for: indentColumns)),
                        frame: markerFrame(for: indentColumns, textContainerOrigin: textContainerOrigin, visibleBounds: visibleBounds, y: y)
                    )
                )

            case .numbered(let indentColumns, let number):
                markerItems.append(
                    LineMarkerOverlayItem(
                        kind: .number(number, level: listLevel(for: indentColumns)),
                        frame: markerFrame(for: indentColumns, textContainerOrigin: textContainerOrigin, visibleBounds: visibleBounds, y: y)
                    )
                )

            case .quote:
                markerItems.append(
                    LineMarkerOverlayItem(
                        kind: .quote,
                        frame: NSRect(x: max(0, textContainerOrigin.x - visibleBounds.origin.x), y: y - 1, width: 14, height: lineHeight())
                    )
                )

            case .codeBlock:
                break

            case .horizontalRule:
                markerItems.append(
                    LineMarkerOverlayItem(
                        kind: .horizontalRule,
                        frame: NSRect(
                            x: max(0, textContainerOrigin.x - visibleBounds.origin.x),
                            y: y - 1,
                            width: max(40, textView.bounds.width - textView.textContainerInset.width * 2),
                            height: lineHeight()
                        )
                    )
                )

            case .tableRow(let isHeader, let columnCount):
                markerItems.append(
                    LineMarkerOverlayItem(
                        kind: .tableRow(
                            isHeader: isHeader,
                            cells: Array(repeating: "", count: columnCount),
                            rowIndex: 0
                        ),
                        frame: NSRect(
                            x: max(0, textContainerOrigin.x - visibleBounds.origin.x),
                            y: y - 1,
                            width: max(80, textView.bounds.width - textView.textContainerInset.width * 2),
                            height: lineHeight() + 1
                        )
                    )
                )

            case .normal, .continuation:
                break
            }

            if let renderedTableRow = renderedTables.rows[line.index] {
                markerItems.append(
                    LineMarkerOverlayItem(
                        kind: .tableRow(
                            isHeader: renderedTableRow.isHeader,
                            cells: renderedTableRow.cells,
                            rowIndex: renderedTableRow.rowIndex
                        ),
                        frame: NSRect(
                            x: max(0, textContainerOrigin.x - visibleBounds.origin.x),
                            y: y - 1,
                            width: max(80, textView.bounds.width - textView.textContainerInset.width * 2),
                            height: lineHeight() + 1
                        )
                    )
                )
            }
        }

        imageInteractionView.setItems(imageItems)
        imageOverlayView.setItems(imageItems, caret: imageCaret)
        updateInsertionPointColor(showCustomImageCaret: imageCaret != nil)
        textView.imageCursorRects = imageInteractionView.imageFrameRects().map {
            textView.convert($0, from: imageInteractionView)
        }
        textView.imageResizeCursorRects = imageInteractionView.resizeHandleRects().map {
            textView.convert($0, from: imageInteractionView)
        }
        overlayView.setItems(checkboxItems, markers: markerItems)
        textView.checkboxCursorRects = overlayView.clickTargetRects().map {
            textView.convert($0, from: overlayView)
        }
    }

    private func imageCaretItem(edge: ImageCaretEdge, imageFrame: NSRect) -> MarkdownImageCaretItem {
        let caretHeight = lineHeight()
        let x: CGFloat
        switch edge {
        case .leading:
            x = imageFrame.minX - 4
        case .trailing:
            x = imageFrame.maxX + 4
        }

        return MarkdownImageCaretItem(
            frame: NSRect(
                x: x,
                y: imageFrame.maxY - caretHeight,
                width: 2,
                height: caretHeight
            )
        )
    }

    private func markerFrame(
        for indentColumns: Int,
        textContainerOrigin: NSPoint,
        visibleBounds: NSRect,
        y: CGFloat
    ) -> NSRect {
        let leftX = taskCheckboxIndent(for: indentColumns)
        let x = max(0, textContainerOrigin.x + leftX - visibleBounds.origin.x - TodoLayout.checkboxDrawInset)
        return NSRect(
            x: x,
            y: y - 1,
            width: TodoLayout.checkboxFrameWidth,
            height: lineHeight()
        )
    }

    private func applyDisplayAttributes() {
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        guard let textStorage = textView.textStorage else {
            return
        }
        guard !isComposingMarkedText else {
            return
        }

        let selectedRange = textView.selectedRange()
        let completedColor = palette.completedTextNS
        let codeBackground = palette.codeBackgroundNS
        let strikethroughColor = palette.strikethroughNS

        textStorage.beginEditing()
        if fullRange.length > 0 {
            textStorage.setAttributes(baseAttributes(), range: fullRange)
        }

        if shouldParseInlineMarkdown {
            let spans = MarkdownInlineParser.spans(in: textView.string)
            for span in spans {
                if !isActiveMarkdownSpan(span, selectedRange: selectedRange) {
                    for syntaxRange in span.syntaxRanges {
                        textStorage.addAttributes(
                            [
                                .foregroundColor: NSColor.clear,
                                .font: hiddenSyntaxFont()
                            ],
                            range: syntaxRange
                        )
                    }
                }

                switch span.style {
                case .heading(let level):
                    textStorage.addAttributes(
                        [
                            .font: NSFont.systemFont(
                                ofSize: headingSize(for: level),
                                weight: .bold
                            )
                        ],
                        range: span.contentRange
                    )
                case .bold:
                    textStorage.addAttributes(
                        [.font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)],
                        range: span.contentRange
                    )
                case .italic:
                    textStorage.addAttributes(
                        [.font: italicFont()],
                        range: span.contentRange
                    )
                case .code:
                    textStorage.addAttributes(
                        [
                            .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular),
                            .backgroundColor: codeBackground
                        ],
                        range: span.contentRange
                    )
                case .strikethrough:
                    textStorage.addAttributes(
                        [
                            .foregroundColor: strikethroughColor,
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .strikethroughColor: strikethroughColor
                        ],
                        range: span.contentRange
                    )
                }
            }
        }

        let displayLineInfos = lineInfos()
        let renderedTables = inactiveMarkdownTableRows(
            selectedRange: selectedRange,
            lineInfos: displayLineInfos
        )

        for line in displayLineInfos {
            let lineKind = kind(at: line.index)
            let paragraphRange = paragraphAttributeRange(for: line)
            textStorage.addAttribute(
                .paragraphStyle,
                value: renderedTables.collapsedLineIndices.contains(line.index)
                    ? collapsedTableSyntaxParagraphStyle()
                    : paragraphStyle(for: line),
                range: paragraphRange
            )

            if imageReference(in: line.text) != nil,
               line.contentRange.length > 0 {
                textStorage.addAttributes(
                    [
                        .foregroundColor: NSColor.clear,
                        .font: hiddenSyntaxFont()
                    ],
                    range: line.contentRange
                )
            }

            if case .task(_, let isCompleted) = lineKind,
               isCompleted,
               line.contentRange.length > 0 {
                textStorage.addAttributes(
                    [
                        .foregroundColor: completedColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: completedColor
                    ],
                    range: line.contentRange
                )
            }

            if case .quote = lineKind,
               line.contentRange.length > 0 {
                textStorage.addAttributes(
                    [
                        .foregroundColor: palette.textNS.withAlphaComponent(0.78),
                        .font: italicFont()
                    ],
                    range: line.contentRange
                )
            }

            if case .codeBlock(let language) = lineKind,
               line.contentRange.length > 0 {
                textStorage.addAttributes(
                    [
                        .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular),
                        .foregroundColor: palette.textNS
                    ],
                    range: line.contentRange
                )
                applyCodeHighlighting(language: language, in: line.contentRange, textStorage: textStorage)
            }

            if case .tableRow(let isHeader, _) = lineKind,
               line.contentRange.length > 0 {
                textStorage.addAttributes(
                    [
                        .font: isHeader
                            ? NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .semibold)
                            : NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular),
                        .backgroundColor: palette.codeBackgroundNS.withAlphaComponent(isHeader ? 0.58 : 0.32)
                    ],
                    range: line.contentRange
                )
            }

            if renderedTables.syntaxLineIndices.contains(line.index),
               line.contentRange.length > 0 {
                textStorage.addAttributes(
                    [
                        .foregroundColor: NSColor.clear,
                        .font: hiddenSyntaxFont()
                    ],
                    range: line.contentRange
                )
            }

            if case .horizontalRule = lineKind,
               line.contentRange.length > 0 {
                textStorage.addAttributes(
                    [
                        .foregroundColor: NSColor.clear,
                        .font: hiddenSyntaxFont()
                    ],
                    range: line.contentRange
                )
            }
        }

        textStorage.endEditing()
        textView.setSelectedRange(selectedRange)
        updateTypingAttributesForCurrentSelection()
        textView.setNeedsDisplay(textView.visibleRect)
    }

    private var isComposingMarkedText: Bool {
        textView.hasMarkedText()
    }

    private func isActiveMarkdownSpan(
        _ span: MarkdownInlineSpan,
        selectedRange: NSRange
    ) -> Bool {
        if selectedRange.length > 0 {
            return selectedRange.intersection(span.fullRange) != nil
        }

        let location = selectedRange.location
        return location > span.fullRange.location
            && location < NSMaxRange(span.fullRange)
    }

    private var shouldParseInlineMarkdown: Bool {
        textView.string.rangeOfCharacter(from: CharacterSet(charactersIn: "#*`~")) != nil
    }

    private func applyCodeHighlighting(
        language: String?,
        in range: NSRange,
        textStorage: NSTextStorage
    ) {
        guard let language = language?.lowercased(),
              let keywords = codeKeywords(for: language),
              range.length > 0
        else {
            return
        }

        let lineText = (textView.string as NSString).substring(with: range)
        let escaped = keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = #"(?<![A-Za-z0-9_])("# + escaped + #")(?![A-Za-z0-9_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }

        let highlightColor = palette.accentNS
        let nsLine = lineText as NSString
        let lineRange = NSRange(location: 0, length: nsLine.length)
        for match in regex.matches(in: lineText, range: lineRange) {
            textStorage.addAttributes(
                [
                    .foregroundColor: highlightColor,
                    .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .semibold)
                ],
                range: NSRange(location: range.location + match.range.location, length: match.range.length)
            )
        }
    }

    private func codeKeywords(for language: String) -> [String]? {
        switch language {
        case "swift":
            return ["let", "var", "func", "struct", "class", "enum", "protocol", "extension", "if", "else", "guard", "return", "switch", "case", "for", "while", "import", "private", "public", "static", "final"]
        case "python", "py":
            return ["def", "class", "if", "elif", "else", "return", "for", "while", "in", "import", "from", "as", "try", "except", "finally", "with", "lambda", "True", "False", "None"]
        case "javascript", "js", "typescript", "ts":
            return ["const", "let", "var", "function", "return", "if", "else", "for", "while", "class", "import", "export", "from", "async", "await", "new", "try", "catch", "finally"]
        default:
            return nil
        }
    }

    private func paragraphAttributeRange(for line: DisplayLineInfo) -> NSRange {
        let fullLength = (textView.string as NSString).length
        if line.lineRange.length > 0 {
            return line.lineRange
        }

        if fullLength == 0 {
            return NSRange(location: 0, length: 0)
        }

        return NSRange(location: max(0, min(line.contentRange.location, fullLength - 1)), length: 1)
    }

    private func updateTypingAttributesForCurrentSelection() {
        guard let line = lineInfo(at: textView.selectedRange().location) else {
            textView.typingAttributes = baseAttributes()
            return
        }

        var attributes = baseAttributes()
        attributes[.paragraphStyle] = paragraphStyle(for: line)
        textView.typingAttributes = attributes
    }

    private func paragraphStyle(for line: DisplayLineInfo) -> NSParagraphStyle {
        let kind = kind(at: line.index)
        let style = NSMutableParagraphStyle()
        let textIndent: CGFloat
        switch kind {
        case .normal, .horizontalRule:
            textIndent = 0
        case .task, .bullet, .numbered, .quote, .codeBlock, .tableRow, .continuation:
            textIndent = lineTextIndent(for: kind)
        }

        style.firstLineHeadIndent = textIndent
        style.headIndent = textIndent
        if case .tableRow(_, let columnCount) = kind {
            applyTableTabStops(to: style, columnCount: columnCount)
        }
        let minimumLineHeight = kind.isCodeBlock ? lineHeight() + 2 : lineHeight()
        style.minimumLineHeight = max(minimumLineHeight, imagePreviewLineHeight(for: line))
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private func paragraphStyle(for kind: LineKind) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let textIndent: CGFloat
        switch kind {
        case .normal, .horizontalRule:
            textIndent = 0
        case .task, .bullet, .numbered, .quote, .codeBlock, .tableRow, .continuation:
            textIndent = lineTextIndent(for: kind)
        }

        style.firstLineHeadIndent = textIndent
        style.headIndent = textIndent
        if case .tableRow(_, let columnCount) = kind {
            applyTableTabStops(to: style, columnCount: columnCount)
        }
        style.minimumLineHeight = kind.isCodeBlock ? lineHeight() + 2 : lineHeight()
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private func collapsedTableSyntaxParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 0
        style.headIndent = 0
        style.minimumLineHeight = 0.01
        style.maximumLineHeight = 0.01
        style.lineSpacing = 0
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
        return style
    }

    private func applyTableTabStops(to style: NSMutableParagraphStyle, columnCount: Int) {
        let availableWidth = max(120, textView.bounds.width - textView.textContainerInset.width * 2)
        let columnWidth = availableWidth / CGFloat(max(1, columnCount))
        style.tabStops = (1..<max(1, columnCount)).map { column in
            NSTextTab(textAlignment: .left, location: columnWidth * CGFloat(column), options: [:])
        }
        style.defaultTabInterval = columnWidth
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: palette.textNS,
            .paragraphStyle: baseParagraphStyle()
        ]
    }

    private func baseParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 0
        style.headIndent = 0
        style.minimumLineHeight = lineHeight()
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private func hiddenSyntaxFont() -> NSFont {
        NSFont.systemFont(ofSize: 0.01)
    }

    private func italicFont() -> NSFont {
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        guard italicFont.fontDescriptor.symbolicTraits.contains(.italic) else {
            return NSFont.systemFont(ofSize: baseFont.pointSize)
        }

        return italicFont
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1:
            return 21
        case 2:
            return 18
        default:
            return 16
        }
    }

    private func scrollSelectionToVisible() {
        guard scrollSelectedLineToVisible() else {
            textView.scrollRangeToVisible(scrollRangeForSelection())
            refreshOverlay()
            return
        }

        refreshOverlay()
    }

    @discardableResult
    private func scrollSelectedLineToVisible() -> Bool {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let line = lineInfo(at: textView.selectedRange().location)
        else {
            return false
        }

        layoutManager.ensureLayout(for: textContainer)

        guard var lineRect = lineFragmentRect(for: line, layoutManager: layoutManager) else {
            return false
        }

        lineRect.origin.x = 0
        lineRect.origin.y += textView.textContainerOrigin.y
        lineRect.size.width = max(textView.bounds.width, scrollView.contentView.bounds.width)
        lineRect.size.height = max(lineRect.height, lineHeight())

        let bottomBreathingRoom = lineHeight() * 0.65
        let visibleRect = lineRect.insetBy(dx: 0, dy: -bottomBreathingRoom)
        textView.scrollToVisible(visibleRect)
        return true
    }

    private func scrollRangeForSelection() -> NSRange {
        let selectedRange = textView.selectedRange()
        let textLength = (textView.string as NSString).length

        guard selectedRange.length == 0, textLength > 0 else {
            return selectedRange
        }

        return NSRange(location: max(0, min(selectedRange.location, textLength) - 1), length: 1)
    }

    private func lineHeight() -> CGFloat {
        ceil(baseFont.ascender - baseFont.descender + baseFont.leading)
    }

    private func taskCheckboxIndent(for indentColumns: Int) -> CGFloat {
        CGFloat(indentColumns) / TodoLayout.markdownIndentColumnsPerLevel * TodoLayout.levelIndent
    }

    private func taskTextIndent(for indentColumns: Int) -> CGFloat {
        taskCheckboxIndent(for: indentColumns) + TodoLayout.taskTextOffset
    }

    private func listLevel(for indentColumns: Int) -> Int {
        max(0, indentColumns / Int(TodoLayout.markdownIndentColumnsPerLevel))
    }

    private func lineTextIndent(for kind: LineKind) -> CGFloat {
        switch kind {
        case .normal, .horizontalRule:
            return 0
        case .task(let indentColumns, _):
            return taskTextIndent(for: indentColumns)
        case .bullet(let indentColumns),
             .numbered(let indentColumns, _),
             .continuation(let indentColumns):
            return taskTextIndent(for: indentColumns)
        case .quote:
            return 18
        case .codeBlock:
            return 18
        case .tableRow:
            return 0
        }
    }

    private func imageReference(in lineText: String) -> MarkdownImageReference? {
        let nsText = lineText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = Self.markdownImageLineRegex.firstMatch(
            in: lineText,
            options: [],
            range: fullRange
        ),
            match.numberOfRanges >= 3
        else {
            return nil
        }

        let width: CGFloat?
        if match.numberOfRanges >= 4,
           match.range(at: 3).location != NSNotFound {
            width = CGFloat((nsText.substring(with: match.range(at: 3)) as NSString).doubleValue)
        } else {
            width = nil
        }

        return MarkdownImageReference(
            altText: nsText.substring(with: match.range(at: 1)),
            path: nsText.substring(with: match.range(at: 2)),
            width: width
        )
    }

    private func markdownImageLine(for reference: MarkdownImageReference, width: CGFloat?) -> String {
        let widthSuffix: String
        if let width {
            widthSuffix = "{width=\(max(1, Int(round(width))))}"
        } else {
            widthSuffix = ""
        }

        return "![\(reference.altText)](\(reference.path))\(widthSuffix)"
    }

    private func image(for reference: MarkdownImageReference) -> NSImage? {
        if let cachedImage = imageCache[reference.path] {
            return cachedImage
        }

        guard let url = AttachmentStore.imageURL(for: reference.path),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        imageCache[reference.path] = image
        return image
    }

    private func imagePreviewSize(
        for image: NSImage,
        reference: MarkdownImageReference,
        lineIndex: Int
    ) -> NSSize {
        let maxWidth = max(120, textView.bounds.width - textView.textContainerInset.width * 2)
        let maxHeight: CGFloat = 360
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: maxWidth, height: 180)
        }

        let explicitWidth = resizingImagePreview?.lineIndex == lineIndex
            ? resizingImagePreview?.width
            : reference.width
        let targetWidth = explicitWidth.map { max(80, min($0, maxWidth)) }
        let scale = min(
            (targetWidth ?? imageSize.width) / imageSize.width,
            maxWidth / imageSize.width,
            maxHeight / imageSize.height
        )
        return NSSize(
            width: floor(imageSize.width * scale),
            height: floor(imageSize.height * scale)
        )
    }

    private func imagePreviewLineHeight(for line: DisplayLineInfo) -> CGFloat {
        guard let reference = imageReference(in: line.text),
              let image = image(for: reference)
        else {
            return lineHeight()
        }

        return imagePreviewSize(for: image, reference: reference, lineIndex: line.index).height + 12
    }

    private func kind(at index: Int) -> LineKind {
        guard index >= 0, index < lineKinds.count else {
            return .normal
        }

        return lineKinds[index]
    }

    private func reconcileLineKinds() {
        if textView.string.isEmpty && !preservesEmptyStructuredLine {
            lineKinds = [.normal]
            return
        }

        lineKinds = normalizedLineKinds(lineKinds, for: textView.string)

        if lineKinds.isEmpty {
            lineKinds = [.normal]
        }
    }

    private func lineKindsAfterDefaultTextEdit(_ edit: PendingDefaultTextEdit) -> [LineKind] {
        var result = normalizedLineKinds(edit.lineKinds, for: edit.text)
        let textAfterEdit = textView.string
        let nsTextBefore = edit.text as NSString
        guard edit.range.location >= 0,
              NSMaxRange(edit.range) <= nsTextBefore.length
        else {
            return normalizedLineKinds(result, for: textAfterEdit)
        }

        let deletedText = nsTextBefore.substring(with: edit.range) as NSString
        let oldInfos = lineInfos(for: edit.text)
        let removedLineIndexes = deletedNewlineLocations(
            in: deletedText as String,
            startingAt: edit.range.location
        )
        .compactMap { newlineLocation in
            lineKindIndexToRemove(
                forDeletedNewlineAt: newlineLocation,
                oldInfos: oldInfos,
                oldLineKinds: result
            )
        }

        for index in Set(removedLineIndexes).sorted(by: >) where result.indices.contains(index) {
            result.remove(at: index)
        }

        let insertedLineCount = edit.replacement.filter { $0 == "\n" }.count
        if insertedLineCount > 0 {
            let insertionLineIndex = lineInfo(at: edit.range.location, in: oldInfos)?.index ?? result.count
            let insertIndex = min(result.count, insertionLineIndex + 1)
            result.insert(
                contentsOf: Array(repeating: .normal, count: insertedLineCount),
                at: insertIndex
            )
        }

        return normalizedLineKinds(result, for: textAfterEdit)
    }

    private func deletedNewlineLocations(in deletedText: String, startingAt startLocation: Int) -> [Int] {
        let nsDeletedText = deletedText as NSString
        var locations: [Int] = []

        for offset in 0..<nsDeletedText.length {
            if nsDeletedText.substring(with: NSRange(location: offset, length: 1)) == "\n" {
                locations.append(startLocation + offset)
            }
        }

        return locations
    }

    private func lineKindIndexToRemove(
        forDeletedNewlineAt newlineLocation: Int,
        oldInfos: [DisplayLineInfo],
        oldLineKinds: [LineKind]
    ) -> Int? {
        guard let previousLine = lineInfo(at: newlineLocation, in: oldInfos) else {
            return nil
        }

        if previousLine.text.isEmpty,
           kind(at: previousLine.index, in: oldLineKinds) == .normal {
            return previousLine.index
        }

        let followingLineIndex = min(previousLine.index + 1, oldLineKinds.count - 1)
        return followingLineIndex >= 0 ? followingLineIndex : nil
    }

    private func normalizedLineKinds(_ kinds: [LineKind], for text: String) -> [LineKind] {
        let lineCount = text.components(separatedBy: "\n").count
        var result = kinds
        if result.count < lineCount {
            result.append(contentsOf: Array(repeating: .normal, count: lineCount - result.count))
        } else if result.count > lineCount {
            result.removeLast(result.count - lineCount)
        }

        if result.isEmpty {
            return [.normal]
        }

        return result
    }

    private func displayLines() -> [String] {
        textView.string.components(separatedBy: "\n")
    }

    private func lineInfos() -> [DisplayLineInfo] {
        lineInfos(for: textView.string)
    }

    private func lineInfos(for text: String) -> [DisplayLineInfo] {
        let lines = text.components(separatedBy: "\n")
        var result: [DisplayLineInfo] = []
        var location = 0

        for (index, line) in lines.enumerated() {
            let length = (line as NSString).length
            let hasNewline = index < lines.count - 1
            let lineRange = NSRange(location: location, length: length + (hasNewline ? 1 : 0))
            let contentRange = NSRange(location: location, length: length)
            result.append(
                DisplayLineInfo(
                    index: index,
                    lineRange: lineRange,
                    contentRange: contentRange,
                    text: line
                )
            )
            location += lineRange.length
        }

        if result.isEmpty {
            result.append(
                DisplayLineInfo(
                    index: 0,
                    lineRange: NSRange(location: 0, length: 0),
                    contentRange: NSRange(location: 0, length: 0),
                    text: ""
                )
            )
        }

        return result
    }

    private func lineInfo(at location: Int) -> DisplayLineInfo? {
        let boundedLocation = max(0, min(location, (textView.string as NSString).length))
        return lineInfo(at: boundedLocation, in: lineInfos())
    }

    private func lineInfo(at location: Int, in infos: [DisplayLineInfo]) -> DisplayLineInfo? {
        for info in infos {
            let lineEnd = NSMaxRange(info.lineRange)
            let contentEnd = NSMaxRange(info.contentRange)
            if location <= contentEnd || location < lineEnd {
                return info
            }
        }

        return infos.last
    }

    private func kind(at index: Int, in kinds: [LineKind]) -> LineKind {
        guard index >= 0, index < kinds.count else {
            return .normal
        }

        return kinds[index]
    }

    private func lineFragmentRect(
        for line: DisplayLineInfo,
        layoutManager: NSLayoutManager
    ) -> NSRect? {
        if line.lineRange.length > 0 {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: line.lineRange,
                actualCharacterRange: nil
            )

            if glyphRange.length > 0 {
                return layoutManager.lineFragmentRect(
                    forGlyphAt: glyphRange.location,
                    effectiveRange: nil,
                    withoutAdditionalLayout: true
                )
            }
        }

        if line.contentRange.location > 0 {
            let previousRange = NSRange(location: line.contentRange.location - 1, length: 1)
            let previousGlyphRange = layoutManager.glyphRange(
                forCharacterRange: previousRange,
                actualCharacterRange: nil
            )

            if previousGlyphRange.length > 0 {
                let previousRect = layoutManager.lineFragmentRect(
                    forGlyphAt: previousGlyphRange.location,
                    effectiveRange: nil,
                    withoutAdditionalLayout: true
                )
                return NSRect(
                    x: previousRect.minX,
                    y: previousRect.maxY,
                    width: previousRect.width,
                    height: lineHeight()
                )
            }
        }

        return NSRect(x: 0, y: 0, width: bounds.width, height: lineHeight())
    }

    private func markdownText() -> String {
        let lines = displayLines()
        var markdownLines: [String] = []
        var isWritingCodeBlock = false
        var activeCodeLanguage: String?

        for (index, line) in lines.enumerated() {
            switch kind(at: index) {
            case .normal:
                if isWritingCodeBlock {
                    markdownLines.append("```")
                    isWritingCodeBlock = false
                }
                markdownLines.append(line)
            case .task(let indentColumns, let isCompleted):
                if isWritingCodeBlock {
                    markdownLines.append("```")
                    isWritingCodeBlock = false
                }
                let marker = isCompleted ? "- [x] " : "- [ ] "
                markdownLines.append(String(repeating: " ", count: indentColumns) + marker + line)
            case .bullet(let indentColumns):
                if isWritingCodeBlock {
                    markdownLines.append("```")
                    isWritingCodeBlock = false
                }
                markdownLines.append(String(repeating: " ", count: indentColumns) + "- " + line)
            case .numbered(let indentColumns, let number):
                if isWritingCodeBlock {
                    markdownLines.append("```")
                    isWritingCodeBlock = false
                }
                markdownLines.append(String(repeating: " ", count: indentColumns) + "\(number). " + line)
            case .quote:
                if isWritingCodeBlock {
                    markdownLines.append("```")
                    isWritingCodeBlock = false
                }
                markdownLines.append("> " + line)
            case .codeBlock(let language):
                if !isWritingCodeBlock || activeCodeLanguage != language {
                    if isWritingCodeBlock {
                        markdownLines.append("```")
                    }
                    markdownLines.append("```" + (language ?? ""))
                    isWritingCodeBlock = true
                    activeCodeLanguage = language
                }
                markdownLines.append(line)
            case .horizontalRule:
                if isWritingCodeBlock {
                    markdownLines.append("```")
                    isWritingCodeBlock = false
                    activeCodeLanguage = nil
                }
                markdownLines.append("---")
            case .tableRow(let isHeader, let columnCount):
                if isWritingCodeBlock {
                    markdownLines.append("```")
                    isWritingCodeBlock = false
                    activeCodeLanguage = nil
                }
                let cells = Self.tableCells(from: line, columnCount: columnCount)
                markdownLines.append("| " + cells.joined(separator: " | ") + " |")
                if isHeader {
                    markdownLines.append("| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |")
                }
            case .continuation(let indentColumns):
                if isWritingCodeBlock {
                    markdownLines.append("```")
                    isWritingCodeBlock = false
                    activeCodeLanguage = nil
                }
                markdownLines.append(continuationMarkdownPrefix(forLineAt: index, indentColumns: indentColumns) + line)
            }
        }

        if isWritingCodeBlock {
            markdownLines.append("```")
        }

        return markdownLines.joined(separator: "\n")
    }

    private static func displayDocument(from markdownText: String) -> DisplayDocument {
        let lines = markdownText.components(separatedBy: "\n")
        var displayLines: [String] = []
        var lineKinds: [LineKind] = []
        var activeTaskIndentColumns: Int?
        var isInsideCodeBlock = false
        var activeCodeLanguage: String?

        var index = 0
        while index < lines.count {
            let line = lines[index]

            if let language = parseCodeFenceLine(line) {
                isInsideCodeBlock.toggle()
                activeCodeLanguage = isInsideCodeBlock ? language : nil
                index += 1
                continue
            }

            if isInsideCodeBlock {
                displayLines.append(line)
                lineKinds.append(.codeBlock(language: activeCodeLanguage))
                activeTaskIndentColumns = nil
                index += 1
                continue
            }

            if isHorizontalRuleLine(line) {
                displayLines.append("")
                lineKinds.append(.horizontalRule)
                activeTaskIndentColumns = nil
                index += 1
                continue
            }

            if let task = parseTaskLine(line) {
                displayLines.append(task.text)
                lineKinds.append(.task(indentColumns: task.indentColumns, isCompleted: task.isCompleted))
                activeTaskIndentColumns = task.indentColumns
                index += 1
                continue
            }

            if let bullet = parseBulletLine(line) {
                displayLines.append(bullet.text)
                lineKinds.append(.bullet(indentColumns: bullet.indentColumns))
                activeTaskIndentColumns = nil
                index += 1
                continue
            }

            if let numbered = parseNumberedLine(line) {
                displayLines.append(numbered.text)
                lineKinds.append(.numbered(indentColumns: numbered.indentColumns, number: numbered.number))
                activeTaskIndentColumns = nil
                index += 1
                continue
            }

            if let quote = parseQuoteLine(line) {
                displayLines.append(quote)
                lineKinds.append(.quote)
                activeTaskIndentColumns = nil
                index += 1
                continue
            }

            if let indentColumns = activeTaskIndentColumns {
                let continuationPrefix = String(repeating: " ", count: indentColumns + 6)
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayLines.append("")
                    lineKinds.append(.continuation(indentColumns: indentColumns))
                    index += 1
                    continue
                }

                if line.hasPrefix(continuationPrefix) {
                    let startIndex = line.index(line.startIndex, offsetBy: continuationPrefix.count)
                    displayLines.append(String(line[startIndex...]))
                    lineKinds.append(.continuation(indentColumns: indentColumns))
                    index += 1
                    continue
                }
            }

            displayLines.append(line)
            lineKinds.append(.normal)
            activeTaskIndentColumns = nil
            index += 1
        }

        if displayLines.isEmpty {
            displayLines = [""]
            lineKinds = [.normal]
        }

        return DisplayDocument(
            text: displayLines.joined(separator: "\n"),
            lineKinds: lineKinds
        )
    }

    private static func parseTaskLine(_ line: String) -> (indentColumns: Int, isCompleted: Bool, text: String)? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = taskLineRegex.firstMatch(in: line, range: range) else {
            return nil
        }

        let indentation = nsLine.substring(with: match.range(at: 1))
        let marker = nsLine.substring(with: match.range(at: 2))
        let text = nsLine.substring(with: match.range(at: 3))
        return (
            indentColumns: indentColumns(in: indentation),
            isCompleted: marker.localizedCaseInsensitiveContains("x"),
            text: text
        )
    }

    private static func parseBulletLine(_ line: String) -> (indentColumns: Int, text: String)? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = bulletLineRegex.firstMatch(in: line, range: range) else {
            return nil
        }

        return (
            indentColumns: indentColumns(in: nsLine.substring(with: match.range(at: 1))),
            text: nsLine.substring(with: match.range(at: 2))
        )
    }

    private static func parseNumberedLine(_ line: String) -> (indentColumns: Int, number: Int, text: String)? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = numberedLineRegex.firstMatch(in: line, range: range) else {
            return nil
        }

        return (
            indentColumns: indentColumns(in: nsLine.substring(with: match.range(at: 1))),
            number: Int(nsLine.substring(with: match.range(at: 2))) ?? 1,
            text: nsLine.substring(with: match.range(at: 3))
        )
    }

    private static func parseQuoteLine(_ line: String) -> String? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = quoteLineRegex.firstMatch(in: line, range: range) else {
            return nil
        }

        return nsLine.substring(with: match.range(at: 1))
    }

    private static func parseCodeFenceLine(_ line: String) -> String?? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") else {
            return nil
        }

        let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !language.contains("`") else {
            return nil
        }

        if language.isEmpty {
            return .some(nil)
        }

        return .some(language.lowercased())
    }

    private static func isHorizontalRuleLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    private static func parseMarkdownTable(
        startingAt index: Int,
        lines: [String],
        requiresBodyRow: Bool = false,
        requiresClosedRows: Bool = false
    ) -> (rows: [[String]], columnCount: Int, nextIndex: Int)? {
        guard index + 1 < lines.count,
              (!requiresClosedRows || isClosedMarkdownTableRow(lines[index])),
              (!requiresClosedRows || isClosedMarkdownTableRow(lines[index + 1])),
              let headerCells = parseMarkdownTableRow(lines[index]),
              isMarkdownTableSeparator(lines[index + 1], expectedColumnCount: headerCells.count)
        else {
            return nil
        }

        var rows = [headerCells]
        var cursor = index + 2
        while cursor < lines.count,
              (!requiresClosedRows || isClosedMarkdownTableRow(lines[cursor])),
              let row = parseMarkdownTableRow(lines[cursor]),
              row.count == headerCells.count {
            rows.append(row)
            cursor += 1
        }

        if requiresBodyRow, rows.count < 2 {
            return nil
        }

        return (rows: rows, columnCount: headerCells.count, nextIndex: cursor)
    }

    private static func isClosedMarkdownTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|")
    }

    private static func parseMarkdownTableRow(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else {
            return nil
        }

        var rawCells = trimmed.components(separatedBy: "|")
        if rawCells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            rawCells.removeFirst()
        }
        if rawCells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            rawCells.removeLast()
        }

        let cells = rawCells.map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count >= 2 else {
            return nil
        }

        return cells
    }

    private static func isMarkdownTableSeparator(_ line: String, expectedColumnCount: Int) -> Bool {
        guard let cells = parseMarkdownTableRow(line),
              cells.count == expectedColumnCount
        else {
            return false
        }

        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return stripped.count >= 1 && stripped.allSatisfy { $0 == "-" }
        }
    }

    private static func tableDisplayText(from cells: [String]) -> String {
        cells.joined(separator: "\t")
    }

    private static func tableCells(from displayText: String, columnCount: Int) -> [String] {
        var cells = displayText.components(separatedBy: "\t")
        if cells.count == 1 {
            cells = displayText.components(separatedBy: "  ").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
        }

        if cells.count < columnCount {
            cells.append(contentsOf: Array(repeating: "", count: columnCount - cells.count))
        }

        return Array(cells.prefix(columnCount)).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func hasTypedTaskSeparator(in line: String) -> Bool {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        return typedTaskSeparatorRegex.firstMatch(in: line, range: range) != nil
    }

    private static func parseTypedTaskContent(_ line: String) -> (isCompleted: Bool, text: String)? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = typedTaskContentRegex.firstMatch(in: line, range: range) else {
            return nil
        }

        let marker = nsLine.substring(with: match.range(at: 1))
        return (
            isCompleted: marker.localizedCaseInsensitiveContains("x"),
            text: nsLine.substring(with: match.range(at: 2))
        )
    }

    private static func containsTaskMarkdown(in text: String) -> Bool {
        text.components(separatedBy: "\n").contains { parseTaskLine($0) != nil }
    }

    private static func indentColumns(in indentation: String) -> Int {
        indentation.reduce(0) { partialResult, character in
            partialResult + (character == "\t" ? 4 : 1)
        }
    }

    private static let taskLineRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)[-*+][ \t]*(\[(?:[ xX]?)\])[ \t]*(.*)$"#
    )

    private static let bulletLineRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)[-*+][ \t]+(?!\[[ xX]\][ \t]*)(.*)$"#
    )

    private static let numberedLineRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(\d+)\.[ \t]+(.*)$"#
    )

    private static let quoteLineRegex = try! NSRegularExpression(
        pattern: #"^>[ \t]?(.*)$"#
    )

    private static let typedTaskSeparatorRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*[-*+][ \t]*\[(?:[ xX]?)\][ \t]*.*$"#
    )

    private static let typedTaskContentRegex = try! NSRegularExpression(
        pattern: #"^(\[(?:[ xX]?)\])[ \t]*(.*)$"#
    )

    private static let markdownImageLineRegex = try! NSRegularExpression(
        pattern: #"^!\[([^\]]*)\]\(([^)\s]+)\)(?:\{width=(\d+(?:\.\d+)?)\})?$"#
    )
}

private final class SlashCommandPaletteView: NSView {
    private static let rowHeight: CGFloat = 24
    private static let rowSpacing: CGFloat = 2
    private static let verticalPadding: CGFloat = 6
    private let scrollView = NSScrollView()
    private let documentView = SlashCommandPaletteDocumentView()
    private let stackView = NSStackView()
    private var trackingArea: NSTrackingArea?
    var onSelect: ((String) -> Void)?
    var onHover: ((String) -> Void)?
    var selectedIndex = 0 {
        didSet {
            updateButtonColors()
            scrollSelectedCommandToVisible()
        }
    }
    var palette: AppTheme.Palette = AppTheme.yellow {
        didSet {
            needsDisplay = true
            updateButtonColors()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var isOpaque: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }

        for case let button as SlashCommandButton in stackView.arrangedSubviews.reversed() {
            let buttonPoint = button.convert(point, from: self)
            if button.bounds.contains(buttonPoint) {
                return button
            }
        }

        return self
    }

    func configure(commands: [(title: String, syntaxHint: String, rawValue: String)]) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, command) in commands.enumerated() {
            let button = SlashCommandButton(title: "", target: self, action: #selector(selectCommand(_:)))
            button.commandTitle = command.title
            button.syntaxHint = command.syntaxHint
            button.setAccessibilityLabel(command.title)
            button.identifier = NSUserInterfaceItemIdentifier(command.rawValue)
            button.palette = palette
            button.isSelectedForPalette = index == selectedIndex
            button.onHover = { [weak self] rawValue in
                self?.onHover?(rawValue)
            }
            button.isBordered = false
            button.alignment = .left
            button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            button.setButtonType(.momentaryChange)
            button.contentTintColor = palette.textNS
            button.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(button)
            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalToConstant: Self.rowHeight),
                button.widthAnchor.constraint(equalTo: stackView.widthAnchor)
            ])
        }
        needsLayout = true
        scrollSelectedCommandToVisible()
    }

    override var fittingSize: NSSize {
        NSSize(width: 248, height: documentHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        menuSurfaceColor.setFill()
        bounds.fill()

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        menuSurfaceColor.setFill()
        path.fill()
        palette.checkboxBorderNS.withAlphaComponent(0.7).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    private var menuSurfaceColor: NSColor {
        switch palette.kind {
        case .yellow:
            return NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.70, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.98, green: 0.985, blue: 0.97, alpha: 1)
        case .dark:
            return NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.14, alpha: 1)
        }
    }

    private func configureViews() {
        wantsLayer = true
        shadow = NSShadow()
        shadow?.shadowBlurRadius = 10
        shadow?.shadowOffset = NSSize(width: 0, height: -2)
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.16)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = Self.rowSpacing
        stackView.edgeInsets = NSEdgeInsets(
            top: Self.verticalPadding,
            left: 8,
            bottom: Self.verticalPadding,
            right: 8
        )
        stackView.translatesAutoresizingMaskIntoConstraints = true
        stackView.autoresizingMask = [.width, .height]
        documentView.addSubview(stackView)
        scrollView.documentView = documentView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func layout() {
        super.layout()

        let clipSize = scrollView.contentView.bounds.size
        let documentHeight = max(self.documentHeight, clipSize.height)
        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(0, clipSize.width),
            height: max(0, documentHeight)
        )
        stackView.frame = documentView.bounds
    }

    private var documentHeight: CGFloat {
        let rowCount = CGFloat(max(1, stackView.arrangedSubviews.count))
        let spacingCount = CGFloat(max(0, stackView.arrangedSubviews.count - 1))
        return Self.verticalPadding * 2 + rowCount * Self.rowHeight + spacingCount * Self.rowSpacing
    }

    private func updateButtonColors() {
        for (index, view) in stackView.arrangedSubviews.enumerated() {
            guard let button = view as? SlashCommandButton else {
                continue
            }

            button.palette = palette
            button.isSelectedForPalette = index == selectedIndex
            button.contentTintColor = palette.textNS
        }
    }

    func resetForOpening() {
        selectedIndex = 0
        for case let button as SlashCommandButton in stackView.arrangedSubviews {
            button.resetPressedState()
        }
        layoutSubtreeIfNeeded()
        scrollTo(y: 0)
        updateButtonColors()
    }

    func scrollSelectedCommandToTop() {
        scrollTo(y: 0)
    }

    func scrollSelectedCommandToBottom() {
        layoutSubtreeIfNeeded()
        let maxY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        scrollTo(y: maxY)
    }

    func scrollSelectedCommandToVisible() {
        guard stackView.arrangedSubviews.indices.contains(selectedIndex) else {
            return
        }

        layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()
        let selectedY = Self.verticalPadding + CGFloat(selectedIndex) * (Self.rowHeight + Self.rowSpacing)
        let targetRect = NSRect(
            x: 0,
            y: selectedY - 4,
            width: documentView.bounds.width,
            height: Self.rowHeight + 8
        )
        let clipView = scrollView.contentView
        var targetOrigin = clipView.bounds.origin

        if targetRect.minY < clipView.bounds.minY {
            targetOrigin.y = targetRect.minY
        } else if targetRect.maxY > clipView.bounds.maxY {
            targetOrigin.y = targetRect.maxY - clipView.bounds.height
        }

        let maxY = max(0, documentView.bounds.height - clipView.bounds.height)
        targetOrigin.y = min(max(0, targetOrigin.y), maxY)
        targetOrigin.x = 0
        scrollTo(y: targetOrigin.y)
    }

    private func scrollTo(y: CGFloat) {
        layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let maxY = max(0, documentView.bounds.height - clipView.bounds.height)
        clipView.scroll(to: NSPoint(x: 0, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(clipView)
    }

    @objc private func selectCommand(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue else {
            return
        }

        onSelect?(rawValue)
    }
}

private final class SlashCommandPaletteDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

private final class SlashCommandButton: NSButton {
    var commandTitle = "" {
        didSet {
            titleLabel.stringValue = commandTitle
        }
    }
    var syntaxHint = "" {
        didSet {
            hintLabel.stringValue = syntaxHint
        }
    }
    var palette: AppTheme.Palette = AppTheme.yellow {
        didSet {
            updateLabelColors()
            needsDisplay = true
        }
    }
    var isSelectedForPalette = false {
        didSet {
            needsDisplay = true
        }
    }
    var onHover: ((String) -> Void)?
    private let titleLabel = SlashCommandLabel(labelWithString: "")
    private let hintLabel = SlashCommandLabel(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isPressedForPalette = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var isFlipped: Bool {
        true
    }

    private func configureViews() {
        isBordered = false
        title = ""

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isSelectable = false

        hintLabel.font = NSFont.userFixedPitchFont(ofSize: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.alignment = .right
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.isSelectable = false

        addSubview(titleLabel)
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: hintLabel.leadingAnchor, constant: -12),

            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            hintLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])

        updateLabelColors()
    }

    private func updateLabelColors() {
        titleLabel.textColor = palette.textNS
        hintLabel.textColor = palette.textNS.withAlphaComponent(0.58)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return
        }
        isPressedForPalette = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { isPressedForPalette = false }

        guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return
        }
        sendAction(action, to: target)
    }

    func resetPressedState() {
        isPressedForPalette = false
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        isPressedForPalette = false
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
        if let rawValue = identifier?.rawValue {
            onHover?(rawValue)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelectedForPalette || isPressedForPalette {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5)
            palette.accentNS.withAlphaComponent(isPressedForPalette ? 0.4 : 0.3).setFill()
            path.fill()
        }
    }
}

private final class SlashCommandLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}

private final class TodoTextView: NSTextView {
    var copyHandler: (() -> Bool)?
    var cutHandler: (() -> Bool)?
    var pasteHandler: (() -> Bool)?
    var canPasteHandler: (() -> Bool)?
    var checkboxMouseDownHandler: ((NSEvent) -> Bool)?
    var selectionDragDidEndHandler: (() -> Void)?
    var imageCursorProvider: ((NSPoint) -> NSCursor?)?
    var imageCursorRects: [NSRect] = [] {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }
    var imageResizeCursorRects: [NSRect] = [] {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }
    var checkboxCursorRects: [NSRect] = [] {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }
    var slashCommandCursorRects: [NSRect] = [] {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }
    private var checkboxTrackingArea: NSTrackingArea?

    override func copy(_ sender: Any?) {
        if copyHandler?() == true {
            return
        }

        super.copy(sender)
    }

    override func cut(_ sender: Any?) {
        if cutHandler?() == true {
            return
        }

        super.cut(sender)
    }

    override func paste(_ sender: Any?) {
        if pasteHandler?() == true {
            return
        }

        super.paste(sender)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)),
           canPasteHandler?() == true {
            return true
        }

        return super.validateUserInterfaceItem(item)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let character = event.charactersIgnoringModifiers?.lowercased()
        guard flags.contains(.command) || flags.contains(.control) else {
            super.keyDown(with: event)
            return
        }

        if character == "x" {
            if cutHandler?() == true {
                return
            }

            super.keyDown(with: event)
            return
        }

        guard character == "z" else {
            super.keyDown(with: event)
            return
        }

        let manager = undoManager ?? window?.undoManager
        if flags.contains(.shift) {
            if manager?.canRedo == true {
                manager?.redo()
            }
            return
        }

        if manager?.canUndo == true {
            manager?.undo()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if checkboxMouseDownHandler?(event) == true {
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        selectionDragDidEndHandler?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let checkboxTrackingArea {
            removeTrackingArea(checkboxTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        checkboxTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if slashCommandCursorRects.contains(where: { $0.contains(point) }) {
            NSCursor.pointingHand.set()
            return
        }

        if let imageCursor = imageCursorProvider?(point) {
            imageCursor.set()
            return
        }

        if checkboxCursorRects.contains(where: { $0.contains(point) }) {
            NSCursor.pointingHand.set()
            return
        }

        super.mouseMoved(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        for rect in slashCommandCursorRects {
            addCursorRect(rect, cursor: .pointingHand)
        }

        for rect in checkboxCursorRects {
            addCursorRect(rect, cursor: .pointingHand)
        }

        for rect in imageCursorRects {
            addCursorRect(rect, cursor: .arrow)
        }

        for rect in imageResizeCursorRects {
            addCursorRect(rect, cursor: .resizeLeftRight)
        }
    }
}

private struct TodoCheckboxOverlayItem {
    var frame: NSRect
    var isChecked: Bool
    var lineIndex: Int
}

private struct LineMarkerOverlayItem {
    enum Kind {
        case bullet(level: Int)
        case number(Int, level: Int)
        case quote
        case codeBlock(language: String?)
        case horizontalRule
        case tableRow(isHeader: Bool, cells: [String], rowIndex: Int)
    }

    var kind: Kind
    var frame: NSRect
}

private struct MarkdownImageOverlayItem {
    var attachmentPath: String
    var image: NSImage
    var altText: String
    var frame: NSRect
    var lineIndex: Int
    var isSelected: Bool

    var resizeHandleRect: NSRect {
        NSRect(
            x: frame.maxX - 8,
            y: frame.midY - 15,
            width: 16,
            height: 30
        )
    }
}

private struct MarkdownImageCaretItem {
    var frame: NSRect
}

private final class MarkdownImageOverlayView: NSView {
    var palette: AppTheme.Palette = AppTheme.yellow {
        didSet {
            needsDisplay = true
        }
    }

    private var items: [MarkdownImageOverlayItem] = []
    private var caret: MarkdownImageCaretItem?

    override var isFlipped: Bool {
        true
    }

    func setItems(_ items: [MarkdownImageOverlayItem], caret: MarkdownImageCaretItem?) {
        self.items = items
        self.caret = caret
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for item in items {
            drawImage(item)
        }

        if let caret {
            drawCaret(caret)
        }
    }

    private func drawImage(_ item: MarkdownImageOverlayItem) {
        let borderPath = NSBezierPath(roundedRect: item.frame, xRadius: 6, yRadius: 6)
        (item.isSelected ? palette.accentNS : palette.checkboxBorderNS)
            .withAlphaComponent(item.isSelected ? 0.78 : 0.35)
            .setStroke()
        borderPath.lineWidth = item.isSelected ? 2 : 1
        borderPath.stroke()

        if item.isSelected {
            drawResizeHandle(for: item)
        }
    }

    private func drawCaret(_ item: MarkdownImageCaretItem) {
        let path = NSBezierPath(roundedRect: item.frame, xRadius: 1, yRadius: 1)
        palette.accentNS.setFill()
        path.fill()
    }

    private func drawResizeHandle(for item: MarkdownImageOverlayItem) {
        let rect = item.resizeHandleRect
        let visibleRect = NSRect(
            x: rect.midX - 4,
            y: rect.minY + 4,
            width: 8,
            height: rect.height - 8
        )
        let handlePath = NSBezierPath(roundedRect: visibleRect, xRadius: 4, yRadius: 4)
        NSColor.white.withAlphaComponent(0.92).setFill()
        handlePath.fill()
        palette.accentNS.withAlphaComponent(0.72).setStroke()
        handlePath.lineWidth = 1
        handlePath.stroke()

        palette.accentNS.withAlphaComponent(0.5).setStroke()
        for offset in [-1.5, 1.5] {
            let linePath = NSBezierPath()
            linePath.move(to: NSPoint(x: visibleRect.midX + offset, y: visibleRect.minY + 5))
            linePath.line(to: NSPoint(x: visibleRect.midX + offset, y: visibleRect.maxY - 5))
            linePath.lineWidth = 1
            linePath.stroke()
        }
    }
}

@MainActor
private final class MarkdownImageInteractionOverlayView: NSView {
    var onSelectImage: ((MarkdownImageOverlayItem, NSEvent) -> Void)?
    var onResizeImage: ((MarkdownImageOverlayItem, NSEvent) -> Void)?

    private let analyzer = ImageAnalyzer()
    private var analysisCache: [String: ImageAnalysis] = [:]
    private var textRegionCache: [String: [CGRect]] = [:]
    private var analysisTasks: [String: Task<Void, Never>] = [:]
    private var imageViews: [String: LiveTextImageView] = [:]
    private var items: [MarkdownImageOverlayItem] = []
    private var analysisGeneration = 0

    override var isFlipped: Bool {
        true
    }

    func setItems(_ items: [MarkdownImageOverlayItem]) {
        self.items = items

        let visibleKeys = Set(items.map(viewKey(for:)))
        for (key, imageView) in imageViews where !visibleKeys.contains(key) {
            imageView.removeFromSuperview()
            imageViews.removeValue(forKey: key)
        }

        for item in items {
            let key = viewKey(for: item)
            let imageView: LiveTextImageView
            if let existing = imageViews[key] {
                imageView = existing
            } else {
                imageView = LiveTextImageView()
                imageViews[key] = imageView
                addSubview(imageView)
            }

            imageView.frame = item.frame
            imageView.setImage(item.image)

            if let analysis = analysisCache[item.attachmentPath] {
                imageView.setAnalysis(
                    analysis,
                    textRegions: textRegionCache[item.attachmentPath] ?? []
                )
            } else {
                analyze(item)
            }
        }

        window?.invalidateCursorRects(for: self)
    }

    func clearAnalysisCache() {
        analysisGeneration += 1
        analysisTasks.values.forEach { $0.cancel() }
        analysisTasks.removeAll()
        analysisCache.removeAll()
        textRegionCache.removeAll()
        imageViews.values.forEach { $0.setAnalysis(nil, textRegions: []) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard let (item, imageView) = imageTarget(at: localPoint) else {
            return nil
        }

        if item.isSelected, item.resizeHandleRect.contains(localPoint) {
            return self
        }

        let imagePoint = imageView.convert(localPoint, from: self)
        switch imageView.interactionRegion(at: imagePoint) {
        case .ocrControl(let control):
            return control
        case .ocrText:
            if let event = NSApp.currentEvent {
                imageView.prepareForTextSelection(with: event)
            }
            return imageView.liveTextTarget(at: imagePoint)
        case .imageBody:
            return self
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let (item, imageView) = imageTarget(at: point) else {
            return
        }

        imageView.resetTextSelection()
        if item.isSelected, item.resizeHandleRect.contains(point) {
            onResizeImage?(item, event)
        } else {
            onSelectImage?(item, event)
        }
    }

    func cursor(at point: NSPoint) -> NSCursor? {
        guard let (item, imageView) = imageTarget(at: point) else {
            return nil
        }

        if item.isSelected, item.resizeHandleRect.contains(point) {
            return .resizeLeftRight
        }

        let imagePoint = imageView.convert(point, from: self)
        switch imageView.interactionRegion(at: imagePoint) {
        case .ocrControl:
            return .arrow
        case .ocrText:
            return .iBeam
        case .imageBody:
            return .arrow
        }
    }

    func imageFrameRects() -> [NSRect] {
        items.map(\.frame)
    }

    func resizeHandleRects() -> [NSRect] {
        items.filter(\.isSelected).map(\.resizeHandleRect)
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        for rect in imageFrameRects() {
            addCursorRect(rect, cursor: .arrow)
        }

        for rect in resizeHandleRects() {
            addCursorRect(rect, cursor: .resizeLeftRight)
        }
    }

    private func imageTarget(at point: NSPoint) -> (MarkdownImageOverlayItem, LiveTextImageView)? {
        for item in items.reversed() where item.frame.contains(point) {
            guard let imageView = imageViews[viewKey(for: item)] else {
                continue
            }
            return (item, imageView)
        }
        return nil
    }

    private func analyze(_ item: MarkdownImageOverlayItem) {
        guard ImageAnalyzer.isSupported,
              analysisTasks[item.attachmentPath] == nil
        else {
            return
        }

        let attachmentPath = item.attachmentPath
        let image = item.image
        let generation = analysisGeneration
        var proposedRect = NSRect(origin: .zero, size: image.size)
        let cgImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        )
        analysisTasks[attachmentPath] = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let configuration = ImageAnalyzer.Configuration([.text])
                async let analysisRequest = analyzer.analyze(
                    image,
                    orientation: .up,
                    configuration: configuration
                )
                let textRegions = await Self.recognizedTextRegions(in: cgImage)
                let analysis = try await analysisRequest
                guard !Task.isCancelled else {
                    return
                }

                guard generation == analysisGeneration else {
                    return
                }
                analysisCache[attachmentPath] = analysis
                textRegionCache[attachmentPath] = textRegions
                for (key, imageView) in imageViews
                    where key.hasPrefix(attachmentPath + "|") {
                    imageView.setAnalysis(analysis, textRegions: textRegions)
                }
            } catch {
                // An unreadable image remains a normal resizable image.
            }

            if generation == analysisGeneration {
                analysisTasks.removeValue(forKey: attachmentPath)
            }
        }
    }

    private func viewKey(for item: MarkdownImageOverlayItem) -> String {
        "\(item.attachmentPath)|\(item.lineIndex)"
    }

    nonisolated private static func recognizedTextRegions(
        in image: CGImage?
    ) async -> [CGRect] {
        guard let image else {
            return []
        }

        return await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            do {
                let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
                try handler.perform([request])
                return (request.results ?? []).compactMap { observation in
                    guard observation.topCandidates(1).first != nil else {
                        return nil
                    }

                    let bounds = observation.boundingBox
                    return bounds.width > 0 && bounds.height > 0 ? bounds : nil
                }
            } catch {
                return []
            }
        }.value
    }
}

@MainActor
private final class OCRRegionOverlayView: NSView {
    var regions: [CGRect] = [] {
        didSet { needsDisplay = true }
    }

    var imageRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    var showsRegions = false {
        didSet {
            isHidden = !showsRegions
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsRegions, !imageRect.isEmpty else { return }

        for region in regions {
            let rect = NSRect(
                x: imageRect.minX + region.minX * imageRect.width,
                y: imageRect.minY + (1 - region.maxY) * imageRect.height,
                width: region.width * imageRect.width,
                height: region.height * imageRect.height
            ).insetBy(dx: -1.5, dy: -1.5)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            NSColor.systemCyan.withAlphaComponent(0.18).setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.72).setStroke()
            path.lineWidth = 3
            path.stroke()
            NSColor.systemCyan.withAlphaComponent(0.95).setStroke()
            path.lineWidth = 1.25
            path.stroke()
        }
    }
}

@MainActor
private final class OCRHighlightButton: NSButton {
    private final class SymbolView: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    private let symbolView = SymbolView()

    var symbolColor: NSColor {
        get { symbolView.contentTintColor ?? .labelColor }
        set { symbolView.contentTintColor = newValue }
    }

    init(symbol: NSImage) {
        super.init(frame: .zero)

        title = ""
        alternateTitle = ""
        attributedTitle = NSAttributedString(string: "")
        attributedAlternateTitle = NSAttributedString(string: "")

        symbolView.image = symbol
        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 16),
            symbolView.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class LiveTextImageView: NSView, ImageAnalysisOverlayViewDelegate {
    enum InteractionRegion {
        case ocrControl(NSView)
        case ocrText
        case imageBody
    }

    private let imageView = NSImageView()
    private lazy var analysisOverlay = ImageAnalysisOverlayView(self)
    private let regionOverlay = OCRRegionOverlayView()
    private lazy var ocrButton = makeOCRButton()
    private var currentAnalysis: ImageAnalysis?
    private var recognizedTextRegions: [CGRect] = []
    private var preparedMouseDownTimestamp: TimeInterval?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func layout() {
        super.layout()
        regionOverlay.imageRect = displayedImageRect()
    }

    func setImage(_ image: NSImage) {
        if imageView.image !== image {
            imageView.image = image
        }
    }

    func setAnalysis(_ analysis: ImageAnalysis?, textRegions: [CGRect]) {
        if currentAnalysis == nil, analysis == nil, recognizedTextRegions.isEmpty,
           textRegions.isEmpty {
            return
        }
        if let currentAnalysis, let analysis, currentAnalysis === analysis,
           recognizedTextRegions == textRegions {
            return
        }

        currentAnalysis = analysis
        recognizedTextRegions = textRegions
        regionOverlay.regions = textRegions
        analysisOverlay.analysis = analysis
        analysisOverlay.preferredInteractionTypes = analysis == nil ? [] : [.textSelection]
        ocrButton.isHidden = analysis == nil
        if analysis == nil {
            ocrButton.state = .off
            regionOverlay.showsRegions = false
        }
    }

    func interactionRegion(at point: NSPoint) -> InteractionRegion {
        if let control = ocrControlTarget(at: point) {
            return .ocrControl(control)
        }

        let overlayPoint = analysisOverlay.convert(point, from: self)
        guard currentAnalysis != nil,
              containsRecognizedText(at: point, overlayPoint: overlayPoint)
        else {
            return .imageBody
        }

        return .ocrText
    }

    func liveTextTarget(at point: NSPoint) -> NSView {
        let overlayPoint = analysisOverlay.convert(point, from: self)
        return analysisOverlay.hitTest(overlayPoint) ?? analysisOverlay
    }

    func ocrControlTarget(at point: NSPoint) -> NSView? {
        guard !ocrButton.isHidden else {
            return nil
        }

        let buttonPoint = ocrButton.convert(point, from: self)
        return ocrButton.bounds.contains(buttonPoint) ? ocrButton : nil
    }

    func resetTextSelection() {
        if analysisOverlay.hasActiveTextSelection {
            analysisOverlay.resetSelection()
        }
    }

    func prepareForTextSelection(with event: NSEvent) {
        guard event.type == .leftMouseDown,
              preparedMouseDownTimestamp != event.timestamp
        else {
            return
        }

        preparedMouseDownTimestamp = event.timestamp
        resetTextSelection()
    }

    func contentsRect(for overlayView: ImageAnalysisOverlayView) -> CGRect {
        CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    func contentView(for overlayView: ImageAnalysisOverlayView) -> NSView? {
        imageView
    }

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        shouldBeginAt point: CGPoint,
        forAnalysisType analysisType: ImageAnalysisOverlayView.InteractionTypes
    ) -> Bool {
        analysisType.contains(.textSelection)
    }

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        highlightSelectedItemsDidChange highlightSelectedItems: Bool
    ) {
        ocrButton.state = highlightSelectedItems ? .on : .off
        regionOverlay.showsRegions = highlightSelectedItems
        updateOCRButtonAppearance()
    }

    private func configureViews() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false

        analysisOverlay.translatesAutoresizingMaskIntoConstraints = false
        regionOverlay.translatesAutoresizingMaskIntoConstraints = false
        analysisOverlay.trackingImageView = imageView
        analysisOverlay.isSupplementaryInterfaceHidden = true
        analysisOverlay.preferredInteractionTypes = []

        addSubview(imageView)
        addSubview(analysisOverlay)
        addSubview(regionOverlay)
        addSubview(ocrButton)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            analysisOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            analysisOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            analysisOverlay.topAnchor.constraint(equalTo: topAnchor),
            analysisOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            regionOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            regionOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            regionOverlay.topAnchor.constraint(equalTo: topAnchor),
            regionOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            ocrButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            ocrButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            ocrButton.widthAnchor.constraint(equalToConstant: 24),
            ocrButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func makeOCRButton() -> OCRHighlightButton {
        let image = NSImage(
            systemSymbolName: "text.viewfinder",
            accessibilityDescription: "Show recognized text"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        )
        let button = OCRHighlightButton(symbol: image ?? NSImage())
        button.target = self
        button.action = #selector(toggleOCRHighlights(_:))
        button.setButtonType(.toggle)
        button.isBordered = false
        button.focusRingType = .none
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.borderWidth = 1
        button.layer?.shadowColor = NSColor.black.cgColor
        button.layer?.shadowOpacity = 0.18
        button.layer?.shadowRadius = 2
        button.layer?.shadowOffset = NSSize(width: 0, height: -1)
        button.setAccessibilityLabel("Show recognized text")
        button.toolTip = "Show recognized text"
        updateOCRButtonAppearance(button)
        return button
    }

    @objc private func toggleOCRHighlights(_ sender: NSButton) {
        analysisOverlay.selectableItemsHighlighted = sender.state == .on
        regionOverlay.showsRegions = sender.state == .on
        updateOCRButtonAppearance()
    }

    private func updateOCRButtonAppearance(_ button: OCRHighlightButton? = nil) {
        let button = button ?? ocrButton
        let title = button.state == .on
            ? "Hide recognized text"
            : "Show recognized text"
        button.setAccessibilityLabel(title)
        button.toolTip = title

        if button.state == .on {
            button.layer?.backgroundColor = NSColor.controlAccentColor
                .withAlphaComponent(0.88)
                .cgColor
            button.layer?.borderColor = NSColor.white.withAlphaComponent(0.72).cgColor
            button.symbolColor = .white
        } else {
            button.layer?.backgroundColor = NSColor.white
                .withAlphaComponent(0.98)
                .cgColor
            button.layer?.borderColor = NSColor.black.withAlphaComponent(0.38).cgColor
            button.symbolColor = NSColor.black.withAlphaComponent(0.9)
        }
    }

    private func containsRecognizedText(
        at point: NSPoint,
        overlayPoint: NSPoint
    ) -> Bool {
        if recognizedTextRegions.isEmpty {
            return analysisOverlay.analysisHasText(at: overlayPoint)
        }

        let contentRect = displayedImageRect()
        return recognizedTextRegions.contains { region in
            let viewRect = NSRect(
                x: contentRect.minX + region.minX * contentRect.width,
                y: contentRect.minY + (1 - region.maxY) * contentRect.height,
                width: region.width * contentRect.width,
                height: region.height * contentRect.height
            ).insetBy(dx: -2, dy: -2)
            return viewRect.contains(point)
        }
    }

    private func displayedImageRect() -> NSRect {
        guard let image = imageView.image,
              image.size.width > 0,
              image.size.height > 0,
              bounds.width > 0,
              bounds.height > 0
        else {
            return bounds
        }

        let scale = min(
            bounds.width / image.size.width,
            bounds.height / image.size.height
        )
        let size = NSSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        return NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

}

private final class TodoCheckboxOverlayView: NSView {
    var palette: AppTheme.Palette = AppTheme.yellow {
        didSet {
            needsDisplay = true
        }
    }

    private var items: [TodoCheckboxOverlayItem] = []
    private var markers: [LineMarkerOverlayItem] = []

    override var isFlipped: Bool {
        true
    }

    func setItems(_ items: [TodoCheckboxOverlayItem], markers: [LineMarkerOverlayItem] = []) {
        self.items = items
        self.markers = markers
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func resetCursorRects() {
        for item in items {
            addCursorRect(clickTarget(for: item), cursor: .pointingHand)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for marker in markers {
            drawMarker(marker)
        }

        for item in items {
            drawCheckbox(item)
        }
    }

    func lineIndex(at point: NSPoint) -> Int? {
        items.first { clickTarget(for: $0).contains(point) }?.lineIndex
    }

    func clickTargetRects() -> [NSRect] {
        items.map { clickTarget(for: $0) }
    }

    private func clickTarget(for item: TodoCheckboxOverlayItem) -> NSRect {
        item.frame.insetBy(dx: -2, dy: -2)
    }

    private func drawCheckbox(_ item: TodoCheckboxOverlayItem) {
        let boxSize: CGFloat = 16
        let boxRect = NSRect(
            x: floor(item.frame.midX - boxSize / 2),
            y: floor(item.frame.midY - boxSize / 2),
            width: boxSize,
            height: boxSize
        )

        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 3.5, yRadius: 3.5)
        (item.isChecked ? palette.checkboxCheckedNS : palette.checkboxUncheckedNS).setFill()
        boxPath.fill()

        palette.checkboxBorderNS.setStroke()
        boxPath.lineWidth = 1.5
        boxPath.stroke()

        guard item.isChecked else {
            return
        }

        let checkPath = NSBezierPath()
        checkPath.move(to: NSPoint(x: boxRect.minX + 4, y: boxRect.midY + 0.5))
        checkPath.line(to: NSPoint(x: boxRect.minX + 7, y: boxRect.maxY - 4))
        checkPath.line(to: NSPoint(x: boxRect.maxX - 3.5, y: boxRect.minY + 4))
        palette.checkboxCheckmarkNS.setStroke()
        checkPath.lineWidth = 2.2
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        checkPath.stroke()
    }

    private func drawMarker(_ item: LineMarkerOverlayItem) {
        switch item.kind {
        case .bullet(let level):
            drawBullet(level: level, in: item.frame)

        case .number(let number, let level):
            drawMarkerText(numberedMarker(number: number, level: level), in: item.frame)

        case .quote:
            let bar = NSRect(x: item.frame.minX + 5, y: item.frame.minY + 1, width: 3, height: item.frame.height - 2)
            palette.accentNS.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()

        case .codeBlock(let language):
            let blockRect = item.frame.integral.insetBy(dx: 0.5, dy: 0.5)
            let blockPath = NSBezierPath(roundedRect: blockRect, xRadius: 6, yRadius: 6)
            palette.codeBackgroundNS.withAlphaComponent(palette.kind == .dark ? 0.34 : 0.24).setFill()
            blockPath.fill()

            palette.checkboxBorderNS.withAlphaComponent(palette.kind == .dark ? 0.34 : 0.28).setStroke()
            blockPath.lineWidth = 1
            blockPath.stroke()

            let railRect = NSRect(
                x: blockRect.minX + 4,
                y: blockRect.minY + 5,
                width: 3,
                height: max(0, blockRect.height - 10)
            )
            palette.accentNS.withAlphaComponent(0.65).setFill()
            NSBezierPath(roundedRect: railRect, xRadius: 1.5, yRadius: 1.5).fill()

            if let language, !language.isEmpty {
                let label = language.uppercased()
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .semibold),
                    .foregroundColor: palette.secondaryTextNS.withAlphaComponent(0.9)
                ]
                let size = (label as NSString).size(withAttributes: attributes)
                let chipRect = NSRect(
                    x: blockRect.maxX - size.width - 18,
                    y: blockRect.minY + 5,
                    width: size.width + 12,
                    height: 16
                )
                palette.checkboxUncheckedNS.withAlphaComponent(palette.kind == .dark ? 0.18 : 0.5).setFill()
                NSBezierPath(roundedRect: chipRect, xRadius: 4, yRadius: 4).fill()
                (label as NSString).draw(
                    at: NSPoint(x: chipRect.minX + 6, y: chipRect.minY + 2.5),
                    withAttributes: attributes
                )
            }

        case .horizontalRule:
            let line = NSRect(
                x: item.frame.minX + 2,
                y: item.frame.midY - 0.75,
                width: item.frame.width - 4,
                height: 1.5
            )
            palette.checkboxBorderNS.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: line, xRadius: 0.75, yRadius: 0.75).fill()

        case .tableRow(let isHeader, let cells, let rowIndex):
            let columnCount = max(1, cells.count)
            let rowRect = item.frame.integral.insetBy(dx: 0, dy: 0)
            let rowPath = NSBezierPath(rect: rowRect)
            palette.codeBackgroundNS.withAlphaComponent(isHeader ? 0.46 : 0.22).setFill()
            rowPath.fill()

            let borderColor = palette.checkboxBorderNS.withAlphaComponent(0.45)
            borderColor.setStroke()

            func strokeLine(from start: NSPoint, to end: NSPoint, width: CGFloat = 1) {
                let path = NSBezierPath()
                path.move(to: start)
                path.line(to: end)
                path.lineWidth = width
                path.stroke()
            }

            let minX = rowRect.minX + 0.5
            let maxX = rowRect.maxX - 0.5
            let minY = rowRect.minY + 0.5
            let maxY = rowRect.maxY - 0.5
            let columnWidth = rowRect.width / CGFloat(columnCount)

            strokeLine(from: NSPoint(x: minX, y: minY), to: NSPoint(x: minX, y: maxY))
            strokeLine(from: NSPoint(x: maxX, y: minY), to: NSPoint(x: maxX, y: maxY))
            if rowIndex == 0 {
                strokeLine(from: NSPoint(x: minX, y: minY), to: NSPoint(x: maxX, y: minY))
            }
            if isHeader {
                strokeLine(from: NSPoint(x: minX, y: maxY - 2), to: NSPoint(x: maxX, y: maxY - 2))
            }
            strokeLine(from: NSPoint(x: minX, y: maxY), to: NSPoint(x: maxX, y: maxY))

            if columnCount > 1 {
                for column in 1..<columnCount {
                    let x = rowRect.minX + columnWidth * CGFloat(column) + 0.5
                    strokeLine(from: NSPoint(x: x, y: minY), to: NSPoint(x: x, y: maxY))
                }
            }

            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: isHeader
                    ? NSFont.systemFont(ofSize: 12, weight: .semibold)
                    : NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: palette.textNS
            ]
            for (index, cell) in cells.enumerated() {
                let cellRect = NSRect(
                    x: rowRect.minX + CGFloat(index) * columnWidth + 8,
                    y: rowRect.minY + max(2, (rowRect.height - 15) / 2),
                    width: max(0, columnWidth - 16),
                    height: rowRect.height
                )
                (cell as NSString).draw(in: cellRect, withAttributes: textAttributes)
            }
        }
    }

    private func drawMarkerText(_ text: String, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: palette.textNS.withAlphaComponent(0.7)
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        attributed.draw(
            at: NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2
            )
        )
    }

    private func drawBullet(level: Int, in rect: NSRect) {
        let color = palette.textNS.withAlphaComponent(0.72)

        switch level % 3 {
        case 1:
            let circleRect = NSRect(
                x: floor(rect.midX - 3),
                y: floor(rect.midY - 3),
                width: 6,
                height: 6
            )
            color.setStroke()
            let path = NSBezierPath(ovalIn: circleRect)
            path.lineWidth = 1.25
            path.stroke()

        case 2:
            let squareRect = NSRect(
                x: floor(rect.midX - 2.5),
                y: floor(rect.midY - 2.5),
                width: 5,
                height: 5
            )
            color.setFill()
            NSBezierPath(roundedRect: squareRect, xRadius: 0.6, yRadius: 0.6).fill()

        default:
            let dotRect = NSRect(
                x: floor(rect.midX - 2.3),
                y: floor(rect.midY - 2.3),
                width: 4.6,
                height: 4.6
            )
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }

    private func numberedMarker(number: Int, level: Int) -> String {
        let safeNumber = max(1, number)
        switch level % 3 {
        case 1:
            return "\(alphabeticNumber(safeNumber))."
        case 2:
            return "\(romanNumber(safeNumber))."
        default:
            return "\(safeNumber)."
        }
    }

    private func alphabeticNumber(_ number: Int) -> String {
        var value = number
        var scalars: [UnicodeScalar] = []

        while value > 0 {
            value -= 1
            scalars.append(UnicodeScalar(97 + value % 26)!)
            value /= 26
        }

        return String(String.UnicodeScalarView(scalars.reversed()))
    }

    private func romanNumber(_ number: Int) -> String {
        let numerals: [(value: Int, symbol: String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"),
            (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
            (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")
        ]
        var remainder = number
        var result = ""

        for numeral in numerals {
            while remainder >= numeral.value {
                result += numeral.symbol
                remainder -= numeral.value
            }
        }

        return result
    }
}

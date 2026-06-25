import AppKit
import SwiftUI

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
        InlineTodoTextEditor(
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
                .fill(AppTheme.paperInset.opacity(0.76))
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
}

private struct InlineTodoTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> InlineTodoTextEditorContainer {
        let view = InlineTodoTextEditorContainer()
        view.onTextChange = { [coordinator = context.coordinator] newText in
            coordinator.text.wrappedValue = newText
        }
        view.setText(text)
        return view
    }

    func updateNSView(_ nsView: InlineTodoTextEditorContainer, context: Context) {
        context.coordinator.text = $text

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
        case continuation(indentColumns: Int)

        var indentColumns: Int {
            switch self {
            case .normal:
                return 0
            case .task(let indentColumns, _), .continuation(let indentColumns):
                return indentColumns
            }
        }

        var isTask: Bool {
            if case .task = self {
                return true
            }

            return false
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

    private let scrollView = NSScrollView()
    private let textView = TodoTextView()
    private let overlayView = TodoCheckboxOverlayView()
    private let baseFont = NSFont.systemFont(ofSize: 14)
    private let baseTextColor = NSColor(calibratedRed: 0.17, green: 0.14, blue: 0.10, alpha: 1)
    private var lineKinds: [LineKind] = [.normal]
    private var isApplyingProgrammaticChange = false

    var onTextChange: ((String) -> Void)?

    var text: String {
        markdownText()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setText(_ text: String) {
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

        reconcileLineKinds()
        notifyTextChangedAndRefresh(scrollSelection: true)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateTypingAttributesForCurrentSelection()
    }

    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                return insertSoftLineBreak()
            }

            return insertReturn()

        case #selector(NSResponder.insertTab(_:)):
            return adjustIndent(by: 4)

        case #selector(NSResponder.insertBacktab(_:)):
            return adjustIndent(by: -4)

        case #selector(NSResponder.deleteBackward(_:)):
            return unwrapTaskIfNeeded()

        default:
            return false
        }
    }

    override func layout() {
        super.layout()
        refreshOverlay()
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
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.font = baseFont
        textView.textColor = baseTextColor
        textView.typingAttributes = baseAttributes()
        textView.defaultParagraphStyle = baseParagraphStyle()
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor
        ]
        textView.insertionPointColor = NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.42, alpha: 1)
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.checkboxMouseDownHandler = { [weak self] event in
            self?.handleCheckboxMouseDown(event) ?? false
        }

        overlayView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = textView
        addSubview(scrollView)
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
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

        switch kind(at: line.index) {
        case .task(let indentColumns, _):
            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .task(indentColumns: indentColumns, isCompleted: false)
            )

        case .continuation(let indentColumns):
            if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lineKinds[line.index] = .task(indentColumns: indentColumns, isCompleted: false)
                notifyTextChangedAndRefresh(scrollSelection: true)
                return true
            }

            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .task(indentColumns: indentColumns, isCompleted: false)
            )

        case .normal:
            return false
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
        case .task(let indentColumns, _), .continuation(let indentColumns):
            return insertLineBreak(
                at: selectedRange,
                afterLineIndex: line.index,
                newLineKind: .continuation(indentColumns: indentColumns)
            )

        case .normal:
            return false
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
        }
    }

    private func adjustIndent(by delta: Int) -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location)
        else {
            return false
        }

        switch kind(at: line.index) {
        case .task(let indentColumns, let isCompleted):
            lineKinds[line.index] = .task(
                indentColumns: max(0, indentColumns + delta),
                isCompleted: isCompleted
            )
        case .continuation(let indentColumns):
            lineKinds[line.index] = .continuation(indentColumns: max(0, indentColumns + delta))
        case .normal:
            return false
        }

        notifyTextChangedAndRefresh(scrollSelection: true)
        return true
    }

    private func unwrapTaskIfNeeded() -> Bool {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length == 0,
              let line = lineInfo(at: selectedRange.location),
              selectedRange.location == line.contentRange.location
        else {
            return false
        }

        switch kind(at: line.index) {
        case .task, .continuation:
            lineKinds[line.index] = .normal
            notifyTextChangedAndRefresh(scrollSelection: true)
            return true
        case .normal:
            return false
        }
    }

    private func applyTextStorageEdit(
        range: NSRange,
        replacement: String,
        selectedRange: NSRange,
        updateLineKinds: () -> Void
    ) -> Bool {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else {
            return true
        }

        isApplyingProgrammaticChange = true
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        updateLineKinds()
        reconcileLineKinds()
        textView.setSelectedRange(selectedRange)
        textView.didChangeText()
        isApplyingProgrammaticChange = false
        notifyTextChangedAndRefresh(scrollSelection: true)
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

        lineKinds[lineIndex] = .task(indentColumns: indentColumns, isCompleted: !isCompleted)
        notifyTextChangedAndRefresh(scrollSelection: false)
        return true
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

    private func refreshOverlay() {
        overlayView.setItems([])

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let visibleBounds = scrollView.contentView.bounds
        let textContainerOrigin = textView.textContainerOrigin
        var checkboxItems: [TodoCheckboxOverlayItem] = []

        for line in lineInfos() where kind(at: line.index).isTask {
            guard let lineRect = lineFragmentRect(for: line, layoutManager: layoutManager) else {
                continue
            }

            let y = textContainerOrigin.y + lineRect.minY - visibleBounds.origin.y + 1
            guard y > -24, y < bounds.height + 24 else {
                continue
            }

            let checkboxLeftX = taskCheckboxIndent(for: kind(at: line.index).indentColumns)
            let x = max(0, textContainerOrigin.x + checkboxLeftX - visibleBounds.origin.x - TodoLayout.checkboxDrawInset)
            let isCompleted: Bool
            if case .task(_, let completed) = kind(at: line.index) {
                isCompleted = completed
            } else {
                isCompleted = false
            }

            checkboxItems.append(
                TodoCheckboxOverlayItem(
                    frame: NSRect(
                        x: x,
                        y: y - 2,
                        width: TodoLayout.checkboxFrameWidth,
                        height: TodoLayout.checkboxFrameHeight
                    ),
                    isChecked: isCompleted,
                    lineIndex: line.index
                )
            )
        }

        overlayView.setItems(checkboxItems)
        textView.checkboxCursorRects = overlayView.clickTargetRects().map {
            textView.convert($0, from: overlayView)
        }
    }

    private func applyDisplayAttributes() {
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        guard let textStorage = textView.textStorage else {
            return
        }

        let selectedRange = textView.selectedRange()
        let completedColor = NSColor(calibratedRed: 0.50, green: 0.46, blue: 0.38, alpha: 1)
        let codeBackground = NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.62, alpha: 0.72)
        let strikethroughColor = NSColor(calibratedRed: 0.43, green: 0.37, blue: 0.30, alpha: 1)

        textStorage.beginEditing()
        if fullRange.length > 0 {
            textStorage.setAttributes(baseAttributes(), range: fullRange)
        }

        if shouldParseInlineMarkdown {
            for span in MarkdownInlineParser.spans(in: textView.string) {
                for syntaxRange in span.syntaxRanges {
                    textStorage.addAttributes(
                        [
                            .foregroundColor: NSColor.clear,
                            .font: hiddenSyntaxFont()
                        ],
                        range: syntaxRange
                    )
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

        for line in lineInfos() {
            let lineKind = kind(at: line.index)
            let paragraphRange = paragraphAttributeRange(for: line)
            textStorage.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(for: lineKind),
                range: paragraphRange
            )

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
        }

        textStorage.endEditing()
        textView.setSelectedRange(selectedRange)
        updateTypingAttributesForCurrentSelection()
        textView.setNeedsDisplay(textView.visibleRect)
    }

    private var shouldParseInlineMarkdown: Bool {
        textView.string.rangeOfCharacter(from: CharacterSet(charactersIn: "#*`~")) != nil
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
        attributes[.paragraphStyle] = paragraphStyle(for: kind(at: line.index))
        textView.typingAttributes = attributes
    }

    private func paragraphStyle(for kind: LineKind) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let textIndent: CGFloat
        switch kind {
        case .normal:
            textIndent = 0
        case .task(let indentColumns, _), .continuation(let indentColumns):
            textIndent = taskTextIndent(for: indentColumns)
        }

        style.firstLineHeadIndent = textIndent
        style.headIndent = textIndent
        style.minimumLineHeight = lineHeight()
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: baseTextColor,
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
        textView.scrollRangeToVisible(scrollRangeForSelection())
        refreshOverlay()
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

    private func kind(at index: Int) -> LineKind {
        guard index >= 0, index < lineKinds.count else {
            return .normal
        }

        return lineKinds[index]
    }

    private func reconcileLineKinds() {
        let lineCount = displayLines().count
        if lineKinds.count < lineCount {
            lineKinds.append(contentsOf: Array(repeating: .normal, count: lineCount - lineKinds.count))
        } else if lineKinds.count > lineCount {
            lineKinds.removeLast(lineKinds.count - lineCount)
        }

        if lineKinds.isEmpty {
            lineKinds = [.normal]
        }
    }

    private func displayLines() -> [String] {
        textView.string.components(separatedBy: "\n")
    }

    private func lineInfos() -> [DisplayLineInfo] {
        let lines = displayLines()
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
        let infos = lineInfos()

        for info in infos {
            let lineEnd = NSMaxRange(info.lineRange)
            let contentEnd = NSMaxRange(info.contentRange)
            if boundedLocation <= contentEnd || boundedLocation < lineEnd {
                return info
            }
        }

        return infos.last
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

        for (index, line) in lines.enumerated() {
            switch kind(at: index) {
            case .normal:
                markdownLines.append(line)
            case .task(let indentColumns, let isCompleted):
                let marker = isCompleted ? "- [x] " : "- [ ] "
                markdownLines.append(String(repeating: " ", count: indentColumns) + marker + line)
            case .continuation(let indentColumns):
                markdownLines.append(String(repeating: " ", count: indentColumns + 6) + line)
            }
        }

        return markdownLines.joined(separator: "\n")
    }

    private static func displayDocument(from markdownText: String) -> DisplayDocument {
        let lines = markdownText.components(separatedBy: "\n")
        var displayLines: [String] = []
        var lineKinds: [LineKind] = []
        var activeTaskIndentColumns: Int?

        for line in lines {
            if let task = parseTaskLine(line) {
                displayLines.append(task.text)
                lineKinds.append(.task(indentColumns: task.indentColumns, isCompleted: task.isCompleted))
                activeTaskIndentColumns = task.indentColumns
                continue
            }

            if let indentColumns = activeTaskIndentColumns {
                let continuationPrefix = String(repeating: " ", count: indentColumns + 6)
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayLines.append("")
                    lineKinds.append(.continuation(indentColumns: indentColumns))
                    continue
                }

                if line.hasPrefix(continuationPrefix) {
                    let startIndex = line.index(line.startIndex, offsetBy: continuationPrefix.count)
                    displayLines.append(String(line[startIndex...]))
                    lineKinds.append(.continuation(indentColumns: indentColumns))
                    continue
                }
            }

            displayLines.append(line)
            lineKinds.append(.normal)
            activeTaskIndentColumns = nil
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

    private static func indentColumns(in indentation: String) -> Int {
        indentation.reduce(0) { partialResult, character in
            partialResult + (character == "\t" ? 4 : 1)
        }
    }

    private static let taskLineRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)[-*+][ \t]+(\[[ xX]\])[ \t]*(.*)$"#
    )
}

private final class TodoTextView: NSTextView {
    var checkboxMouseDownHandler: ((NSEvent) -> Bool)?
    var checkboxCursorRects: [NSRect] = [] {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }
    private var checkboxTrackingArea: NSTrackingArea?

    override func mouseDown(with event: NSEvent) {
        if checkboxMouseDownHandler?(event) == true {
            return
        }

        super.mouseDown(with: event)
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
        if checkboxCursorRects.contains(where: { $0.contains(point) }) {
            NSCursor.pointingHand.set()
            return
        }

        super.mouseMoved(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        for rect in checkboxCursorRects {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }
}

private struct TodoCheckboxOverlayItem {
    var frame: NSRect
    var isChecked: Bool
    var lineIndex: Int
}

private final class TodoCheckboxOverlayView: NSView {
    private let checkedFillColor = NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.42, alpha: 1)
    private let uncheckedFillColor = NSColor(calibratedWhite: 1.0, alpha: 0.82)
    private let borderColor = NSColor(calibratedRed: 0.40, green: 0.35, blue: 0.20, alpha: 0.56)
    private let checkmarkColor = NSColor.white
    private var items: [TodoCheckboxOverlayItem] = []

    override var isFlipped: Bool {
        true
    }

    func setItems(_ items: [TodoCheckboxOverlayItem]) {
        self.items = items
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
        (item.isChecked ? checkedFillColor : uncheckedFillColor).setFill()
        boxPath.fill()

        borderColor.setStroke()
        boxPath.lineWidth = 1.5
        boxPath.stroke()

        guard item.isChecked else {
            return
        }

        let checkPath = NSBezierPath()
        checkPath.move(to: NSPoint(x: boxRect.minX + 4, y: boxRect.midY + 0.5))
        checkPath.line(to: NSPoint(x: boxRect.minX + 7, y: boxRect.maxY - 4))
        checkPath.line(to: NSPoint(x: boxRect.maxX - 3.5, y: boxRect.minY + 4))
        checkmarkColor.setStroke()
        checkPath.lineWidth = 2.2
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        checkPath.stroke()
    }
}

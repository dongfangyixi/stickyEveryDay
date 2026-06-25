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
    private let scrollView = NSScrollView()
    private let textView = TodoTextView()
    private let overlayView = TodoCheckboxOverlayView()
    private let baseFont = NSFont.systemFont(ofSize: 14)
    private let baseTextColor = NSColor(calibratedRed: 0.17, green: 0.14, blue: 0.10, alpha: 1)

    var onTextChange: ((String) -> Void)?

    var text: String {
        textView.string
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
        guard textView.string != text else {
            refreshCheckboxes()
            return
        }

        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: baseAttributes())
        )
        refreshCheckboxes()
    }

    func textDidChange(_ notification: Notification) {
        onTextChange?(textView.string)
        refreshCheckboxesSoon()
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
        case #selector(NSResponder.insertLineBreak(_:)):
            return applyTextEdit(
                MarkdownTaskParser.softLineBreakEdit(
                    in: textView.string,
                    selectedRange: textView.selectedRange()
                )
            )

        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                return applyTextEdit(
                    MarkdownTaskParser.softLineBreakEdit(
                        in: textView.string,
                        selectedRange: textView.selectedRange()
                    )
                )
            }

            return applyTextEdit(
                MarkdownTaskParser.newlineEdit(
                    in: textView.string,
                    selectedRange: textView.selectedRange()
                )
            )

        case #selector(NSResponder.insertTab(_:)):
            return applyTextEdit(
                MarkdownTaskParser.indentationEdit(
                    in: textView.string,
                    selectedRange: textView.selectedRange(),
                    direction: .inward
                )
            )

        case #selector(NSResponder.insertBacktab(_:)):
            return applyTextEdit(
                MarkdownTaskParser.indentationEdit(
                    in: textView.string,
                    selectedRange: textView.selectedRange(),
                    direction: .outward
                )
            )

        default:
            return false
        }
    }

    override func layout() {
        super.layout()
        refreshCheckboxesSoon()
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
        refreshCheckboxesSoon()
    }

    private func refreshCheckboxesSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshCheckboxes()
        }
    }

    private func refreshCheckboxes() {
        overlayView.setItems([])

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let visibleBounds = scrollView.contentView.bounds
        let textContainerOrigin = textView.textContainerOrigin

        let lines = MarkdownTaskParser.todoLines(in: textView.string)
        let continuationLines = MarkdownTaskParser.continuationLines(in: textView.string)
        applyMarkdownAttributes(taskLines: lines, continuationLines: continuationLines)
        layoutManager.ensureLayout(for: textContainer)

        var checkboxItems: [TodoCheckboxOverlayItem] = []
        for line in lines {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: line.lineRange,
                actualCharacterRange: nil
            )

            guard glyphRange.length > 0 else {
                continue
            }

            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            let y = textContainerOrigin.y + lineRect.minY - visibleBounds.origin.y + 1

            guard y > -24, y < bounds.height + 24 else {
                continue
            }

            let x = taskCheckboxFrameX(
                for: line,
                textContainerOrigin: textContainerOrigin,
                visibleBounds: visibleBounds
            )
            checkboxItems.append(
                TodoCheckboxOverlayItem(
                    frame: NSRect(
                        x: x,
                        y: y - 2,
                        width: TodoLayout.checkboxFrameWidth,
                        height: TodoLayout.checkboxFrameHeight
                    ),
                    isChecked: line.isCompleted,
                    lineLocation: line.lineRange.location
                )
            )
        }

        overlayView.setItems(checkboxItems)
        textView.checkboxCursorRects = overlayView.clickTargetRects().map {
            textView.convert($0, from: overlayView)
        }
    }

    private func taskCheckboxFrameX(
        for line: MarkdownTaskLine,
        textContainerOrigin: NSPoint,
        visibleBounds: NSRect
    ) -> CGFloat {
        let checkboxLeftX = textContainerOrigin.x + taskCheckboxIndent(for: line) - visibleBounds.origin.x
        return max(0, checkboxLeftX - TodoLayout.checkboxDrawInset)
    }

    private func taskCheckboxIndent(for line: MarkdownTaskLine) -> CGFloat {
        CGFloat(line.indentColumns) / TodoLayout.markdownIndentColumnsPerLevel * TodoLayout.levelIndent
    }

    private func taskTextIndent(for line: MarkdownTaskLine) -> CGFloat {
        taskCheckboxIndent(for: line) + TodoLayout.taskTextOffset
    }

    private func applyMarkdownAttributes(
        taskLines: [MarkdownTaskLine],
        continuationLines: [MarkdownContinuationLine]
    ) {
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)

        guard fullRange.length > 0, let textStorage = textView.textStorage else {
            return
        }

        let syntaxColor = NSColor.clear
        let completedColor = NSColor(calibratedRed: 0.50, green: 0.46, blue: 0.38, alpha: 1)
        let codeBackground = NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.62, alpha: 0.72)
        let strikethroughColor = NSColor(calibratedRed: 0.43, green: 0.37, blue: 0.30, alpha: 1)

        let selectedRange = textView.selectedRange()
        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes(), range: fullRange)

        for span in MarkdownInlineParser.spans(in: textView.string) {
            for syntaxRange in span.syntaxRanges {
                textStorage.addAttributes(
                    [
                        .foregroundColor: syntaxColor,
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

        for line in taskLines {
            let paragraphRange = clampedRange(line.lineRange, within: fullRange)
            let prefixRange = clampedRange(taskPrefixRange(for: line), within: fullRange)

            if paragraphRange.length > 0 {
                textStorage.addAttribute(
                    .paragraphStyle,
                    value: taskParagraphStyle(for: line),
                    range: paragraphRange
                )
            }

            textStorage.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    .font: hiddenSyntaxFont()
                ],
                range: prefixRange
            )

            guard line.isCompleted, line.textRange.length > 0 else {
                continue
            }

            textStorage.addAttributes(
                [
                    .foregroundColor: completedColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: completedColor
                ],
                range: line.textRange
            )
        }

        for line in continuationLines {
            let paragraphRange = clampedRange(line.lineRange, within: fullRange)
            let whitespaceRange = clampedRange(line.leadingWhitespaceRange, within: fullRange)

            if paragraphRange.length > 0 {
                textStorage.addAttribute(
                    .paragraphStyle,
                    value: taskParagraphStyle(for: line.taskLine),
                    range: paragraphRange
                )
            }

            if whitespaceRange.length > 0 {
                textStorage.addAttributes(
                    [
                        .foregroundColor: NSColor.clear,
                        .font: hiddenSyntaxFont()
                    ],
                    range: whitespaceRange
                )
            }
        }

        textStorage.endEditing()
        textView.setSelectedRange(selectedRange)
        textView.typingAttributes = typingAttributes(
            for: selectedRange,
            taskLines: taskLines,
            continuationLines: continuationLines
        )
    }

    private func typingAttributes(
        for selectedRange: NSRange,
        taskLines: [MarkdownTaskLine],
        continuationLines: [MarkdownContinuationLine]
    ) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes()
        let insertionLocation = selectedRange.location

        if let line = taskLines.first(where: { containsInsertionLocation(insertionLocation, lineRange: $0.lineRange) }) {
            attributes[.paragraphStyle] = taskParagraphStyle(for: line)
        } else if let line = continuationLines.first(where: { containsInsertionLocation(insertionLocation, lineRange: $0.lineRange) }) {
            attributes[.paragraphStyle] = taskParagraphStyle(for: line.taskLine)
        }

        return attributes
    }

    private func containsInsertionLocation(_ location: Int, lineRange: NSRange) -> Bool {
        location >= lineRange.location && location <= NSMaxRange(lineRange)
    }

    private func taskParagraphStyle(for line: MarkdownTaskLine) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let textIndent = taskTextIndent(for: line)
        style.firstLineHeadIndent = textIndent
        style.headIndent = textIndent
        style.minimumLineHeight = ceil(baseFont.ascender - baseFont.descender + baseFont.leading)
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private func taskPrefixRange(for line: MarkdownTaskLine) -> NSRange {
        NSRange(
            location: line.lineRange.location,
            length: max(0, NSMaxRange(line.syntaxRange) - line.lineRange.location)
        )
    }

    private func clampedRange(_ range: NSRange, within bounds: NSRange) -> NSRange {
        let lowerBound = max(range.location, bounds.location)
        let upperBound = min(NSMaxRange(range), NSMaxRange(bounds))
        return NSRange(location: lowerBound, length: max(0, upperBound - lowerBound))
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

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: baseTextColor
        ]
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

    private func handleCheckboxMouseDown(_ event: NSEvent) -> Bool {
        let point = overlayView.convert(event.locationInWindow, from: nil)
        guard let lineLocation = overlayView.lineLocation(at: point) else {
            return false
        }

        toggleCheckbox(lineLocation: lineLocation)
        return true
    }

    private func applyTextEdit(_ edit: MarkdownTaskParser.TextEdit?) -> Bool {
        guard let edit else {
            return false
        }

        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else {
            return true
        }

        textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(edit.selectedRange)
        refreshCheckboxes()
        return true
    }

    private func toggleCheckbox(lineLocation: Int) {
        guard let edit = MarkdownTaskParser.toggleEdit(in: textView.string, lineLocation: lineLocation) else {
            return
        }

        let selectedRange = textView.selectedRange()
        let replacementLength = (edit.replacement as NSString).length
        let delta = replacementLength - edit.range.length

        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else {
            return
        }

        textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()

        var adjustedRange = selectedRange
        if selectedRange.location >= NSMaxRange(edit.range) {
            adjustedRange.location = max(0, selectedRange.location + delta)
        }
        textView.setSelectedRange(adjustedRange)

        refreshCheckboxes()
    }
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
    var lineLocation: Int
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

    private func item(at point: NSPoint) -> TodoCheckboxOverlayItem? {
        items.first { clickTarget(for: $0).contains(point) }
    }

    func lineLocation(at point: NSPoint) -> Int? {
        item(at: point)?.lineLocation
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

import AppKit
import SwiftUI

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
        .padding(14)
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
        guard replacementString == "\n",
              affectedCharRange.length == 0,
              let edit = MarkdownTaskParser.newlineEdit(
                in: textView.string,
                selectedRange: affectedCharRange
              )
        else {
            return true
        }

        textView.insertText(edit.replacement, replacementRange: affectedCharRange)
        return false
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
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
        textView.textContainerInset = NSSize(width: 36, height: 12)
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
        applyMarkdownAttributes(taskLines: lines)
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

            let textStartX = taskTextStartX(
                for: line,
                layoutManager: layoutManager,
                textContainer: textContainer,
                textContainerOrigin: textContainerOrigin,
                visibleBounds: visibleBounds
            )
            let x = max(8, textStartX - 28)
            checkboxItems.append(
                TodoCheckboxOverlayItem(
                    frame: NSRect(x: x, y: y - 2, width: 26, height: 22),
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

    private func taskTextStartX(
        for line: MarkdownTaskLine,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textContainerOrigin: NSPoint,
        visibleBounds: NSRect
    ) -> CGFloat {
        guard let characterLocation = firstVisibleTaskTextLocation(for: line) else {
            return emptyTaskTextStartX(
                for: line,
                layoutManager: layoutManager,
                textContainer: textContainer,
                textContainerOrigin: textContainerOrigin,
                visibleBounds: visibleBounds
            )
        }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterLocation, length: 1),
            actualCharacterRange: nil
        )

        guard glyphRange.length > 0 else {
            return textContainerOrigin.x + 24
        }

        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return textContainerOrigin.x + glyphRect.minX - visibleBounds.origin.x
    }

    private func emptyTaskTextStartX(
        for line: MarkdownTaskLine,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textContainerOrigin: NSPoint,
        visibleBounds: NSRect
    ) -> CGFloat {
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: line.syntaxRange,
            actualCharacterRange: nil
        )

        guard glyphRange.length > 0 else {
            return textContainerOrigin.x + 24
        }

        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return textContainerOrigin.x + glyphRect.maxX - visibleBounds.origin.x
    }

    private func firstVisibleTaskTextLocation(for line: MarkdownTaskLine) -> Int? {
        let nsText = textView.string as NSString
        let textEnd = min(NSMaxRange(line.textRange), nsText.length)

        guard line.textRange.location < textEnd else {
            return nil
        }

        for location in line.textRange.location..<textEnd {
            let character = nsText.character(at: location)
            guard let scalar = UnicodeScalar(character),
                  CharacterSet.whitespacesAndNewlines.contains(scalar)
            else {
                return location
            }
        }

        return line.textRange.location
    }

    private func applyMarkdownAttributes(taskLines: [MarkdownTaskLine]) {
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
            let taskSyntaxAnchorRange = NSRange(
                location: max(line.syntaxRange.location, NSMaxRange(line.syntaxRange) - 1),
                length: min(1, line.syntaxRange.length)
            )

            textStorage.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    .font: hiddenSyntaxFont()
                ],
                range: line.syntaxRange
            )
            textStorage.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    .font: baseFont
                ],
                range: taskSyntaxAnchorRange
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

        textStorage.endEditing()
        textView.setSelectedRange(selectedRange)
        textView.typingAttributes = baseAttributes()
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
        refreshCheckboxesSoon()
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

        refreshCheckboxesSoon()
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

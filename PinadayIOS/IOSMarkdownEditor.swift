import PhotosUI
import SwiftUI
import UIKit

struct IOSMarkdownCommand: Equatable {
    enum Action: Equatable {
        case wrap(prefix: String, suffix: String, placeholder: String)
        case prefixLine(String)
        case insert(String)
        case codeBlock
    }

    let id = UUID()
    let action: Action
}

struct IOSNoteEditor: View {
    @Binding var text: String
    let dateKey: String
    let focusRequestID: UUID
    let blurRequestID: UUID
    @Binding var command: IOSMarkdownCommand?
    let palette: AppTheme.Palette

    private var imageReferences: [MarkdownImageReference] {
        MarkdownImageReferenceParser.references(in: text)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !imageReferences.isEmpty {
                IOSAttachmentGallery(
                    references: imageReferences,
                    palette: palette
                )
                Rectangle()
                    .fill(palette.separator)
                    .frame(height: 1)
            }

            IOSMarkdownTextView(
                text: $text,
                dateKey: dateKey,
                focusRequestID: focusRequestID,
                blurRequestID: blurRequestID,
                command: $command,
                palette: palette
            )
        }
        .background(palette.paperInset)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 14,
                topTrailingRadius: 14
            )
        )
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }
}

private struct IOSAttachmentGallery: View {
    let references: [MarkdownImageReference]
    let palette: AppTheme.Palette

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(references, id: \.path) { reference in
                    IOSAttachmentPreview(reference: reference, palette: palette)
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .frame(height: 170)
    }
}

private struct IOSAttachmentPreview: View {
    let reference: MarkdownImageReference
    let palette: AppTheme.Palette

    @State private var recognizedText = ""

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ContentUnavailableView(
                    "Image unavailable",
                    systemImage: "photo.badge.exclamationmark"
                )
            }
        }
        .frame(minWidth: 180, maxWidth: 300, minHeight: 140, maxHeight: 146)
        .background(palette.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(palette.separator, lineWidth: 1)
        }
        .contextMenu {
            if !recognizedText.isEmpty {
                Button {
                    UIPasteboard.general.string = recognizedText
                } label: {
                    Label("Copy recognized text", systemImage: "text.viewfinder")
                }
            }
            if let image {
                Button {
                    UIPasteboard.general.image = image
                } label: {
                    Label("Copy Image", systemImage: "doc.on.doc")
                }
            }
        }
        .task(id: reference.path) {
            let observations = await ImageOCRRepository.shared.observations(for: reference.path)
            recognizedText = observations.map(\.text).joined(separator: "\n")
        }
        .accessibilityLabel(reference.altText.isEmpty ? "Image" : reference.altText)
    }

    private var image: UIImage? {
        guard let url = AttachmentStore.imageURL(for: reference.path) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

struct IOSFormatBar: View {
    let palette: AppTheme.Palette
    @Binding var command: IOSMarkdownCommand?
    @Binding var selectedPhoto: PhotosPickerItem?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 3) {
                formatButton("bold", label: "Bold") {
                    .wrap(prefix: "**", suffix: "**", placeholder: "bold text")
                }
                formatButton("italic", label: "Italic") {
                    .wrap(prefix: "_", suffix: "_", placeholder: "italic text")
                }
                formatButton("checklist", label: "Todo list") {
                    .prefixLine("- [ ] ")
                }
                formatButton("textformat.size.larger", label: "Heading") {
                    .prefixLine("## ")
                }
                formatButton("list.bullet", label: "Bulleted list") {
                    .prefixLine("- ")
                }
                formatButton("list.number", label: "Numbered list") {
                    .prefixLine("1. ")
                }
                formatButton("text.quote", label: "Quote") {
                    .prefixLine("> ")
                }
                formatButton("chevron.left.forwardslash.chevron.right", label: "Code block") {
                    .codeBlock
                }
                formatButton("minus", label: "Divider") {
                    .insert("\n---\n")
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Add image")
                }
                .foregroundStyle(palette.text)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
        }
        .scrollIndicators(.hidden)
        .background(palette.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.separator).frame(height: 1)
        }
    }

    private func formatButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> IOSMarkdownCommand.Action
    ) -> some View {
        Button {
            command = IOSMarkdownCommand(action: action())
        } label: {
            Image(systemName: systemName)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .foregroundStyle(palette.text)
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct IOSMarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    let dateKey: String
    let focusRequestID: UUID
    let blurRequestID: UUID
    @Binding var command: IOSMarkdownCommand?
    let palette: AppTheme.Palette

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MarkdownUITextView {
        let view = MarkdownUITextView()
        context.coordinator.lastFocusRequestID = focusRequestID
        context.coordinator.lastBlurRequestID = blurRequestID
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = .yes
        view.smartDashesType = .yes
        view.smartQuotesType = .yes
        view.textContainerInset = UIEdgeInsets(top: 18, left: 12, bottom: 30, right: 12)
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.accessibilityLabel = "Daily note"
        view.onPasteImage = { [weak coordinator = context.coordinator] image in
            coordinator?.markdownForPastedImage(image)
        }
        view.onToggleTask = { [weak coordinator = context.coordinator, weak view] lineLocation in
            guard let coordinator, let view else { return }
            coordinator.toggleTask(at: lineLocation, in: view)
        }

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        context.coordinator.applyText(text, to: view, force: true)
        return view
    }

    func updateUIView(_ view: MarkdownUITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyText(text, to: view)
        context.coordinator.applyPalette(to: view)

        if context.coordinator.lastBlurRequestID != blurRequestID {
            context.coordinator.lastBlurRequestID = blurRequestID
            context.coordinator.focusTask?.cancel()
            view.resignFirstResponder()
        }

        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            context.coordinator.focusTask?.cancel()
            let requestID = focusRequestID
            context.coordinator.focusTask = Task { @MainActor [weak view, weak coordinator = context.coordinator] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled,
                      coordinator?.parent.focusRequestID == requestID,
                      let view else {
                    return
                }
                view.becomeFirstResponder()
                view.selectedRange = NSRange(location: view.textStorage.length, length: 0)
            }
        }

        if let command,
           context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            DispatchQueue.main.async {
                context.coordinator.apply(command, to: view)
                self.command = nil
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSMarkdownTextView
        var lastFocusRequestID: UUID?
        var lastBlurRequestID: UUID?
        var lastCommandID: UUID?
        var focusTask: Task<Void, Never>?

        private var isApplyingText = false

        init(parent: IOSMarkdownTextView) {
            self.parent = parent
        }

        func applyText(_ text: String, to view: UITextView, force: Bool = false) {
            guard force || view.text != text else { return }
            guard view.markedTextRange == nil else { return }

            let selection = view.selectedRange
            isApplyingText = true
            view.text = text
            view.selectedRange = NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            )
            applyPalette(to: view)
            isApplyingText = false
        }

        func applyPalette(to view: UITextView) {
            guard view.markedTextRange == nil else { return }
            let selection = view.selectedRange
            let text = view.text ?? ""
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            let baseFont = UIFont.preferredFont(forTextStyle: .body)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 2

            view.textStorage.beginEditing()
            view.textStorage.setAttributes(
                [
                    .font: baseFont,
                    .foregroundColor: parent.palette.textUI,
                    .paragraphStyle: paragraph
                ],
                range: fullRange
            )

            for span in MarkdownInlineParser.spans(in: text) {
                switch span.style {
                case let .heading(level):
                    let style: UIFont.TextStyle = level <= 1 ? .largeTitle : (level == 2 ? .title1 : .title2)
                    view.textStorage.addAttributes(
                        [
                            .font: UIFont.systemFont(
                                ofSize: UIFont.preferredFont(forTextStyle: style).pointSize,
                                weight: .bold
                            ),
                            .foregroundColor: parent.palette.textUI
                        ],
                        range: span.fullRange
                    )
                case .bold:
                    view.textStorage.addAttribute(
                        .font,
                        value: symbolicFont(baseFont, trait: .traitBold),
                        range: span.contentRange
                    )
                case .italic:
                    view.textStorage.addAttribute(
                        .font,
                        value: symbolicFont(baseFont, trait: .traitItalic),
                        range: span.contentRange
                    )
                case .code:
                    view.textStorage.addAttributes(
                        [
                            .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular),
                            .backgroundColor: parent.palette.codeBackgroundUI
                        ],
                        range: span.contentRange
                    )
                case .strikethrough:
                    view.textStorage.addAttribute(
                        .strikethroughStyle,
                        value: NSUnderlineStyle.single.rawValue,
                        range: span.contentRange
                    )
                }
                for syntaxRange in span.syntaxRanges {
                    view.textStorage.addAttributes(
                        [
                            .foregroundColor: UIColor.clear,
                            .font: UIFont.systemFont(ofSize: 0.01)
                        ],
                        range: syntaxRange
                    )
                }
            }

            let tasks = MarkdownTaskParser.todoLines(in: text)
            for task in tasks {
                let taskParagraph = paragraph.mutableCopy() as! NSMutableParagraphStyle
                let taskIndent = CGFloat(task.indentColumns) * 7 + 29
                taskParagraph.firstLineHeadIndent = taskIndent
                taskParagraph.headIndent = taskIndent
                view.textStorage.addAttributes(
                    [
                        .foregroundColor: UIColor.clear,
                        .font: UIFont.systemFont(ofSize: 0.01)
                    ],
                    range: task.syntaxRange
                )
                view.textStorage.addAttribute(
                    .paragraphStyle,
                    value: taskParagraph,
                    range: task.lineRange
                )
                if task.isCompleted {
                    view.textStorage.addAttributes(
                        [
                            .foregroundColor: parent.palette.completedTextUI,
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue
                        ],
                        range: task.textRange
                    )
                }
            }

            applyBlockStyles(in: text, to: view, baseFont: baseFont)
            for reference in MarkdownImageReferenceParser.references(in: text) {
                view.textStorage.addAttributes(
                    [
                        .foregroundColor: UIColor.clear,
                        .font: UIFont.systemFont(ofSize: 0.01)
                    ],
                    range: reference.markdownRange
                )
            }
            view.textStorage.endEditing()
            (view as? MarkdownUITextView)?.updateTaskButtons(
                tasks: tasks,
                accentColor: parent.palette.accentUI
            )
            view.selectedRange = selection
            view.tintColor = parent.palette.accentUI
            view.typingAttributes = [
                .font: baseFont,
                .foregroundColor: parent.palette.textUI,
                .paragraphStyle: paragraph
            ]
        }

        private func applyBlockStyles(in text: String, to view: UITextView, baseFont: UIFont) {
            let nsText = text as NSString
            var location = 0
            var insideCodeBlock = false
            while location < nsText.length {
                let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
                let line = nsText.substring(with: lineRange)
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

                if trimmed.hasPrefix("```") {
                    insideCodeBlock.toggle()
                    view.textStorage.addAttribute(
                        .foregroundColor,
                        value: parent.palette.secondaryTextUI,
                        range: lineRange
                    )
                } else if insideCodeBlock {
                    view.textStorage.addAttributes(
                        [
                            .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.92, weight: .regular),
                            .backgroundColor: parent.palette.codeBackgroundUI
                        ],
                        range: lineRange
                    )
                } else if trimmed.hasPrefix(">") {
                    view.textStorage.addAttributes(
                        [
                            .foregroundColor: parent.palette.secondaryTextUI,
                            .obliqueness: 0.12
                        ],
                        range: lineRange
                    )
                } else if trimmed.contains("|") {
                    view.textStorage.addAttribute(
                        .font,
                        value: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular),
                        range: lineRange
                    )
                } else if trimmed == "---" || trimmed == "***" {
                    view.textStorage.addAttribute(
                        .foregroundColor,
                        value: parent.palette.secondaryTextUI,
                        range: lineRange
                    )
                }
                location = NSMaxRange(lineRange)
            }
        }

        private func symbolicFont(_ font: UIFont, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
            guard let descriptor = font.fontDescriptor.withSymbolicTraits(trait) else {
                return font
            }
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingText else { return }
            parent.text = textView.text
            applyPalette(to: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard replacement == "\n",
                  let edit = MarkdownTaskParser.newlineEdit(
                    in: textView.text,
                    selectedRange: range
                  )
            else {
                return true
            }

            apply(edit: edit, to: textView)
            return false
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let textView = recognizer.view as? UITextView
            else { return }

            var point = recognizer.location(in: textView)
            point.x -= textView.textContainerInset.left
            point.y -= textView.textContainerInset.top
            let glyph = textView.layoutManager.glyphIndex(
                for: point,
                in: textView.textContainer
            )
            let character = textView.layoutManager.characterIndexForGlyph(at: glyph)
            let lines = MarkdownTaskParser.todoLines(in: textView.text)
            guard let line = lines.first(where: { NSLocationInRange(character, $0.lineRange) }),
                  point.x <= 46 || NSLocationInRange(character, line.markerRange),
                  let edit = MarkdownTaskParser.toggleEdit(
                    in: textView.text,
                    lineLocation: line.lineRange.location
                  )
            else { return }

            applyToggle(edit, in: textView)
        }

        func toggleTask(at lineLocation: Int, in textView: UITextView) {
            guard let edit = MarkdownTaskParser.toggleEdit(
                in: textView.text,
                lineLocation: lineLocation
            ) else { return }
            applyToggle(edit, in: textView)
        }

        private func applyToggle(_ edit: MarkdownTaskParser.ToggleEdit, in textView: UITextView) {
            let selection = textView.selectedRange
            textView.textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.selectedRange = selection
            parent.text = textView.text
            applyPalette(to: textView)
            UISelectionFeedbackGenerator().selectionChanged()
        }

        func markdownForPastedImage(_ image: UIImage) -> String? {
            do {
                let path = try AttachmentStore.savePastedImage(
                    image,
                    dateKey: parent.dateKey
                )
                return "\n![image](\(path))\n"
            } catch {
                return nil
            }
        }

        func apply(_ command: IOSMarkdownCommand, to textView: UITextView) {
            let selection = textView.selectedRange
            let nsText = textView.text as NSString

            switch command.action {
            case let .insert(value):
                replace(selection, with: value, selectionOffset: (value as NSString).length, in: textView)
            case let .wrap(prefix, suffix, placeholder):
                let selected = selection.length > 0
                    ? nsText.substring(with: selection)
                    : placeholder
                let replacement = prefix + selected + suffix
                let newSelection = NSRange(
                    location: selection.location + (prefix as NSString).length,
                    length: (selected as NSString).length
                )
                replace(selection, with: replacement, selectedRange: newSelection, in: textView)
            case let .prefixLine(prefix):
                let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
                replace(
                    NSRange(location: lineRange.location, length: 0),
                    with: prefix,
                    selectionOffset: (prefix as NSString).length,
                    in: textView
                )
            case .codeBlock:
                let selected = selection.length > 0 ? nsText.substring(with: selection) : "code"
                let replacement = "```\n\(selected)\n```"
                let selectedRange = NSRange(
                    location: selection.location + 4,
                    length: (selected as NSString).length
                )
                replace(selection, with: replacement, selectedRange: selectedRange, in: textView)
            }
        }

        private func apply(edit: MarkdownTaskParser.TextEdit, to textView: UITextView) {
            replace(edit.range, with: edit.replacement, selectedRange: edit.selectedRange, in: textView)
        }

        private func replace(
            _ range: NSRange,
            with replacement: String,
            selectionOffset: Int,
            in textView: UITextView
        ) {
            replace(
                range,
                with: replacement,
                selectedRange: NSRange(
                    location: range.location + selectionOffset,
                    length: 0
                ),
                in: textView
            )
        }

        private func replace(
            _ range: NSRange,
            with replacement: String,
            selectedRange: NSRange,
            in textView: UITextView
        ) {
            textView.textStorage.replaceCharacters(in: range, with: replacement)
            textView.selectedRange = selectedRange
            parent.text = textView.text
            applyPalette(to: textView)
            textView.becomeFirstResponder()
        }
    }
}

private final class MarkdownUITextView: UITextView {
    var onPasteImage: ((UIImage) -> String?)?
    var onToggleTask: ((Int) -> Void)?

    private var taskButtons: [UIButton] = []
    private var taskLines: [MarkdownTaskLine] = []
    private var taskAccentColor = UIColor.systemBlue

    override func paste(_ sender: Any?) {
        if let image = UIPasteboard.general.image,
           let markdown = onPasteImage?(image),
           let selectedTextRange {
            replace(selectedTextRange, withText: markdown)
            delegate?.textViewDidChange?(self)
            return
        }
        super.paste(sender)
    }

    func updateTaskButtons(tasks: [MarkdownTaskLine], accentColor: UIColor) {
        taskLines = tasks
        taskAccentColor = accentColor
        rebuildTaskButtonsIfNeeded()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTaskButtons()
    }

    private func rebuildTaskButtonsIfNeeded() {
        guard taskButtons.count != taskLines.count else {
            for (button, task) in zip(taskButtons, taskLines) {
                configure(button, for: task)
            }
            return
        }

        taskButtons.forEach { $0.removeFromSuperview() }
        taskButtons = taskLines.map { task in
            let button = UIButton(type: .system)
            button.addTarget(self, action: #selector(toggleTask(_:)), for: .touchUpInside)
            addSubview(button)
            configure(button, for: task)
            return button
        }
    }

    private func configure(_ button: UIButton, for task: MarkdownTaskLine) {
        button.tag = task.lineRange.location
        let name = task.isCompleted ? "checkmark.square.fill" : "square"
        button.setImage(UIImage(systemName: name), for: .normal)
        button.tintColor = taskAccentColor
        button.accessibilityLabel = task.isCompleted ? "Completed task" : "Incomplete task"
        button.accessibilityValue = (text as NSString).substring(with: task.textRange)
    }

    private func layoutTaskButtons() {
        layoutManager.ensureLayout(for: textContainer)
        for (button, task) in zip(taskButtons, taskLines) {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: task.syntaxRange,
                actualCharacterRange: nil
            )
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x = textContainerInset.left + CGFloat(task.indentColumns) * 7
            rect.origin.y += textContainerInset.top - 3
            button.frame = CGRect(x: rect.minX, y: rect.minY, width: 25, height: 25)
        }
    }

    @objc private func toggleTask(_ sender: UIButton) {
        onToggleTask?(sender.tag)
    }
}

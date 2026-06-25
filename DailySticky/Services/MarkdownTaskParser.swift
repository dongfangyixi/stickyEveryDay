import Foundation

struct MarkdownTaskLine: Equatable {
    var lineRange: NSRange
    var syntaxRange: NSRange
    var markerRange: NSRange
    var textRange: NSRange
    var isCompleted: Bool
    var indentColumns: Int
    var indentation: String
    var hasWhitespaceAfterMarker: Bool
}

struct MarkdownContinuationLine: Equatable {
    var lineRange: NSRange
    var leadingWhitespaceRange: NSRange
    var taskLine: MarkdownTaskLine
}

enum MarkdownTaskParser {
    private struct ContinuationContext {
        var taskLine: MarkdownTaskLine
        var contentRange: NSRange
        var lineText: String
    }

    struct ToggleEdit: Equatable {
        var range: NSRange
        var replacement: String
    }

    struct TextEdit: Equatable {
        var range: NSRange
        var replacement: String
        var selectedRange: NSRange
    }

    enum IndentDirection {
        case inward
        case outward
    }

    static func todoLines(in text: String) -> [MarkdownTaskLine] {
        let nsText = text as NSString

        guard nsText.length > 0 else {
            return []
        }

        var result: [MarkdownTaskLine] = []
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = contentRangeWithoutNewline(from: lineRange, in: nsText)
            let line = nsText.substring(with: contentRange)

            if let todoLine = parseLine(line, contentLocation: contentRange.location, lineRange: lineRange) {
                result.append(todoLine)
            }

            location = NSMaxRange(lineRange)
        }

        return result
    }

    static func continuationLines(in text: String) -> [MarkdownContinuationLine] {
        let nsText = text as NSString

        guard nsText.length > 0 else {
            return []
        }

        var result: [MarkdownContinuationLine] = []
        var activeTaskLine: MarkdownTaskLine?
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = contentRangeWithoutNewline(from: lineRange, in: nsText)
            let line = nsText.substring(with: contentRange)

            if let taskLine = parseLine(line, contentLocation: contentRange.location, lineRange: lineRange) {
                activeTaskLine = taskLine
                location = NSMaxRange(lineRange)
                continue
            }

            if let taskLine = activeTaskLine, isContinuationLine(line, for: taskLine) {
                result.append(
                    MarkdownContinuationLine(
                        lineRange: lineRange,
                        leadingWhitespaceRange: NSRange(
                            location: contentRange.location,
                            length: min(leadingWhitespaceLength(in: line), contentRange.length)
                        ),
                        taskLine: taskLine
                    )
                )
            } else {
                activeTaskLine = nil
            }

            location = NSMaxRange(lineRange)
        }

        return result
    }

    static func newlineEdit(in text: String, selectedRange: NSRange) -> TextEdit? {
        guard selectedRange.length == 0 else {
            return nil
        }

        let nsText = text as NSString
        if let todoLine = taskLine(at: selectedRange.location, in: nsText),
           selectedRange.location >= todoLine.textRange.location {
            return newTaskEdit(
                at: selectedRange,
                indentation: todoLine.indentation
            )
        }

        guard let context = continuationContext(at: selectedRange.location, in: nsText),
              selectedRange.location == NSMaxRange(context.contentRange)
        else {
            return nil
        }

        let newTaskPrefix = "\(context.taskLine.indentation)- [ ] "
        if context.lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TextEdit(
                range: context.contentRange,
                replacement: newTaskPrefix,
                selectedRange: NSRange(
                    location: context.contentRange.location + (newTaskPrefix as NSString).length,
                    length: 0
                )
            )
        }

        return newTaskEdit(
            at: selectedRange,
            indentation: context.taskLine.indentation
        )
    }

    static func softLineBreakEdit(in text: String, selectedRange: NSRange) -> TextEdit? {
        let nsText = text as NSString
        let replacement: String
        if selectedRange.length == 0,
           let todoLine = taskLine(at: selectedRange.location, in: nsText),
           selectedRange.location >= todoLine.textRange.location {
            replacement = "\n\(continuationIndent(for: todoLine))"
        } else if selectedRange.length == 0,
                  let context = continuationContext(at: selectedRange.location, in: nsText) {
            replacement = "\n\(continuationIndent(for: context.taskLine))"
        } else {
            replacement = "\n"
        }

        return TextEdit(
            range: selectedRange,
            replacement: replacement,
            selectedRange: NSRange(
                location: selectedRange.location + (replacement as NSString).length,
                length: 0
            )
        )
    }

    static func indentationEdit(
        in text: String,
        selectedRange: NSRange,
        direction: IndentDirection
    ) -> TextEdit? {
        guard selectedRange.length == 0 else {
            return nil
        }

        let nsText = text as NSString
        guard let todoLine = taskLine(at: selectedRange.location, in: nsText) else {
            return nil
        }

        switch direction {
        case .inward:
            return TextEdit(
                range: NSRange(location: todoLine.lineRange.location, length: 0),
                replacement: indentUnit,
                selectedRange: NSRange(
                    location: selectedRange.location + (indentUnit as NSString).length,
                    length: 0
                )
            )

        case .outward:
            let removalLength = outdentRemovalLength(from: todoLine.indentation)
            guard removalLength > 0 else {
                return nil
            }

            return TextEdit(
                range: NSRange(location: todoLine.lineRange.location, length: removalLength),
                replacement: "",
                selectedRange: NSRange(
                    location: max(todoLine.lineRange.location, selectedRange.location - removalLength),
                    length: 0
                )
            )
        }
    }

    static func toggleEdit(in text: String, lineLocation: Int) -> ToggleEdit? {
        let nsText = text as NSString

        guard nsText.length > 0, lineLocation >= 0, lineLocation < nsText.length else {
            return nil
        }

        let lineRange = nsText.lineRange(for: NSRange(location: lineLocation, length: 0))
        let contentRange = contentRangeWithoutNewline(from: lineRange, in: nsText)
        let line = nsText.substring(with: contentRange)

        guard let todoLine = parseLine(line, contentLocation: contentRange.location, lineRange: lineRange) else {
            return nil
        }

        let replacement: String
        if todoLine.hasWhitespaceAfterMarker {
            replacement = todoLine.isCompleted ? "[ ]" : "[x]"
        } else {
            replacement = todoLine.isCompleted ? "[ ] " : "[x] "
        }

        return ToggleEdit(
            range: todoLine.markerRange,
            replacement: replacement
        )
    }

    private static func parseLine(
        _ line: String,
        contentLocation: Int,
        lineRange: NSRange
    ) -> MarkdownTaskLine? {
        guard let match = firstMatch(in: line, regex: taskRegex) else {
            return nil
        }

        let nsLine = line as NSString
        let indentRange = match.range(at: 1)
        let syntaxRange = match.range(at: 2)
        let markerRange = match.range(at: 3)
        let bodyRange = match.range(at: 4)
        let marker = nsLine.substring(with: markerRange)
        let syntax = nsLine.substring(with: syntaxRange)

        return MarkdownTaskLine(
            lineRange: lineRange,
            syntaxRange: NSRange(location: contentLocation + syntaxRange.location, length: syntaxRange.length),
            markerRange: NSRange(location: contentLocation + markerRange.location, length: markerRange.length),
            textRange: NSRange(location: contentLocation + bodyRange.location, length: bodyRange.length),
            isCompleted: marker.localizedCaseInsensitiveContains("x"),
            indentColumns: indentColumns(in: nsLine.substring(with: indentRange)),
            indentation: nsLine.substring(with: indentRange),
            hasWhitespaceAfterMarker: syntax.last?.isWhitespace == true
        )
    }

    private static func firstMatch(in line: String, regex: NSRegularExpression) -> NSTextCheckingResult? {
        let range = NSRange(location: 0, length: (line as NSString).length)
        return regex.firstMatch(in: line, range: range)
    }

    private static func taskLine(at location: Int, in nsText: NSString) -> MarkdownTaskLine? {
        guard nsText.length > 0 else {
            return nil
        }

        let lookupLocation = max(0, min(location, nsText.length - 1))
        let lineRange = nsText.lineRange(for: NSRange(location: lookupLocation, length: 0))
        let contentRange = contentRangeWithoutNewline(from: lineRange, in: nsText)
        let line = nsText.substring(with: contentRange)
        return parseLine(line, contentLocation: contentRange.location, lineRange: lineRange)
    }

    private static func newTaskEdit(at selectedRange: NSRange, indentation: String) -> TextEdit {
        let continuation = "\n\(indentation)- [ ] "
        return TextEdit(
            range: selectedRange,
            replacement: continuation,
            selectedRange: NSRange(
                location: selectedRange.location + (continuation as NSString).length,
                length: 0
            )
        )
    }

    private static func continuationContext(at location: Int, in nsText: NSString) -> ContinuationContext? {
        guard nsText.length > 0 else {
            return nil
        }

        let currentLineRange = lineRange(containing: location, in: nsText)
        let currentContentRange = contentRangeWithoutNewline(from: currentLineRange, in: nsText)
        let currentLine = nsText.substring(with: currentContentRange)

        guard parseLine(currentLine, contentLocation: currentContentRange.location, lineRange: currentLineRange) == nil else {
            return nil
        }

        var interveningLines = [currentLine]
        var previousLineEnd = currentLineRange.location

        while previousLineEnd > 0 {
            let previousLineRange = nsText.lineRange(
                for: NSRange(location: previousLineEnd - 1, length: 0)
            )
            let previousContentRange = contentRangeWithoutNewline(from: previousLineRange, in: nsText)
            let previousLine = nsText.substring(with: previousContentRange)

            if let taskLine = parseLine(
                previousLine,
                contentLocation: previousContentRange.location,
                lineRange: previousLineRange
            ) {
                guard interveningLines.allSatisfy({ isContinuationLine($0, for: taskLine) }) else {
                    return nil
                }

                return ContinuationContext(
                    taskLine: taskLine,
                    contentRange: currentContentRange,
                    lineText: currentLine
                )
            }

            interveningLines.append(previousLine)
            previousLineEnd = previousLineRange.location
        }

        return nil
    }

    private static func lineRange(containing location: Int, in nsText: NSString) -> NSRange {
        guard nsText.length > 0 else {
            return NSRange(location: 0, length: 0)
        }

        let boundedLocation = max(0, min(location, nsText.length))
        if boundedLocation == nsText.length,
           boundedLocation > 0,
           isNewline(nsText.character(at: boundedLocation - 1)) {
            return NSRange(location: boundedLocation, length: 0)
        }

        return nsText.lineRange(
            for: NSRange(location: min(boundedLocation, nsText.length - 1), length: 0)
        )
    }

    private static func continuationIndent(for line: MarkdownTaskLine) -> String {
        line.indentation + String(repeating: " ", count: line.syntaxRange.length)
    }

    private static func isContinuationLine(_ line: String, for taskLine: MarkdownTaskLine) -> Bool {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        return line.hasPrefix(continuationIndent(for: taskLine))
    }

    private static func leadingWhitespaceLength(in line: String) -> Int {
        let nsLine = line as NSString
        var length = 0

        while length < nsLine.length {
            let character = nsLine.character(at: length)
            guard character == 9 || character == 32 else {
                break
            }

            length += 1
        }

        return length
    }

    private static func contentRangeWithoutNewline(from lineRange: NSRange, in text: NSString) -> NSRange {
        var length = lineRange.length

        while length > 0 {
            let character = text.character(at: lineRange.location + length - 1)
            guard character == 10 || character == 13 else {
                break
            }

            length -= 1
        }

        return NSRange(location: lineRange.location, length: length)
    }

    private static func isNewline(_ character: unichar) -> Bool {
        character == 10 || character == 13
    }

    private static func indentColumns(in indentation: String) -> Int {
        indentation.reduce(0) { partialResult, character in
            partialResult + (character == "\t" ? 4 : 1)
        }
    }

    private static func outdentRemovalLength(from indentation: String) -> Int {
        guard let firstCharacter = indentation.first else {
            return 0
        }

        if firstCharacter == "\t" {
            return 1
        }

        var removalLength = 0
        for character in indentation {
            guard character == " ", removalLength < (indentUnit as NSString).length else {
                break
            }

            removalLength += 1
        }

        return removalLength
    }

    private static let indentUnit = "    "

    private static let taskRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)((?:[-*+])[ \t]+(\[[ xX]\])[ \t]+)(.*)$"#
    )
}

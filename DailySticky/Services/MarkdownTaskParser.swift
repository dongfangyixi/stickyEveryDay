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

enum MarkdownTaskParser {
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

    static func newlineEdit(in text: String, selectedRange: NSRange) -> TextEdit? {
        guard selectedRange.length == 0 else {
            return nil
        }

        let nsText = text as NSString
        guard let todoLine = taskLine(at: selectedRange.location, in: nsText),
              selectedRange.location >= todoLine.textRange.location
        else {
            return nil
        }

        let continuation = "\n\(todoLine.indentation)- [ ] "
        return TextEdit(
            range: selectedRange,
            replacement: continuation,
            selectedRange: NSRange(
                location: selectedRange.location + (continuation as NSString).length,
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

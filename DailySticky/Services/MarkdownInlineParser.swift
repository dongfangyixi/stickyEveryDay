import Foundation
import Markdown

enum MarkdownInlineStyle: Equatable {
    case heading(level: Int)
    case bold
    case italic
    case code
    case strikethrough
}

struct MarkdownInlineSpan: Equatable {
    var style: MarkdownInlineStyle
    var contentRange: NSRange
    var syntaxRanges: [NSRange]
}

enum MarkdownInlineParser {
    static func spans(in text: String) -> [MarkdownInlineSpan] {
        guard !text.isEmpty else {
            return []
        }

        let document = Document(parsing: text)
        let mapper = MarkdownSourceRangeMapper(text: text)
        var collector = MarkdownInlineSpanCollector(text: text, mapper: mapper)
        collector.visit(document)
        return collector.spans
    }
}

private struct MarkdownInlineSpanCollector: MarkupWalker {
    let text: String
    let mapper: MarkdownSourceRangeMapper
    var spans: [MarkdownInlineSpan] = []

    mutating func visitHeading(_ heading: Heading) {
        addContainerSpan(style: .heading(level: heading.level), markup: heading)
        descendInto(heading)
    }

    mutating func visitStrong(_ strong: Strong) {
        addContainerSpan(style: .bold, markup: strong)
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        addContainerSpan(style: .italic, markup: emphasis)
        descendInto(emphasis)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let fullRange = mapper.nsRange(from: inlineCode.range) else {
            return
        }

        let rawText = (text as NSString).substring(with: fullRange)
        let openingLength = rawText.prefix { $0 == "`" }.count
        let closingLength = rawText.reversed().prefix { $0 == "`" }.count
        let contentLength = max(0, fullRange.length - openingLength - closingLength)

        guard contentLength > 0 else {
            return
        }

        let contentRange = NSRange(
            location: fullRange.location + openingLength,
            length: contentLength
        )
        spans.append(
            MarkdownInlineSpan(
                style: .code,
                contentRange: contentRange,
                syntaxRanges: syntaxRanges(in: fullRange, excluding: contentRange)
            )
        )
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        addContainerSpan(style: .strikethrough, markup: strikethrough)
        descendInto(strikethrough)
    }

    private mutating func addContainerSpan(style: MarkdownInlineStyle, markup: Markup) {
        guard let fullRange = mapper.nsRange(from: markup.range),
              let contentRange = contentRange(for: markup)
        else {
            return
        }

        spans.append(
            MarkdownInlineSpan(
                style: style,
                contentRange: contentRange,
                syntaxRanges: syntaxRanges(in: fullRange, excluding: contentRange)
            )
        )
    }

    private func contentRange(for markup: Markup) -> NSRange? {
        let childRanges = markup.children.compactMap { mapper.nsRange(from: $0.range) }

        guard let firstRange = childRanges.min(by: { $0.location < $1.location }),
              let lastRange = childRanges.max(by: { NSMaxRange($0) < NSMaxRange($1) })
        else {
            return nil
        }

        let location = firstRange.location
        let endLocation = NSMaxRange(lastRange)
        guard endLocation > location else {
            return nil
        }

        return NSRange(location: location, length: endLocation - location)
    }

    private func syntaxRanges(in fullRange: NSRange, excluding contentRange: NSRange) -> [NSRange] {
        var ranges: [NSRange] = []

        if contentRange.location > fullRange.location {
            ranges.append(
                NSRange(
                    location: fullRange.location,
                    length: contentRange.location - fullRange.location
                )
            )
        }

        let contentEnd = NSMaxRange(contentRange)
        let fullEnd = NSMaxRange(fullRange)
        if contentEnd < fullEnd {
            ranges.append(NSRange(location: contentEnd, length: fullEnd - contentEnd))
        }

        return ranges
    }
}

private struct MarkdownSourceRangeMapper {
    private let text: String
    private let lineStartIndices: [String.UTF8View.Index]

    init(text: String) {
        self.text = text
        self.lineStartIndices = Self.lineStartIndices(in: text)
    }

    func nsRange(from sourceRange: SourceRange?) -> NSRange? {
        guard let sourceRange,
              let lowerBound = stringIndex(for: sourceRange.lowerBound),
              let upperBound = stringIndex(for: sourceRange.upperBound),
              lowerBound <= upperBound
        else {
            return nil
        }

        return NSRange(lowerBound..<upperBound, in: text)
    }

    private func stringIndex(for location: SourceLocation) -> String.Index? {
        let lineIndex = location.line - 1
        guard lineIndex >= 0, lineIndex < lineStartIndices.count else {
            return nil
        }

        let columnOffset = max(0, location.column - 1)
        guard let utf8Index = text.utf8.index(
            lineStartIndices[lineIndex],
            offsetBy: columnOffset,
            limitedBy: text.utf8.endIndex
        ) else {
            return nil
        }

        return String.Index(utf8Index, within: text)
    }

    private static func lineStartIndices(in text: String) -> [String.UTF8View.Index] {
        var starts = [text.utf8.startIndex]
        var index = text.utf8.startIndex

        while index < text.utf8.endIndex {
            if text.utf8[index] == 10 {
                starts.append(text.utf8.index(after: index))
            }
            text.utf8.formIndex(after: &index)
        }

        return starts
    }
}

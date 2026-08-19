import CoreGraphics
import Foundation

struct MarkdownImageReference: Equatable, Sendable {
    let altText: String
    let path: String
    let width: CGFloat?
    let markdownRange: NSRange
}

enum MarkdownImageReferenceParser {
    static func reference(in line: String) -> MarkdownImageReference? {
        reference(in: line, offset: 0)
    }

    static func references(in markdown: String) -> [MarkdownImageReference] {
        let text = markdown as NSString
        guard text.length > 0 else {
            return []
        }

        var references: [MarkdownImageReference] = []
        var location = 0
        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            var contentLength = lineRange.length
            while contentLength > 0 {
                let scalar = text.character(at: lineRange.location + contentLength - 1)
                guard scalar == 0x0A || scalar == 0x0D else {
                    break
                }
                contentLength -= 1
            }

            let contentRange = NSRange(location: lineRange.location, length: contentLength)
            let line = text.substring(with: contentRange)
            if let reference = reference(in: line, offset: contentRange.location) {
                references.append(reference)
            }
            location = NSMaxRange(lineRange)
        }
        return references
    }

    private static func reference(in line: String, offset: Int) -> MarkdownImageReference? {
        let text = line as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        guard let match = lineRegex.firstMatch(in: line, range: fullRange),
              match.numberOfRanges >= 3
        else {
            return nil
        }

        let width: CGFloat?
        if match.numberOfRanges >= 4,
           match.range(at: 3).location != NSNotFound {
            width = CGFloat((text.substring(with: match.range(at: 3)) as NSString).doubleValue)
        } else {
            width = nil
        }

        return MarkdownImageReference(
            altText: text.substring(with: match.range(at: 1)),
            path: text.substring(with: match.range(at: 2)),
            width: width,
            markdownRange: NSRange(location: offset, length: fullRange.length)
        )
    }

    static func markdownLine(for reference: MarkdownImageReference, width: CGFloat?) -> String {
        let widthSuffix: String
        if let width {
            widthSuffix = "{width=\(max(1, Int(round(width))))}"
        } else {
            widthSuffix = ""
        }

        return "![\(reference.altText)](\(reference.path))\(widthSuffix)"
    }

    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^!\[([^\]]*)\]\(([^)\s]+)\)(?:\{width=(\d+(?:\.\d+)?)\})?$"#
    )
}

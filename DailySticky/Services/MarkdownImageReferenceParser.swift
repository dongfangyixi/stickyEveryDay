import CoreGraphics
import Foundation

struct MarkdownImageReference: Equatable, Sendable {
    let altText: String
    let path: String
    let width: CGFloat?
}

enum MarkdownImageReferenceParser {
    static func reference(in line: String) -> MarkdownImageReference? {
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
            width: width
        )
    }

    static func references(in markdown: String) -> [MarkdownImageReference] {
        markdown.components(separatedBy: .newlines).compactMap(reference(in:))
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

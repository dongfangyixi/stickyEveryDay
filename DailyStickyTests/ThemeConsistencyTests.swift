import Foundation
import XCTest

final class ThemeConsistencyTests: XCTestCase {
    func testAppControlsDoNotInheritTheSystemAccentColor() throws {
        let sources = try applicationSources()

        let systemAccentViolations = sources.filter {
            $0.contents.contains("NSColor.controlAccentColor")
        }
        XCTAssertTrue(
            systemAccentViolations.isEmpty,
            "Use AppTheme.Palette instead of NSColor.controlAccentColor in: \(paths(in: systemAccentViolations))"
        )

        let implicitBorderedViolations = sources.filter {
            $0.contents.contains(".buttonStyle(.bordered)")
        }
        XCTAssertTrue(
            implicitBorderedViolations.isEmpty,
            "Use a shared Pinaday button style instead of an implicit native bordered style in: \(paths(in: implicitBorderedViolations))"
        )
    }

    func testNativeProminentButtonsUseThePinadayAccent() throws {
        for source in try applicationSources() {
            let lines = source.contents.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated()
                where line.contains(".buttonStyle(.borderedProminent)") {
                let tintWindow = lines[index..<min(index + 4, lines.count)]
                XCTAssertTrue(
                    tintWindow.contains { $0.contains(".tint(palette.accent)") },
                    "Native prominent button must apply palette.accent at \(source.url.path):\(index + 1)"
                )
            }
        }
    }

    private func applicationSources() throws -> [(url: URL, contents: String)] {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = projectRoot.appendingPathComponent("DailySticky", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ) else {
            XCTFail("Could not enumerate application sources at \(sourceRoot.path)")
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else {
                return nil
            }
            return (url, try String(contentsOf: url, encoding: .utf8))
        }
    }

    private func paths(in sources: [(url: URL, contents: String)]) -> String {
        sources.map(\.url.path).joined(separator: ", ")
    }
}

import AppKit
import Foundation
import XCTest
@testable import Pinaday

final class ThemeConsistencyTests: XCTestCase {
    func testNoteZoomPolicyClampsAndStepsPredictably() {
        XCTAssertEqual(NoteZoom.clamped(0.2), 0.6)
        XCTAssertEqual(NoteZoom.clamped(2.4), 2.0)
        XCTAssertEqual(NoteZoom.stepped(1.0, by: NoteZoom.step), 1.1)
        XCTAssertEqual(NoteZoom.stepped(1.0, by: -NoteZoom.step), 0.9)
        XCTAssertEqual(NoteZoom.stepped(1.96, by: NoteZoom.step), 2.0)
    }

    func testLegacySettingsDecodeWithStandardNoteZoom() throws {
        let json = """
        {
          "lastOpenedDateKey": "2026-08-24",
          "isPinned": false,
          "windowFrame": null,
          "theme": "yellow",
          "language": "english",
          "launchAtLogin": false,
          "noteOpacity": 1,
          "hasSeenWelcome": true,
          "storageMode": "localOnly",
          "hasChosenStorageMode": true
        }
        """

        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(settings.noteZoom, NoteZoom.standard)
    }

    func testNoteZoomShortcutsUseConventionalMacBindingsOnly() {
        XCTAssertEqual(
            NoteZoomShortcut.command(
                charactersIgnoringModifiers: "=",
                modifierFlags: .command
            ),
            .zoomIn
        )
        XCTAssertEqual(
            NoteZoomShortcut.command(
                charactersIgnoringModifiers: "+",
                modifierFlags: [.command, .shift]
            ),
            .zoomIn
        )
        XCTAssertEqual(
            NoteZoomShortcut.command(
                charactersIgnoringModifiers: "-",
                modifierFlags: .command
            ),
            .zoomOut
        )
        XCTAssertEqual(
            NoteZoomShortcut.command(
                charactersIgnoringModifiers: "0",
                modifierFlags: .command
            ),
            .actualSize
        )
        XCTAssertNil(
            NoteZoomShortcut.command(
                charactersIgnoringModifiers: "-",
                modifierFlags: []
            )
        )
        XCTAssertNil(
            NoteZoomShortcut.command(
                charactersIgnoringModifiers: "0",
                modifierFlags: [.command, .shift]
            )
        )
    }

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

    func testAppKitScrollViewsUsePinadayScrollerAppearance() throws {
        let rawScrollViewViolations = try applicationSources().filter {
            $0.contents.contains("NSScrollView()")
        }

        XCTAssertTrue(
            rawScrollViewViolations.isEmpty,
            "Use PinadayScrollView so scrollbars follow the app theme in: \(paths(in: rawScrollViewViolations))"
        )

        for (palette, expectedStyle) in [
            (AppTheme.yellow, NSScroller.KnobStyle.dark),
            (AppTheme.light, NSScroller.KnobStyle.dark),
            (AppTheme.dark, NSScroller.KnobStyle.light)
        ] {
            let scrollView = PinadayScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.palette = palette

            XCTAssertEqual(scrollView.verticalScroller?.knobStyle, expectedStyle)
        }
    }

    func testSwiftUIScrollViewsDeclarePinadayNativeAppearance() throws {
        for source in try applicationSources() {
            let scrollViewCount = source.contents
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("ScrollView {") }
                .count
            guard scrollViewCount > 0 else {
                continue
            }

            let appearanceCount = source.contents
                .components(separatedBy: ".pinadayNativeControlAppearance(")
                .count - 1
            XCTAssertGreaterThanOrEqual(
                appearanceCount,
                scrollViewCount,
                "Every SwiftUI ScrollView must explicitly follow the Pinaday theme in \(source.url.path)"
            )
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

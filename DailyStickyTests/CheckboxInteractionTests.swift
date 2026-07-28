import AppKit
import XCTest
@testable import Pinaday

@MainActor
final class CheckboxInteractionTests: XCTestCase {
    func testCheckboxesRemainClickableAndUsePointingHandAfterNaturallyWrappedParagraph() {
        let editor = InlineTodoTextEditorContainer(
            frame: NSRect(x: 0, y: 0, width: 220, height: 320),
            palette: AppTheme.yellow,
            dateKey: "2026-07-28"
        )
        let window = NSWindow(
            contentRect: editor.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = editor
        editor.setText(
            """
            This is one logical line whose text is intentionally long enough to wrap across several visual lines in a narrow note window.
            - [ ] first task
            - [ ] second task
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(editor.visualFragmentCountForTesting(lineIndex: 0), 1)
        XCTAssertTrue(editor.checkboxUsesPointingHandCursorForTesting(lineIndex: 1))
        XCTAssertTrue(editor.checkboxUsesPointingHandCursorForTesting(lineIndex: 2))

        XCTAssertTrue(
            editor.checkboxRespondsToClickForTesting(lineIndex: 1),
            editor.checkboxDiagnosticsForTesting(lineIndex: 1)
        )
        XCTAssertTrue(editor.text.contains("- [x] first task"))

        XCTAssertTrue(
            editor.checkboxRespondsToClickForTesting(lineIndex: 2),
            editor.checkboxDiagnosticsForTesting(lineIndex: 2)
        )
        XCTAssertTrue(editor.text.contains("- [x] second task"))
    }
}

import AppKit
import XCTest
@testable import Pinaday

@MainActor
final class CheckboxInteractionTests: XCTestCase {
    func testPastingTaskIntoBlankLinePreservesFollowingTaskIdentity() {
        let (editor, window) = makeEditor()
        editor.setText(
            """
            - [ ] item1
            - [ ] item2
            - [ ] item2

            - [ ] item3
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(editor.pasteMarkdownForTesting("- [ ] inserted", atLine: 3))
        XCTAssertEqual(
            editor.text,
            """
            - [ ] item1
            - [ ] item2
            - [ ] item2
            - [ ] inserted
            - [ ] item3
            """
        )
        XCTAssertTrue(editor.checkboxRespondsToClickForTesting(lineIndex: 3))
        XCTAssertTrue(editor.text.contains("- [x] inserted"))
        XCTAssertTrue(editor.checkboxRespondsToClickForTesting(lineIndex: 4))
        XCTAssertTrue(editor.text.contains("- [x] item3"))
    }

    func testPastingTaskIntoInteractivelyCreatedBlankLinePreservesFollowingTask() {
        let (editor, window) = makeEditor()
        editor.setText("")
        editor.typeTextForTesting("- [ ] before")
        editor.pressReturnForTesting()
        editor.pressReturnForTesting()
        editor.pressReturnForTesting()
        editor.typeTextForTesting("- [ ] after")
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            editor.text,
            """
            - [ ] before

            - [ ] after
            """
        )
        XCTAssertTrue(editor.pasteMarkdownForTesting("- [ ] pasted", atLine: 1))
        XCTAssertEqual(
            editor.text,
            """
            - [ ] before
            - [ ] pasted
            - [ ] after
            """
        )
        XCTAssertTrue(editor.checkboxRespondsToClickForTesting(lineIndex: 1))
        XCTAssertTrue(editor.checkboxRespondsToClickForTesting(lineIndex: 2))
    }

    func testPastingTaskAndNewlineBeforeExistingTaskKeepsBothCheckboxes() {
        let (editor, window) = makeEditor()
        editor.setText(
            """
            - [ ] before
            - [ ] after
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(editor.pasteMarkdownForTesting("- [ ] inserted\n", atLine: 1))
        XCTAssertEqual(
            editor.text,
            """
            - [ ] before
            - [ ] inserted
            - [ ] after
            """
        )
        XCTAssertTrue(editor.checkboxRespondsToClickForTesting(lineIndex: 1))
        XCTAssertTrue(editor.checkboxRespondsToClickForTesting(lineIndex: 2))
        XCTAssertEqual(
            editor.text,
            """
            - [ ] before
            - [x] inserted
            - [x] after
            """
        )
    }

    func testCheckboxesRemainClickableAndUsePointingHandAfterNaturallyWrappedParagraph() {
        let (editor, window) = makeEditor()
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

    func testCaretHitTestingRemainsAlignedAcrossEditedBulletAndNumberedLines() {
        let (editor, window) = makeEditor()
        editor.setText(
            """
            What I added
            1. Chat File (Temporary) => Chat Uploads (later we can add mouse over messages).
            2. AI Workspace => Agent Outputs

            What is left:
            - For External Connectors: change database connections to general connections including gmail, drive, etc
            - MCP Servers should be entirely hidden from users.
            - Project => we need to decide later where to place it.
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 1, utf16Offset: 12), 25)
        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 2, utf16Offset: 5), 96)
        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 5, utf16Offset: 10), 146)
        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 6, utf16Offset: 8), 248)
        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 7, utf16Offset: 7), 297)

        XCTAssertTrue(editor.typeTextForTesting(" updated", atLine: 6, utf16Offset: 49))
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 6, utf16Offset: 8), 248)
        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 7, utf16Offset: 7), 305)
        XCTAssertTrue(editor.selectionDisplayRefreshIsDeferredDuringMouseTrackingForTesting())
    }

    func testExplicitImageWidthCanGrowBeyondAutomaticPreviewHeightCap() {
        let (editor, _) = makeEditor()
        let imageSize = NSSize(width: 1600, height: 960)

        XCTAssertEqual(
            editor.imagePreviewSizeForTesting(
                imageSize: imageSize,
                availableWidth: 1000,
                explicitWidth: nil
            ),
            NSSize(width: 600, height: 360)
        )
        XCTAssertEqual(
            editor.imagePreviewSizeForTesting(
                imageSize: imageSize,
                availableWidth: 1000,
                explicitWidth: 738
            ),
            NSSize(width: 738, height: 442)
        )
        XCTAssertEqual(
            editor.imagePreviewSizeForTesting(
                imageSize: imageSize,
                availableWidth: 1000,
                explicitWidth: 1400
            ),
            NSSize(width: 1000, height: 600)
        )
    }

    private func makeEditor() -> (InlineTodoTextEditorContainer, NSWindow) {
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
        editor.layoutSubtreeIfNeeded()
        return (editor, window)
    }
}

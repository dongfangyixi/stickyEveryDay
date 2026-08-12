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

        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 1, utf16Offset: 12), 28)
        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 2, utf16Offset: 5), 102)
        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 5, utf16Offset: 10), 152)
        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 6, utf16Offset: 8), 254)
        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 7, utf16Offset: 7), 303)

        XCTAssertTrue(editor.typeTextForTesting(" updated", atLine: 6, utf16Offset: 49))
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 6, utf16Offset: 8), 254)
        XCTAssertEqual(editor.caretLocationForTesting(lineIndex: 7, utf16Offset: 7), 311)
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

    func testDeletingMiddleNumberedItemRenumbersFollowingItems() {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            1. one
            2. two
            3. three
            4. four
            """
        )

        XCTAssertTrue(editor.deleteLineForTesting(lineIndex: 1))
        XCTAssertEqual(
            editor.text,
            """
            1. one
            2. three
            3. four
            """
        )
    }

    func testDeletingMiddleNestedNumberedItemRenumbersItsLevelOnly() {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            1. first parent
                1. first child
                2. removed child
                3. remaining child
            2. second parent
                1. second parent child
            """
        )

        XCTAssertTrue(editor.deleteLineForTesting(lineIndex: 2))
        XCTAssertEqual(
            editor.text,
            """
            1. first parent
                1. first child
                2. remaining child
            2. second parent
                1. second parent child
            """
        )
    }

    func testNumberedPrefixParticipatesInNativeCharacterSelection() throws {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            1. one
            2. merge
            """
        )

        let firstPrefix = try XCTUnwrap(editor.numberedPrefixRangeForTesting(lineIndex: 0))
        editor.extendSelectionRightForTesting(from: firstPrefix.location + 1)
        XCTAssertEqual(editor.selectedTextForTesting, ".")
        XCTAssertEqual(editor.copySelectionForTesting(), ".")

        let secondPrefix = try XCTUnwrap(editor.numberedPrefixRangeForTesting(lineIndex: 1))
        editor.selectRangeForTesting(
            NSRange(
                location: firstPrefix.location + 1,
                length: NSMaxRange(secondPrefix) - firstPrefix.location - 1
            )
        )
        XCTAssertEqual(editor.copySelectionForTesting(), ". one\n2. ")
    }

    func testNumberedPrefixGlyphsParticipateInNativeMouseHitTesting() throws {
        let (editor, window) = makeEditor()
        editor.setText("1. selectable")
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        let prefixRange = try XCTUnwrap(editor.numberedPrefixRangeForTesting(lineIndex: 0))

        let numberLocation = try XCTUnwrap(
            editor.insertionLocationAtNumberedPrefixCharacterForTesting(
                lineIndex: 0,
                characterOffset: 0
            )
        )
        let periodLocation = try XCTUnwrap(
            editor.insertionLocationAtNumberedPrefixCharacterForTesting(
                lineIndex: 0,
                characterOffset: 1
            )
        )

        XCTAssertTrue(NSLocationInRange(numberLocation, prefixRange))
        XCTAssertTrue(NSLocationInRange(periodLocation, prefixRange))
    }

    func testSelectingOnlyNumberedContentDoesNotCopyItsPrefix() throws {
        let (editor, _) = makeEditor()
        editor.setText("1. merge")

        let contentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        editor.selectRangeForTesting(contentRange)

        XCTAssertEqual(editor.selectedTextForTesting, "merge")
        XCTAssertEqual(editor.copySelectionForTesting(), "merge")
    }

    func testCopyingAcrossNumberedAndTaskLinesPreservesEachVisibleStructure() throws {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            1. first
            - [ ] task
            """
        )

        let numberedPrefix = try XCTUnwrap(editor.numberedPrefixRangeForTesting(lineIndex: 0))
        let taskContent = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 1))
        editor.selectRangeForTesting(
            NSRange(
                location: numberedPrefix.location + 1,
                length: NSMaxRange(taskContent) - numberedPrefix.location - 1
            )
        )

        XCTAssertEqual(editor.copySelectionForTesting(), ". first\n- [ ] task")
    }

    func testSelectingAllStillCopiesCanonicalNumberedMarkdown() {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            1. one
                1. nested
            2. two
            """
        )
        editor.selectAllForTesting()

        XCTAssertEqual(editor.selectedRangeForTesting.location, 0)
        XCTAssertEqual(
            editor.selectedRangeForTesting.length,
            (editor.presentationTextForTesting as NSString).length
        )
        XCTAssertEqual(
            editor.copySelectionForTesting(),
            """
            1. one
                1. nested
            2. two
            """
        )
    }

    func testDeletingNumberedPrefixDoesNotDeleteItsContentOrStructure() throws {
        let (editor, _) = makeEditor()
        editor.setText("1. one")
        let prefixRange = try XCTUnwrap(editor.numberedPrefixRangeForTesting(lineIndex: 0))

        editor.selectRangeForTesting(prefixRange)
        editor.deleteSelectionForTesting()

        XCTAssertEqual(editor.text, "1. one")
        XCTAssertEqual(editor.presentationTextForTesting, "1. one")
    }

    func testDeletingNumberedPrefixPreservesContentThatAlsoStartsWithANumber() throws {
        let (editor, _) = makeEditor()
        editor.setText("1. 1. content marker")
        let prefixRange = try XCTUnwrap(editor.numberedPrefixRangeForTesting(lineIndex: 0))

        editor.selectRangeForTesting(prefixRange)
        editor.deleteSelectionForTesting()

        XCTAssertEqual(editor.text, "1. 1. content marker")
        XCTAssertEqual(editor.presentationTextForTesting, "1. 1. content marker")
    }

    func testDeletingOnlyNumberedPrefixSeparatorPreservesGeneratedMarker() throws {
        let (editor, _) = makeEditor()
        editor.setText("1. content")
        let prefixRange = try XCTUnwrap(editor.numberedPrefixRangeForTesting(lineIndex: 0))

        editor.selectRangeForTesting(NSRange(location: NSMaxRange(prefixRange) - 1, length: 1))
        editor.deleteSelectionForTesting()

        XCTAssertEqual(editor.text, "1. content")
        XCTAssertEqual(editor.presentationTextForTesting, "1. content")
    }

    func testReturnInNumberedListCreatesAndRenumbersNativePrefixes() throws {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            1. one
            2. two
            """
        )
        let firstContent = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        editor.selectRangeForTesting(NSRange(location: NSMaxRange(firstContent), length: 0))

        editor.pressReturnForTesting()

        XCTAssertEqual(editor.text, "1. one\n2. \n3. two")
        XCTAssertEqual(editor.presentationTextForTesting, "1. one\n2. \n3. two")
    }

    func testNestedNumberedMarkersUseNativeHierarchicalPresentation() {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            1. parent
                1. child
                    1. grandchild
            """
        )

        XCTAssertEqual(editor.presentationTextForTesting, "1. parent\na. child\ni. grandchild")
        XCTAssertEqual(
            editor.text,
            """
            1. parent
                1. child
                    1. grandchild
            """
        )
    }

    func testIndentingPartialNumberedSelectionPreservesSelectedCharacters() throws {
        let (editor, _) = makeEditor()
        editor.setText("1. numbered content")
        let contentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        let selectedRange = NSRange(location: contentRange.location + 3, length: 8)
        editor.selectRangeForTesting(selectedRange)
        let selectedText = editor.selectedTextForTesting

        editor.pressTabForTesting()

        XCTAssertEqual(editor.selectedTextForTesting, selectedText)
        XCTAssertEqual(editor.selectedRangeForTesting.length, selectedRange.length)
        XCTAssertEqual(editor.presentationTextForTesting, "a. numbered content")
        XCTAssertEqual(editor.text, "    1. numbered content")
    }

    func testTypingInNumberedContentPreservesMarkerAndMarkdown() throws {
        let (editor, _) = makeEditor()
        editor.setText("1. one")
        let contentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        editor.selectRangeForTesting(NSRange(location: NSMaxRange(contentRange), length: 0))

        editor.typeTextForTesting(" more")

        XCTAssertEqual(editor.presentationTextForTesting, "1. one more")
        XCTAssertEqual(editor.text, "1. one more")
    }

    func testBackspaceAtNumberedContentStartRemovesListStructureCleanly() throws {
        let (editor, _) = makeEditor()
        editor.setText("1. one")
        let contentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        editor.selectRangeForTesting(NSRange(location: contentRange.location, length: 0))

        editor.pressBackspaceForTesting()

        XCTAssertEqual(editor.presentationTextForTesting, "one")
        XCTAssertEqual(editor.text, "one")
    }

    func testReturnOnEmptyNumberedItemLeavesAPlainEmptyLine() throws {
        let (editor, _) = makeEditor()
        editor.setText("1. ")
        let contentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        editor.selectRangeForTesting(NSRange(location: contentRange.location, length: 0))

        editor.pressReturnForTesting()

        XCTAssertEqual(editor.presentationTextForTesting, "")
        XCTAssertEqual(editor.text, "")
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

import AppKit
import XCTest
@testable import Pinaday

@MainActor
final class CheckboxInteractionTests: XCTestCase {
    func testCodeBlockLayoutIsStableAndDoesNotOverlapNeighboringLines() throws {
        let (editor, window) = makeEditor()
        editor.setText(
            """
            before
            ```swift

            ```
            after
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let emptyFrame = try XCTUnwrap(editor.codeBlockFramesForTesting().first)
        let beforeFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 0))
        let afterFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 2))
        XCTAssertGreaterThanOrEqual(emptyFrame.minY, beforeFrame.maxY - 0.5)
        XCTAssertLessThanOrEqual(emptyFrame.maxY, afterFrame.minY + 0.5)

        editor.setText(
            """
            before
            ```swift
            let value = 1
            ```
            after
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let populatedFrame = try XCTUnwrap(editor.codeBlockFramesForTesting().first)
        let populatedBeforeFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 0))
        let populatedAfterFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 2))
        XCTAssertEqual(populatedFrame.height, emptyFrame.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(populatedFrame.minY, populatedBeforeFrame.maxY - 0.5)
        XCTAssertLessThanOrEqual(populatedFrame.maxY, populatedAfterFrame.minY + 0.5)
    }

    func testSlashCommandMatchingPrefersCodeNameOverTodoAlias() {
        let (editor, _) = makeEditor()

        XCTAssertEqual(editor.slashCommandRawValueForTesting(query: "c"), "codeBlock")
        XCTAssertEqual(editor.slashCommandRawValueForTesting(query: "co"), "codeBlock")
        XCTAssertEqual(editor.slashCommandRawValueForTesting(query: "code"), "codeBlock")
        XCTAssertEqual(editor.slashCommandRawValueForTesting(query: "t"), "todo")
        XCTAssertEqual(editor.slashCommandRawValueForTesting(query: "check"), "todo")
        XCTAssertEqual(editor.slashCommandRawValueForTesting(query: "div"), "divider")
    }

    func testChangingCodeLanguageUpdatesTheWholeBlockAndMarkdownFence() {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            ```swift
            let first = 1
            let second = 2
            ```
            """
        )

        XCTAssertTrue(editor.setCodeLanguageForTesting("go", atLine: 1))
        XCTAssertEqual(editor.codeBlockLanguagesForTesting, ["go", "go"])
        XCTAssertTrue(editor.text.hasPrefix("```go\n"))
    }

    func testCodeLanguageChipIsReachableWithAButtonCursor() {
        let (editor, window) = makeEditor()
        editor.setText(
            """
            ```swift
            let value = 1
            ```
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        XCTAssertTrue(editor.codeLanguageControlRespondsToHitTestingForTesting())
    }

    func testLinesAfterCodeBlockRemainMouseInteractiveInScrollableEditor() {
        let editor = InlineTodoTextEditorContainer(
            frame: NSRect(x: 0, y: 0, width: 220, height: 120),
            palette: AppTheme.yellow,
            dateKey: "2026-08-20"
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
            before
            ```python
            import abc from b
            run b with a
            ```

            first
            second
            third

            fourth
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let geometry = editor.textDocumentGeometryForTesting
        XCTAssertGreaterThanOrEqual(
            geometry.frame.height,
            geometry.usedRect.maxY,
            "The text view must contain every line that AppKit draws"
        )
        for lineIndex in 3...8 {
            XCTAssertTrue(
                editor.mouseCanPlaceCaretForTesting(lineIndex: lineIndex, utf16Offset: 0),
                "Line \(lineIndex) must remain reachable through real view hit testing"
            )
        }
    }

    func testEmptyCodeBlockDoesNotMoveWhenFirstTextIsTyped() throws {
        let (editor, window) = makeEditor()
        editor.setText(
            """
            before
            ```python

            ```
            after
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let emptyFrame = try XCTUnwrap(editor.codeBlockFramesForTesting().first)
        let emptyLineFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 1))

        XCTAssertTrue(editor.typeTextForTesting("print('hello')", atLine: 1, utf16Offset: 0))
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let populatedFrame = try XCTUnwrap(editor.codeBlockFramesForTesting().first)
        let populatedLineFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 1))
        XCTAssertEqual(populatedFrame.minY, emptyFrame.minY, accuracy: 0.5)
        XCTAssertEqual(populatedFrame.maxY, emptyFrame.maxY, accuracy: 0.5)
        XCTAssertEqual(populatedLineFrame.minY, emptyLineFrame.minY, accuracy: 0.5)
        XCTAssertEqual(populatedLineFrame.maxY, emptyLineFrame.maxY, accuracy: 0.5)
    }

    func testFinalEmptyCodeBlockCreatedFromSlashDoesNotMoveWhenFirstTextIsTyped() throws {
        let (editor, window) = makeEditor()
        editor.setText("")
        editor.typeTextForTesting("/c")
        editor.pressReturnForTesting()
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let emptyFrame = try XCTUnwrap(editor.codeBlockFramesForTesting().first)
        let emptyLineFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 0))

        editor.typeTextForTesting("print('hello')")
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let populatedFrame = try XCTUnwrap(editor.codeBlockFramesForTesting().first)
        let populatedLineFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 0))
        XCTAssertEqual(populatedFrame.minY, emptyFrame.minY, accuracy: 0.5)
        XCTAssertEqual(populatedFrame.maxY, emptyFrame.maxY, accuracy: 0.5)
        XCTAssertEqual(populatedLineFrame.minY, emptyLineFrame.minY, accuracy: 0.5)
        XCTAssertEqual(populatedLineFrame.maxY, emptyLineFrame.maxY, accuracy: 0.5)
    }

    func testIncrementalCodeBlockEditingKeepsFollowingLinesMouseInteractive() {
        let editor = InlineTodoTextEditorContainer(
            frame: NSRect(x: 0, y: 0, width: 220, height: 150),
            palette: AppTheme.yellow,
            dateKey: "2026-08-20"
        )
        let window = NSWindow(
            contentRect: editor.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = editor
        editor.setText("")
        editor.typeTextForTesting("sfd\n```python\nimport abc from b\nrun b with a\n```\n\ndsf\nsdf\nsdf\n\nsdf")
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let geometry = editor.textDocumentGeometryForTesting
        XCTAssertGreaterThanOrEqual(geometry.frame.height, geometry.usedRect.maxY)
        for lineIndex in 3...8 {
            XCTAssertTrue(
                editor.mouseCanPlaceCaretForTesting(lineIndex: lineIndex, utf16Offset: 0),
                "The leading edge of line \(lineIndex) must accept mouse placement"
            )
            XCTAssertTrue(
                editor.mouseCanPlaceCaretForTesting(lineIndex: lineIndex, utf16Offset: 2),
                "The text of line \(lineIndex) must accept mouse placement"
            )
        }
    }

    func testNormalLineBetweenCodeBlocksHasVisibleMargins() throws {
        let (editor, window) = makeEditor()
        editor.setText(
            """
            ```swift
            first
            ```
            middle
            ```swift
            second
            ```
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let codeFrames = editor.codeBlockFramesForTesting()
        XCTAssertEqual(codeFrames.count, 2)
        let firstCodeFrame = try XCTUnwrap(codeFrames.first)
        let secondCodeFrame = try XCTUnwrap(codeFrames.last)
        let firstCodeLineFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 0))
        let middleLineFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 1))

        XCTAssertLessThanOrEqual(
            firstCodeFrame.maxY + 3,
            middleLineFrame.minY,
            "The first code block must leave a visible margin before the normal line. "
                + "code=\(firstCodeFrame), codeLine=\(firstCodeLineFrame), line=\(middleLineFrame)"
        )
        XCTAssertLessThanOrEqual(
            middleLineFrame.maxY + 3,
            secondCodeFrame.minY,
            "The second code block must leave a visible margin after the normal line. "
                + "line=\(middleLineFrame), code=\(secondCodeFrame)"
        )
    }

    func testMouseCanPlaceCaretAndDragSelectionAcrossLinesAfterCodeBlock() {
        let editor = InlineTodoTextEditorContainer(
            frame: NSRect(x: 0, y: 0, width: 220, height: 150),
            palette: AppTheme.yellow,
            dateKey: "2026-08-20"
        )
        let window = NSWindow(
            contentRect: editor.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer { window.close() }
        window.contentView = editor
        editor.setText(
            """
            before
            ```python
            import abc from b
            run b with a
            ```

            first
            second
            third

            fourth
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        XCTAssertTrue(editor.mouseCanPlaceCaretForTesting(lineIndex: 8, utf16Offset: 2))
        XCTAssertTrue(editor.dragSelectWithMouseEventsForTesting(
            fromLine: 5,
            utf16Offset: 0,
            toLine: 8,
            utf16EndOffset: 3
        ))
        XCTAssertTrue(editor.selectedTextForTesting.contains("second"))
        XCTAssertTrue(editor.selectedTextForTesting.contains("third"))
    }

    func testTrailingLinesRemainInteractiveWhenCodeBlockIsBuiltLineByLine() {
        let (editor, window) = makeEditor()
        editor.setText("")
        editor.typeTextForTesting("sfd")
        editor.pressReturnForTesting()
        editor.typeTextForTesting("```python")
        editor.pressReturnForTesting()
        editor.typeTextForTesting("import abc from b")
        editor.pressReturnForTesting()
        editor.typeTextForTesting("run b with a")
        editor.pressReturnForTesting()
        editor.typeTextForTesting("```")
        editor.pressReturnForTesting()
        editor.pressReturnForTesting()
        let trailingLines = ["dsf", "sdf", "sdf", "", "sdf"]
        for (index, text) in trailingLines.enumerated() {
            editor.typeTextForTesting(text)
            if index < trailingLines.count - 1 {
                editor.pressReturnForTesting()
            }
        }
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let lines = editor.presentationTextForTesting.components(separatedBy: "\n")
        let geometry = editor.textDocumentGeometryForTesting
        XCTAssertGreaterThanOrEqual(geometry.frame.height, geometry.usedRect.maxY)
        for lineIndex in max(0, lines.count - 5)..<lines.count {
            XCTAssertTrue(
                editor.mouseCanPlaceCaretForTesting(lineIndex: lineIndex, utf16Offset: 0),
                "Incrementally created trailing line \(lineIndex) must accept a mouse click"
            )
        }
    }

    func testLoadingLanguageTaggedAndPlainEmptyFencesCreatesCodeBlocks() {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            ```python
            ```

            ```
            ```
            """
        )

        XCTAssertFalse(editor.presentationTextForTesting.contains("```"))
        XCTAssertEqual(editor.codeBlockLanguagesForTesting, ["python", nil])
        XCTAssertTrue(editor.text.contains("```python\n\n```"))
    }

    func testPastingFencedMarkdownUsesStructuredCodeBlockPresentation() {
        let (editor, _) = makeEditor()
        editor.setText("")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            """
            ```go
            fmt.Println("hello")
            ```
            """,
            forType: .string
        )

        editor.pasteFromGeneralPasteboardForTesting()

        XCTAssertEqual(editor.presentationTextForTesting, "fmt.Println(\"hello\")")
        XCTAssertEqual(editor.codeBlockLanguagesForTesting, ["go"])
        XCTAssertEqual(
            editor.text,
            """
            ```go
            fmt.Println("hello")
            ```
            """
        )
    }

    func testReturnPromotesTypedLanguageFenceAndBareFenceClosesBlock() {
        let (editor, _) = makeEditor()
        editor.setText("")

        editor.typeTextForTesting("```python")
        editor.pressReturnForTesting()

        XCTAssertEqual(editor.presentationTextForTesting, "")
        XCTAssertEqual(editor.codeBlockLanguagesForTesting, ["python"])

        editor.typeTextForTesting("print('hello')")
        editor.pressReturnForTesting()
        editor.typeTextForTesting("```")
        editor.pressReturnForTesting()

        XCTAssertEqual(editor.presentationTextForTesting, "print('hello')\n")
        XCTAssertEqual(editor.codeBlockLanguagesForTesting, ["python"])
        XCTAssertEqual(
            editor.text,
            """
            ```python
            print('hello')
            ```

            """
        )
    }

    func testCopyingAnImagePublishesImageDataWithoutMarkdownText() {
        let (editor, _) = makeEditor()
        let image = NSImage(size: NSSize(width: 24, height: 18))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()

        XCTAssertTrue(editor.copyImageForTesting(image))
        XCTAssertNotNil(NSPasteboard.general.data(forType: .png))
        XCTAssertNotNil(NSPasteboard.general.data(forType: .tiff))
        XCTAssertNil(NSPasteboard.general.string(forType: .string))
    }

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

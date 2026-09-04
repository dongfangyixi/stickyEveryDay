import AppKit
import XCTest
@testable import Pinaday

@MainActor
final class CheckboxInteractionTests: XCTestCase {
    func testDateNavigationFocusPolicyTargetsOnlyEmptyDestinationNotes() {
        XCTAssertTrue(
            NoteNavigationFocusPolicy.shouldFocusEditor(
                previousDateKey: "2026-09-01",
                destinationDateKey: "2026-09-02",
                noteText: ""
            )
        )
        XCTAssertFalse(
            NoteNavigationFocusPolicy.shouldFocusEditor(
                previousDateKey: "2026-09-01",
                destinationDateKey: "2026-09-02",
                noteText: "existing note"
            )
        )
        XCTAssertFalse(
            NoteNavigationFocusPolicy.shouldFocusEditor(
                previousDateKey: "2026-09-01",
                destinationDateKey: "2026-09-01",
                noteText: ""
            )
        )
    }

    func testEmptyNoteFocusPlacesCaretAtStartWithoutFocusingExistingNote() {
        let (editor, window) = makeEditor()
        XCTAssertTrue(editor.focusEmptyNoteAtStart())
        XCTAssertTrue(editor.isTextEditorFirstResponderForTesting)
        XCTAssertEqual(editor.selectedRangeForTesting, NSRange(location: 0, length: 0))

        editor.setText("existing note")
        _ = window.makeFirstResponder(nil)

        XCTAssertFalse(editor.focusEmptyNoteAtStart())
        XCTAssertFalse(editor.isTextEditorFirstResponderForTesting)
    }

    func testSlashNumberedListSplitsCodeBlockWithoutBreakingLowerMouseHits() throws {
        let (editor, _, _, lowerCodeLineIndex) = try makeScrolledSplitCodeBlockEditor()
        XCTAssertTrue(
            editor.isSlashCommandPaletteHiddenForTesting,
            "Applying the slash command must remove its menu from hit testing"
        )
        XCTAssertTrue(
            editor.clickLineWithWindowEventForTesting(
                lineIndex: lowerCodeLineIndex,
                utf16Offset: 2
            ),
            "A real mouse event must reach the visible lower code block after the split. "
                + editor.lineGeometryDescriptionForTesting(lineIndex: lowerCodeLineIndex)
                + " "
                + editor.interactionGeometryDescriptionForTesting(lineIndex: lowerCodeLineIndex)
        )
    }

    func testSlashNumberedListSplitKeepsNumberedLineMouseReachable() throws {
        let (editor, _, splitLineIndex, _) = try makeScrolledSplitCodeBlockEditor()
        XCTAssertTrue(
            editor.clickLineWithWindowEventForTesting(
                lineIndex: splitLineIndex,
                utf16Offset: 0
            ),
            "A real mouse event must reach the numbered line created by the split. "
                + editor.lineGeometryDescriptionForTesting(lineIndex: splitLineIndex)
                + " "
                + editor.interactionGeometryDescriptionForTesting(lineIndex: splitLineIndex)
        )
        editor.typeTextForTesting("item")
        XCTAssertEqual(
            editor.presentationTextForTesting.components(separatedBy: "\n")[splitLineIndex],
            "1. item",
            "Typing after the click must edit the numbered line, not the previous focus"
        )
    }

    func testAug25MixedStructuredNoteKeepsNumberedAndFinalCodeLinesMouseReachable() throws {
        let (editor, window) = makeEditor()
        window.setContentSize(NSSize(width: 620, height: 1_500))
        editor.setText(
            """
            ```python
            import tensorflow as tf
            def add(a, b):
                return a + b

            ```






            ```
            dsdf

            ```
            sdfsdf
            dsfsdfsdfsdf
            ```

            ```
            dfsaddfsf
            ```
            sdf
            dsf
            abc
            ```
            - [ ] sdklfjkl
            ```
            sdfsdf
            sdf
            ```
            1.\u{20}
            ```
            dsfs
            /
            sdf
            sdf
            /
            ```
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let lines = editor.presentationTextForTesting.components(separatedBy: "\n")
        let numberedLine = try XCTUnwrap(lines.firstIndex(where: { $0.hasPrefix("1. ") }))
        let finalCodeLine = try XCTUnwrap(editor.codeBlockLineIndicesForTesting.last)

        XCTAssertTrue(
            editor.mouseCanPlaceCaretWithoutScrollingForTesting(
                lineIndex: numberedLine,
                utf16Offset: 0
            ),
            "The empty numbered item must accept a direct click"
        )
        XCTAssertTrue(
            editor.mouseCanPlaceCaretWithoutScrollingForTesting(
                lineIndex: finalCodeLine,
                utf16Offset: 0
            ),
            "The final code line must accept a direct click"
        )
    }

    func testProgrammaticStructuredExpansionKeepsLowerLinesMouseReachable() {
        let (editor, window) = makeEditor()
        window.setContentSize(NSSize(width: 220, height: 800))
        editor.layoutSubtreeIfNeeded()
        editor.setText("short note")
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        editor.setText(
            """
            ```python
            import tensorflow as tf
            def add(a, b):
                return a + b
            ```






            ```
            first block
            ```
            normal one
            normal two
            ```
            second block
            line two
            ```
            - [ ] task
            ```
            third block
            line two
            ```
            1.\u{20}
            ```
            final block
            /
            final line
            ```
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let geometry = editor.textDocumentGeometryForTesting
        XCTAssertGreaterThanOrEqual(
            geometry.frame.height,
            geometry.usedRect.maxY,
            "Programmatic updates must resize the interactive NSTextView document"
        )
        for lineIndex in editor.codeBlockLineIndicesForTesting.suffix(4) {
            XCTAssertTrue(
                editor.mouseCanPlaceCaretWithoutScrollingForTesting(
                    lineIndex: lineIndex,
                    utf16Offset: 0
                ),
                "Lower code line \(lineIndex) must accept a direct click after programmatic expansion"
            )
        }
    }

    func testMiddleListPromotionKeepsEveryLowerLineMouseReachable() throws {
        let (editor, window) = makeEditor()
        window.setContentSize(NSSize(width: 220, height: 900))
        editor.setText(
            """
            ```python
            import tensorflow as tf
            def add(a, b):
                return a + b
            ```

            ```
            first block
            ```
            normal one
            normal two
            ```
            second block
            line two
            ```
            - [ ] task
            ```
            third block
            line two
            ```
            insertion anchor
            ```
            final block
            /
            final line
            ```
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let originalLines = editor.presentationTextForTesting.components(separatedBy: "\n")
        let anchorLineIndex = try XCTUnwrap(originalLines.firstIndex(of: "insertion anchor"))
        XCTAssertTrue(
            editor.typeTextForTesting(
                "\n1. ",
                atLine: anchorLineIndex,
                utf16Offset: (originalLines[anchorLineIndex] as NSString).length
            )
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let numberedLineIndex = anchorLineIndex + 1
        let geometry = editor.textDocumentGeometryForTesting
        XCTAssertGreaterThanOrEqual(
            geometry.frame.height,
            geometry.usedRect.maxY,
            "The interactive NSTextView frame must contain post-edit structured layout"
        )
        XCTAssertTrue(
            editor.mouseCanPlaceCaretWithoutScrollingForTesting(
                lineIndex: numberedLineIndex,
                utf16Offset: 0
            ),
            "The newly promoted numbered line must accept a mouse click"
        )
        for lineIndex in editor.codeBlockLineIndicesForTesting where lineIndex > numberedLineIndex {
            XCTAssertTrue(
                editor.mouseCanPlaceCaretWithoutScrollingForTesting(
                    lineIndex: lineIndex,
                    utf16Offset: 0
                ),
                "Lower code line \(lineIndex) must remain reachable after the middle edit"
            )
        }
    }

    func testTerminalEmptyCodeBlockGeometryDoesNotDependOnCaretLine() throws {
        let (editor, window) = makeEditor()
        editor.setText(
            """
            first
            second
            ```

            ```
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let codeLine = try XCTUnwrap(editor.codeBlockLineIndicesForTesting.last)
        let codeRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: codeLine))
        editor.selectRangeForTesting(NSRange(location: codeRange.location, length: 0))
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        let focusedFrame = try XCTUnwrap(editor.codeBlockFramesForTesting().last)
        let focusedGeometry = editor.lineGeometryDescriptionForTesting(lineIndex: codeLine)

        let precedingRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: codeLine - 1))
        editor.selectRangeForTesting(NSRange(location: precedingRange.location, length: 0))
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        let unfocusedFrame = try XCTUnwrap(editor.codeBlockFramesForTesting().last)
        let unfocusedGeometry = editor.lineGeometryDescriptionForTesting(lineIndex: codeLine)

        XCTAssertEqual(
            unfocusedFrame.minY,
            focusedFrame.minY,
            accuracy: 0.5,
            "Moving the caret outside a terminal empty code block must not move it. "
                + "focused=\(focusedGeometry), unfocused=\(unfocusedGeometry)"
        )
        XCTAssertEqual(
            unfocusedFrame.height,
            focusedFrame.height,
            accuracy: 0.5,
            "Moving the caret outside a terminal empty code block must not resize it. "
                + "focused=\(focusedGeometry), unfocused=\(unfocusedGeometry)"
        )
    }

    func testEmptyCodeBlockAfterPopulatedBlockAndBlankLinesUsesSingleLineHeight() throws {
        let (editor, window) = makeEditor()
        editor.setText(
            """
            ```python
            import tensorflow as tf
            def add(a, b):
                return a + b

            ```





            ```

            ```
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let initialFrames = editor.codeBlockFramesForTesting()
        XCTAssertEqual(initialFrames.count, 2)
        XCTAssertEqual(editor.codeBlockLineIndicesForTesting.count, 5)
        let emptyCodeLine = try XCTUnwrap(editor.codeBlockLineIndicesForTesting.last)
        let emptyCodeRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: emptyCodeLine))
        editor.selectRangeForTesting(NSRange(location: emptyCodeRange.location, length: 0))
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let focusedFrames = editor.codeBlockFramesForTesting()
        let emptyGeometry = editor.lineGeometryDescriptionForTesting(lineIndex: emptyCodeLine)
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(focusedFrames.last).height,
            40,
            "A focused one-line empty block must not absorb surrounding blank-line height: initial=\(initialFrames), focused=\(focusedFrames)"
        )
        XCTAssertTrue(editor.typeTextForTesting("x", atLine: emptyCodeLine, utf16Offset: 0))
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let populatedFrames = editor.codeBlockFramesForTesting()
        let populatedGeometry = editor.lineGeometryDescriptionForTesting(lineIndex: emptyCodeLine)
        XCTAssertEqual(
            try XCTUnwrap(populatedFrames.last).minY,
            try XCTUnwrap(focusedFrames.last).minY,
            accuracy: 0.5,
            "The empty block must not move when its first character is typed. empty=\(emptyGeometry), populated=\(populatedGeometry)"
        )
        XCTAssertEqual(
            try XCTUnwrap(populatedFrames.last).height,
            try XCTUnwrap(focusedFrames.last).height,
            accuracy: 0.5,
            "The empty block must not resize when its first character is typed. empty=\(emptyGeometry), populated=\(populatedGeometry)"
        )
    }

    func testFirstDocumentLineCodeBlockContainsItsGlyphRow() throws {
        let (editor, window) = makeEditor()
        editor.setText(
            """
            ```swift
            let value = 1
            ```
            after
            """
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let blockFrame = try XCTUnwrap(editor.codeBlockFramesForTesting().first)
        let glyphFrame = try XCTUnwrap(editor.glyphFrameForTesting(lineIndex: 0))
        XCTAssertLessThanOrEqual(
            blockFrame.minY,
            glyphFrame.minY - 2,
            "The first code block border must begin above its text. block=\(blockFrame), glyph=\(glyphFrame)"
        )
        XCTAssertGreaterThanOrEqual(
            blockFrame.maxY,
            glyphFrame.maxY + 2,
            "The first code block border must end below its text. block=\(blockFrame), glyph=\(glyphFrame)"
        )
    }

    func testCopyingCompleteCodeBlockPreservesFenceAndLanguage() throws {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            before
            ```python
            import abc
            run abc
            ```
            after
            """
        )

        let firstCodeRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 1))
        let secondCodeRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 2))
        editor.selectRangeForTesting(
            NSRange(
                location: firstCodeRange.location,
                length: NSMaxRange(secondCodeRange) - firstCodeRange.location
            )
        )

        XCTAssertEqual(
            editor.copySelectionForTesting(),
            """
            ```python
            import abc
            run abc
            ```
            """
        )
    }

    func testCopyingPartialCodeTextDoesNotAddFences() throws {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            ```python
            import abc
            ```
            """
        )

        let codeRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        editor.selectRangeForTesting(NSRange(location: codeRange.location, length: 6))

        XCTAssertEqual(editor.copySelectionForTesting(), "import")
    }

    func testCopyingNormalTextAndACompleteCodeBlockPreservesBoth() throws {
        let (editor, _) = makeEditor()
        editor.setText(
            """
            ignored
            before block
            ```swift
            let value = 1
            ```
            ignored after
            """
        )

        let normalRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 1))
        let codeRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 2))
        editor.selectRangeForTesting(
            NSRange(
                location: normalRange.location,
                length: NSMaxRange(codeRange) - normalRange.location
            )
        )

        XCTAssertEqual(
            editor.copySelectionForTesting(),
            """
            before block
            ```swift
            let value = 1
            ```
            """
        )
    }

    func testCopiedCodeBlockPastesIntoAnotherNoteWithItsLanguage() throws {
        let (source, _) = makeEditor()
        source.setText(
            """
            ```go
            fmt.Println("hello")
            return nil
            ```
            """
        )
        let firstCodeRange = try XCTUnwrap(source.contentRangeForTesting(lineIndex: 0))
        let secondCodeRange = try XCTUnwrap(source.contentRangeForTesting(lineIndex: 1))
        source.selectRangeForTesting(
            NSRange(
                location: firstCodeRange.location,
                length: NSMaxRange(secondCodeRange) - firstCodeRange.location
            )
        )
        XCTAssertNotNil(source.copySelectionForTesting())

        let (destination, _) = makeEditor()
        destination.setText("")
        destination.pasteFromGeneralPasteboardForTesting()

        XCTAssertEqual(destination.codeBlockLanguagesForTesting, ["go", "go"])
        XCTAssertEqual(
            destination.text,
            """
            ```go
            fmt.Println("hello")
            return nil
            ```
            """
        )
    }

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
        let emptyGeometry = editor.lineGeometryDescriptionForTesting(lineIndex: 1)

        XCTAssertTrue(editor.typeTextForTesting("print('hello')", atLine: 1, utf16Offset: 0))
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let populatedFrame = try XCTUnwrap(editor.codeBlockFramesForTesting().first)
        let populatedLineFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 1))
        let populatedGeometry = editor.lineGeometryDescriptionForTesting(lineIndex: 1)
        XCTAssertEqual(populatedFrame.minY, emptyFrame.minY, accuracy: 0.5, "empty=\(emptyGeometry), populated=\(populatedGeometry)")
        XCTAssertEqual(populatedFrame.maxY, emptyFrame.maxY, accuracy: 0.5, "empty=\(emptyGeometry), populated=\(populatedGeometry)")
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
        let emptyGeometry = editor.lineGeometryDescriptionForTesting(lineIndex: 0)

        editor.typeTextForTesting("print('hello')")
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()

        let populatedFrame = try XCTUnwrap(editor.codeBlockFramesForTesting().first)
        let populatedLineFrame = try XCTUnwrap(editor.lineFrameForTesting(lineIndex: 0))
        let populatedGeometry = editor.lineGeometryDescriptionForTesting(lineIndex: 0)
        XCTAssertEqual(populatedFrame.minY, emptyFrame.minY, accuracy: 0.5, "empty=\(emptyGeometry), populated=\(populatedGeometry)")
        XCTAssertEqual(populatedFrame.maxY, emptyFrame.maxY, accuracy: 0.5, "empty=\(emptyGeometry), populated=\(populatedGeometry)")
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

    func testSemanticZoomReflowsTextWithoutChangingMarkdownOrScrollingSideways() {
        let (editor, window) = makeEditor()
        window.setContentSize(NSSize(width: 240, height: 320))
        let markdown = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen"
        editor.setText(markdown)

        editor.setNoteZoom(0.6)
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        let smallFragmentCount = editor.visualFragmentCountForTesting(lineIndex: 0)

        editor.setNoteZoom(2.0)
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        let largeFragmentCount = editor.visualFragmentCountForTesting(lineIndex: 0)

        XCTAssertEqual(editor.noteZoomForTesting, 2.0)
        XCTAssertGreaterThan(largeFragmentCount, smallFragmentCount)
        XCTAssertEqual(editor.text, markdown)
        XCTAssertEqual(editor.horizontalScrollOffsetForTesting, 0, accuracy: 0.5)
    }

    func testSemanticZoomKeepsCodeAndCheckboxInteractionsReachable() throws {
        let (editor, window) = makeEditor()
        window.setContentSize(NSSize(width: 300, height: 420))
        editor.setText(
            """
            ```swift
            let answer = 42
            ```
            - [ ] task
            """
        )
        let originalMarkdown = editor.text
        var codeHeights: [CGFloat] = []

        for scale in [0.6, 1.0, 2.0] {
            editor.setNoteZoom(scale)
            window.contentView?.layoutSubtreeIfNeeded()
            editor.layoutSubtreeIfNeeded()

            let frame = try XCTUnwrap(editor.codeBlockFramesForTesting().first)
            codeHeights.append(frame.height)
            XCTAssertTrue(editor.codeLanguageControlRespondsToHitTestingForTesting())
            XCTAssertTrue(editor.checkboxUsesPointingHandCursorForTesting(lineIndex: 1))
            XCTAssertTrue(
                editor.checkboxRespondsToClickForTesting(lineIndex: 1),
                editor.checkboxDiagnosticsForTesting(lineIndex: 1)
            )
            XCTAssertTrue(editor.mouseCanPlaceCaretWithoutScrollingForTesting(
                lineIndex: 0,
                utf16Offset: 3
            ))
        }

        XCTAssertLessThan(codeHeights[0], codeHeights[1])
        XCTAssertLessThan(codeHeights[1], codeHeights[2])
        XCTAssertEqual(
            editor.text.replacingOccurrences(of: "- [x]", with: "- [ ]"),
            originalMarkdown
        )
    }

    func testSemanticZoomScalesRenderedTableRowsAndPreservesSource() throws {
        let (editor, window) = makeEditor()
        window.setContentSize(NSSize(width: 300, height: 420))
        let markdown = """
        | Name | Details |
        | --- | --- |
        | Pinaday | a long table value that wraps inside its cell |
        after
        """
        editor.setText(markdown)
        let afterRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 3))
        editor.selectRangeForTesting(
            NSRange(location: NSMaxRange(afterRange), length: 0)
        )

        editor.setNoteZoom(0.6)
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        let smallRows = editor.tableRowFramesForTesting()

        editor.setNoteZoom(2.0)
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        let largeRows = editor.tableRowFramesForTesting()

        XCTAssertEqual(smallRows.count, 2)
        XCTAssertEqual(largeRows.count, 2)
        XCTAssertGreaterThan(largeRows[1].height, smallRows[1].height)
        XCTAssertEqual(editor.text, markdown)
    }

    func testSemanticZoomScalesImagePreviewButKeepsViewportClamp() {
        let (editor, _) = makeEditor()
        let imageSize = NSSize(width: 1200, height: 600)

        XCTAssertEqual(
            editor.imagePreviewSizeForTesting(
                imageSize: imageSize,
                availableWidth: 1000,
                explicitWidth: 300,
                contentScale: 0.6
            ),
            NSSize(width: 180, height: 90)
        )
        XCTAssertEqual(
            editor.imagePreviewSizeForTesting(
                imageSize: imageSize,
                availableWidth: 1000,
                explicitWidth: 300,
                contentScale: 2.0
            ),
            NSSize(width: 600, height: 300)
        )
        XCTAssertEqual(
            editor.imagePreviewSizeForTesting(
                imageSize: imageSize,
                availableWidth: 500,
                explicitWidth: 300,
                contentScale: 2.0
            ),
            NSSize(width: 500, height: 250)
        )
    }

    func testSemanticZoomPreservesTheVisibleReadingRegion() throws {
        let (editor, window) = makeEditor()
        window.setContentSize(NSSize(width: 260, height: 220))
        editor.setText((1...120).map { "line \($0) with enough text to wrap" }.joined(separator: "\n"))
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        editor.scrollToBottomForTesting()
        let before = try XCTUnwrap(editor.visibleCharacterLocationForTesting)

        editor.setNoteZoom(2.0)
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        let after = try XCTUnwrap(editor.visibleCharacterLocationForTesting)

        XCTAssertGreaterThan(before, 1_000)
        XCTAssertGreaterThan(after, before - 100)
        XCTAssertEqual(editor.horizontalScrollOffsetForTesting, 0, accuracy: 0.5)
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

    func testSelectCurrentLineSelectsTheLogicalLineIncludingItsNewline() {
        let (editor, _) = makeEditor()
        editor.setText("alpha\nbeta\ngamma")
        editor.selectRangeForTesting(NSRange(location: 8, length: 0))

        editor.pressSelectCurrentLineShortcutForTesting()

        XCTAssertEqual(editor.selectedTextForTesting, "beta\n")
        XCTAssertEqual(editor.selectedRangeForTesting, NSRange(location: 6, length: 5))
    }

    func testSelectCurrentLineSelectsFinalLineWithoutTrailingNewline() {
        let (editor, _) = makeEditor()
        editor.setText("alpha\nbeta\ngamma")
        editor.selectRangeForTesting(NSRange(location: 13, length: 0))

        editor.selectCurrentLineForTesting()

        XCTAssertEqual(editor.selectedTextForTesting, "gamma")
        XCTAssertEqual(editor.selectedRangeForTesting, NSRange(location: 11, length: 5))
    }

    func testSelectCurrentLinePreservesStructuredMarkdownWhenCopied() throws {
        let (editor, _) = makeEditor()
        editor.setText("- [ ] first task\n1. numbered item\nplain")
        let contentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        editor.selectRangeForTesting(NSRange(location: contentRange.location + 2, length: 0))

        editor.selectCurrentLineForTesting()

        XCTAssertEqual(editor.selectedTextForTesting, "first task\n")
        XCTAssertEqual(editor.copySelectionForTesting(), "- [ ] first task")
    }

    func testSelectCurrentLineShortcutRequiresCommandLWithoutExtraModifiers() {
        XCTAssertTrue(SelectCurrentLineShortcut.matches(
            charactersIgnoringModifiers: "l",
            modifierFlags: .command
        ))
        XCTAssertTrue(SelectCurrentLineShortcut.matches(
            charactersIgnoringModifiers: "L",
            modifierFlags: .command
        ))
        XCTAssertFalse(SelectCurrentLineShortcut.matches(
            charactersIgnoringModifiers: "l",
            modifierFlags: []
        ))
        XCTAssertFalse(SelectCurrentLineShortcut.matches(
            charactersIgnoringModifiers: "l",
            modifierFlags: [.command, .shift]
        ))
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

    func testCaretTabAndBacktabChangeTodoHierarchyWithoutEditingContent() throws {
        let (editor, _) = makeEditor()
        editor.setText("- [ ] task")
        let contentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        editor.selectRangeForTesting(NSRange(location: NSMaxRange(contentRange), length: 0))

        editor.pressTabForTesting()

        XCTAssertEqual(editor.presentationTextForTesting, "task")
        XCTAssertEqual(editor.text, "    - [ ] task")

        editor.pressBacktabForTesting()

        XCTAssertEqual(editor.presentationTextForTesting, "task")
        XCTAssertEqual(editor.text, "- [ ] task")
    }

    func testCaretTabAndBacktabChangeBulletHierarchyWithoutEditingContent() throws {
        let (editor, _) = makeEditor()
        editor.setText("- bullet")
        let contentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        editor.selectRangeForTesting(NSRange(location: NSMaxRange(contentRange), length: 0))

        editor.pressTabForTesting()

        XCTAssertEqual(editor.presentationTextForTesting, "bullet")
        XCTAssertEqual(editor.text, "    - bullet")

        editor.pressBacktabForTesting()

        XCTAssertEqual(editor.presentationTextForTesting, "bullet")
        XCTAssertEqual(editor.text, "- bullet")
    }

    func testCaretTabAndBacktabChangeNumberedHierarchyAndPreserveCaretOffset() throws {
        let (editor, _) = makeEditor()
        editor.setText("1. numbered")
        let contentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        let contentOffset = 4
        editor.selectRangeForTesting(
            NSRange(location: contentRange.location + contentOffset, length: 0)
        )

        editor.pressTabForTesting()

        let indentedContentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        XCTAssertEqual(editor.presentationTextForTesting, "a. numbered")
        XCTAssertEqual(editor.text, "    1. numbered")
        XCTAssertEqual(
            editor.selectedRangeForTesting.location,
            indentedContentRange.location + contentOffset
        )

        editor.pressBacktabForTesting()

        let restoredContentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        XCTAssertEqual(editor.presentationTextForTesting, "1. numbered")
        XCTAssertEqual(editor.text, "1. numbered")
        XCTAssertEqual(
            editor.selectedRangeForTesting.location,
            restoredContentRange.location + contentOffset
        )
    }

    func testBacktabAtTopLevelStructuredItemDoesNotDeleteContent() throws {
        let (editor, _) = makeEditor()
        editor.setText("- [ ] task")
        let contentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 0))
        editor.selectRangeForTesting(NSRange(location: contentRange.location + 2, length: 0))

        editor.pressBacktabForTesting()

        XCTAssertEqual(editor.presentationTextForTesting, "task")
        XCTAssertEqual(editor.text, "- [ ] task")
    }

    func testCaretTabInPlainTextStillInsertsLiteralIndentation() {
        let (editor, _) = makeEditor()
        editor.setText("plain")
        editor.selectRangeForTesting(NSRange(location: 2, length: 0))

        editor.pressTabForTesting()

        XCTAssertEqual(editor.presentationTextForTesting, "pl    ain")
        XCTAssertEqual(editor.text, "pl    ain")
        XCTAssertEqual(editor.selectedRangeForTesting, NSRange(location: 6, length: 0))
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

    func testTypingNumberedMarkerPromotesToVisibleEmptyNumberedItem() {
        for marker in ["1. ", "2. ", "24. "] {
            let (editor, _) = makeEditor()

            for character in marker {
                editor.typeTextForTesting(String(character))
            }

            XCTAssertEqual(
                editor.presentationTextForTesting,
                marker,
                "Typing \(marker.debugDescription) must keep its visible numbered marker"
            )
            XCTAssertEqual(
                editor.text,
                marker,
                "Typing \(marker.debugDescription) must preserve canonical Markdown"
            )
        }
    }

    func testTypingLetterPeriodSpaceRemainsPlainText() {
        let (editor, _) = makeEditor()

        editor.typeTextForTesting("x. ")

        XCTAssertEqual(editor.presentationTextForTesting, "x. ")
        XCTAssertEqual(editor.text, "x. ")
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

    private func makeScrolledSplitCodeBlockEditor() throws -> (
        editor: InlineTodoTextEditorContainer,
        window: NSWindow,
        splitLineIndex: Int,
        lowerCodeLineIndex: Int
    ) {
        let (editor, window) = makeEditor()
        window.setContentSize(NSSize(width: 620, height: 300))
        let precedingLines = (1...45).map { "prefix\($0)" }
        let codeLines = (1...10).map { "code\($0)" }
        editor.setText(
            (precedingLines + ["```python"] + codeLines + ["```"]).joined(separator: "\n")
        )
        window.contentView?.layoutSubtreeIfNeeded()
        editor.layoutSubtreeIfNeeded()
        editor.scrollToBottomForTesting()

        let splitLineIndex = precedingLines.count + 3
        let splitLine = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: splitLineIndex))
        editor.selectRangeForTesting(splitLine)
        editor.typeTextForTesting("/n")
        editor.pressReturnForTesting()

        let lines = editor.presentationTextForTesting.components(separatedBy: "\n")
        XCTAssertEqual(lines[splitLineIndex], "1. ")
        let lowerCodeLineIndex = try XCTUnwrap(lines.firstIndex(of: "code5"))
        return (editor, window, splitLineIndex, lowerCodeLineIndex)
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

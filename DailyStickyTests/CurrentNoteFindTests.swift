import AppKit
import Foundation
import XCTest
@testable import Pinaday

final class CurrentNoteFindTests: XCTestCase {
    func testFindReturnsEveryCurrentNoteRangeWithoutMutatingText() {
        let text = "Alpha first\nsecond alpha\nALPHA third"

        let matches = CurrentNoteFindEngine.matches(
            query: "alpha",
            noteText: text,
            imageText: [],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(
            matches.compactMap(\.noteRange),
            [
                NSRange(location: 0, length: 5),
                NSRange(location: 19, length: 5),
                NSRange(location: 25, length: 5)
            ]
        )
        XCTAssertEqual(text, "Alpha first\nsecond alpha\nALPHA third")
    }

    func testFindSupportsDiacriticsCharacterWidthAndCJKText() {
        let text = "Résumé\n資料レビュー\n全角 ＡＢＣ"

        XCTAssertEqual(find("resume", in: text).count, 1)
        XCTAssertEqual(find("資料", in: text).count, 1)
        XCTAssertEqual(find("ABC", in: text).count, 1)
    }

    func testImageMarkdownSourceIsNotReturnedAsVisibleNoteText() {
        let markdown = "visible receipt\n![](attachments/receipt.png){width=240}"

        let matches = find("receipt", in: markdown)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.noteRange, NSRange(location: 8, length: 7))
    }

    func testOCRMatchesCarryImageAndObservationLocation() throws {
        let markdown = "Before\n![](attachments/receipt.png)\nAfter"
        let reference = try XCTUnwrap(
            MarkdownImageReferenceParser.references(in: markdown).first
        )
        let imageLine = SearchableImageText(
            attachmentPath: reference.path,
            markdownRange: reference.markdownRange,
            observationIndex: 2,
            text: "Invoice total 438 dollars",
            normalizedBoundingBox: CGRect(x: 0.1, y: 0.72, width: 0.8, height: 0.08)
        )

        let matches = CurrentNoteFindEngine.matches(
            query: "438",
            noteText: markdown,
            imageText: [imageLine],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(
            matches.map(\.location),
            [
                .image(
                    attachmentPath: reference.path,
                    markdownRange: reference.markdownRange,
                    observationIndex: 2,
                    characterRange: NSRange(location: 14, length: 3),
                    normalizedBoundingBox: CGRect(
                        x: 0.1,
                        y: 0.72,
                        width: 0.8,
                        height: 0.08
                    )
                )
            ]
        )
    }

    func testGlobalSearchCarriesExactNormalTextLocation() {
        let text = "first line\ndeploy the release"
        let engine = NoteSearchEngine(
            documents: [
                NoteSearchDocument(
                    dateKey: "2026-08-19",
                    text: text,
                    updatedAt: .distantPast
                )
            ]
        )

        XCTAssertEqual(
            engine.search("deploy").first?.matchLocation,
            .note(range: (text as NSString).range(of: "deploy"))
        )
    }

    func testGlobalFuzzySearchFallsBackToTheMatchingLineRange() {
        let text = "first line\ndeploy the release"
        let engine = NoteSearchEngine(
            documents: [
                NoteSearchDocument(
                    dateKey: "2026-08-19",
                    text: text,
                    updatedAt: .distantPast
                )
            ]
        )

        XCTAssertEqual(
            engine.search("deply").first?.matchLocation,
            .note(range: (text as NSString).range(of: "deploy the release"))
        )
    }

    func testGlobalSearchNarrowsOCRLocationToExactCharacters() {
        let markdownRange = NSRange(location: 7, length: 30)
        let engine = NoteSearchEngine(
            documents: [
                NoteSearchDocument(
                    dateKey: "2026-08-19",
                    text: "image",
                    updatedAt: .distantPast,
                    supplementalLines: [
                        NoteSearchSupplementalLine(
                            text: "Invoice total 438 dollars",
                            source: .image(attachmentPath: "attachments/receipt.png"),
                            location: .image(
                                attachmentPath: "attachments/receipt.png",
                                markdownRange: markdownRange,
                                observationIndex: 2,
                                characterRange: NSRange(location: 0, length: 25),
                                normalizedBoundingBox: CGRect(
                                    x: 0.1,
                                    y: 0.72,
                                    width: 0.8,
                                    height: 0.08
                                )
                            )
                        )
                    ]
                )
            ]
        )

        XCTAssertEqual(
            engine.search("438").first?.matchLocation,
            .image(
                attachmentPath: "attachments/receipt.png",
                markdownRange: markdownRange,
                observationIndex: 2,
                characterRange: NSRange(location: 14, length: 3),
                normalizedBoundingBox: CGRect(
                    x: 0.1,
                    y: 0.72,
                    width: 0.8,
                    height: 0.08
                )
            )
        )
    }

    @MainActor
    func testEditorMapsMarkdownSearchRangesWithoutChangingTextOrSelection() throws {
        let markdown = "- [ ] alpha\n1. beta\n```swift\ngamma\n```"
        let editor = InlineTodoTextEditorContainer(
            frame: NSRect(x: 0, y: 0, width: 360, height: 260)
        )
        editor.setText(markdown)
        let betaContentRange = try XCTUnwrap(editor.contentRangeForTesting(lineIndex: 1))
        let originalSelection = NSRange(location: betaContentRange.location + 2, length: 0)
        editor.selectRangeForTesting(originalSelection)

        let source = markdown as NSString
        let matches = ["alpha", "beta", "gamma"].enumerated().map { index, text in
            CurrentNoteFindMatch(
                id: "match-\(index)",
                location: .note(range: source.range(of: text))
            )
        }
        editor.setFindMatches(
            query: "a",
            matches: matches,
            selectedMatchID: "match-2"
        )

        let visibleText = editor.presentationTextForTesting as NSString
        XCTAssertEqual(
            editor.searchHighlightRangesForTesting().map { visibleText.substring(with: $0) },
            ["alpha", "beta", "gamma"]
        )
        XCTAssertEqual(
            editor.searchHighlightRangesForTesting(activeOnly: true).map {
                visibleText.substring(with: $0)
            },
            ["gamma"]
        )
        XCTAssertEqual(editor.selectedRangeForTesting, originalSelection)
        XCTAssertEqual(editor.text, markdown)
    }

    @MainActor
    func testRenderedTablesReceiveCellLocalHighlightsAcrossSeparateTableRows() throws {
        let markdown = """
        Before
        | Model | Baige samples/s | Baige / ACK | **Baige / PAI** |
        | --- | --- | --- | --- |
        | A | 10 | 11 | 12 |

        Between
        | Model | Baige samples/s | Baige / ACK | Baige / PAI |
        | --- | --- | --- | --- |
        | B | 20 | 21 | 22 |
        After
        """
        let matches = CurrentNoteFindEngine.matches(
            query: "baige",
            noteText: markdown,
            imageText: [],
            locale: Locale(identifier: "en_US")
        )
        let editor = InlineTodoTextEditorContainer(
            frame: NSRect(x: 0, y: 0, width: 360, height: 180)
        )
        editor.setText(markdown)
        editor.selectRangeForTesting(NSRange(location: 0, length: 0))
        editor.setFindMatches(
            query: "baige",
            matches: matches,
            selectedMatchID: matches[1].id
        )

        let snapshots = editor.tableSearchHighlightSnapshotsForTesting()
        XCTAssertEqual(snapshots.map(\.lineIndex), [1, 1, 1, 6, 6, 6])
        XCTAssertEqual(snapshots.map(\.cellIndex), [1, 2, 3, 1, 2, 3])
        XCTAssertEqual(snapshots.map(\.matchedText), Array(repeating: "Baige", count: 6))
        XCTAssertEqual(snapshots.filter(\.isActive).count, 1)
        XCTAssertEqual(snapshots.first(where: \.isActive)?.cellIndex, 2)
        XCTAssertEqual(
            editor.displayLineIndexForSearchTesting(matches[4].location),
            6
        )
        XCTAssertEqual(editor.text, markdown)
    }

    @MainActor
    func testImageOCRSearchMapsToTheImageDisplayLine() throws {
        let markdown = "Before\nMiddle\n![](attachments/receipt.png){width=240}\nAfter"
        let reference = try XCTUnwrap(
            MarkdownImageReferenceParser.references(in: markdown).first
        )
        let location = NoteSearchMatchLocation.image(
            attachmentPath: reference.path,
            markdownRange: reference.markdownRange,
            observationIndex: 0,
            characterRange: NSRange(location: 8, length: 5),
            normalizedBoundingBox: CGRect(x: 0.2, y: 0.15, width: 0.4, height: 0.06)
        )
        let editor = InlineTodoTextEditorContainer(
            frame: NSRect(x: 0, y: 0, width: 360, height: 180)
        )
        editor.setText(markdown)

        XCTAssertEqual(editor.displayLineIndexForSearchTesting(location), 2)
        XCTAssertEqual(editor.text, markdown)
    }

    func testOCRSearchRevealMapsVisionCoordinatesIntoRenderedImage() {
        let imageRect = CGRect(x: 10, y: 100, width: 400, height: 800)

        let nearTop = OCRSearchRevealGeometry.displayRect(
            for: CGRect(x: 0.25, y: 0.80, width: 0.5, height: 0.10),
            in: imageRect
        )
        let nearBottom = OCRSearchRevealGeometry.displayRect(
            for: CGRect(x: 0.25, y: 0.10, width: 0.5, height: 0.10),
            in: imageRect
        )

        XCTAssertEqual(nearTop, CGRect(x: 110, y: 180, width: 200, height: 80))
        XCTAssertEqual(nearBottom, CGRect(x: 110, y: 740, width: 200, height: 80))
        XCTAssertLessThan(nearTop.midY, nearBottom.midY)
    }

    func testOCRSearchRevealCentersAndClampsInsideDocument() {
        XCTAssertEqual(
            OCRSearchRevealGeometry.centeredVerticalOffset(
                for: CGRect(x: 0, y: 20, width: 50, height: 20),
                viewportHeight: 200,
                documentHeight: 1_000
            ),
            0
        )
        XCTAssertEqual(
            OCRSearchRevealGeometry.centeredVerticalOffset(
                for: CGRect(x: 0, y: 480, width: 50, height: 40),
                viewportHeight: 200,
                documentHeight: 1_000
            ),
            400
        )
        XCTAssertEqual(
            OCRSearchRevealGeometry.centeredVerticalOffset(
                for: CGRect(x: 0, y: 960, width: 50, height: 30),
                viewportHeight: 200,
                documentHeight: 1_000
            ),
            800
        )
    }

    func testCurrentNoteFindShortcutIsCommandFOnly() {
        XCTAssertTrue(CurrentNoteFindShortcut.matches(
            charactersIgnoringModifiers: "f",
            modifierFlags: [.command]
        ))
        XCTAssertFalse(CurrentNoteFindShortcut.matches(
            charactersIgnoringModifiers: "p",
            modifierFlags: [.command]
        ))
        XCTAssertFalse(CurrentNoteFindShortcut.matches(
            charactersIgnoringModifiers: "f",
            modifierFlags: [.command, .shift]
        ))
    }

    func testCurrentNoteFindEscapeShortcutAllowsPlainOrShiftEscapeOnly() {
        XCTAssertTrue(CurrentNoteFindEscapeShortcut.matches(
            keyCode: 53,
            modifierFlags: []
        ))
        XCTAssertTrue(CurrentNoteFindEscapeShortcut.matches(
            keyCode: 53,
            modifierFlags: [.shift]
        ))
        XCTAssertFalse(CurrentNoteFindEscapeShortcut.matches(
            keyCode: 53,
            modifierFlags: [.command]
        ))
        XCTAssertFalse(CurrentNoteFindEscapeShortcut.matches(
            keyCode: 36,
            modifierFlags: []
        ))
    }

    @MainActor
    func testEscapeClearsThenClosesPresentedFindFromOutsideTheSearchField() {
        let controller = CurrentNoteFindController()
        controller.present()
        controller.query = "needle"

        XCTAssertTrue(controller.handleEscapeIfPresented())
        XCTAssertEqual(controller.query, "")
        XCTAssertTrue(controller.isPresented)

        XCTAssertTrue(controller.handleEscapeIfPresented())
        XCTAssertFalse(controller.isPresented)
        XCTAssertFalse(controller.handleEscapeIfPresented())
    }

    func testEditorContextMenuPreservesNativeServicesAndAddsPinadayActionsAfterPasteGroup() throws {
        let menu = NSMenu()
        let lookupItem = NSMenuItem(
            title: "Look Up",
            action: Selector("lookUp:"),
            keyEquivalent: ""
        )
        let pasteItem = NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        let pasteAndMatchStyleItem = NSMenuItem(
            title: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v"
        )
        pasteAndMatchStyleItem.keyEquivalentModifierMask = [
            .command, .option, .shift
        ]
        let shareItem = NSMenuItem(
            title: "Share",
            action: Selector("share:"),
            keyEquivalent: ""
        )
        menu.addItem(lookupItem)
        menu.addItem(pasteItem)
        menu.addItem(pasteAndMatchStyleItem)
        menu.addItem(.separator())
        menu.addItem(shareItem)
        let target = ContextMenuActionTarget()

        let actions = [
            EditorContextMenuAction(
                title: "Find in Note",
                action: #selector(ContextMenuActionTarget.findInNote(_:)),
                keyEquivalent: "f",
                modifierMask: [.command]
            ),
            EditorContextMenuAction(
                title: "Go to Note",
                action: #selector(ContextMenuActionTarget.goToNote(_:)),
                keyEquivalent: "p",
                modifierMask: [.command]
            ),
            EditorContextMenuAction(
                title: "Back to today",
                action: #selector(ContextMenuActionTarget.backToToday(_:))
            )
        ]
        let updatedMenu = EditorContextMenuBuilder.addingPinadayActions(
            to: menu,
            target: target,
            actions: actions
        )

        XCTAssertTrue(updatedMenu === menu)
        XCTAssertTrue(updatedMenu.items.contains(where: { $0 === lookupItem }))
        XCTAssertTrue(updatedMenu.items.contains(where: { $0 === pasteItem }))
        XCTAssertTrue(updatedMenu.items.contains(where: {
            $0 === pasteAndMatchStyleItem
        }))
        XCTAssertTrue(updatedMenu.items.contains(where: { $0 === shareItem }))
        XCTAssertEqual(
            updatedMenu.items.filter { !$0.isSeparatorItem }.map(\.title),
            [
                "Look Up",
                "Paste",
                "Paste and Match Style",
                "Find in Note",
                "Go to Note",
                "Back to today",
                "Share"
            ]
        )
        let findItem = try XCTUnwrap(updatedMenu.items.first(where: {
            $0.action == #selector(ContextMenuActionTarget.findInNote(_:))
        }))
        XCTAssertEqual(findItem.keyEquivalent, "f")
        XCTAssertEqual(findItem.keyEquivalentModifierMask, [.command])
        XCTAssertTrue(findItem.target === target)
        let goToItem = try XCTUnwrap(updatedMenu.items.first(where: {
            $0.action == #selector(ContextMenuActionTarget.goToNote(_:))
        }))
        XCTAssertEqual(goToItem.keyEquivalent, "p")
        XCTAssertEqual(goToItem.keyEquivalentModifierMask, [.command])
        XCTAssertTrue(goToItem.target === target)

        _ = EditorContextMenuBuilder.addingPinadayActions(
            to: menu,
            target: target,
            actions: actions
        )
        for action in actions {
            XCTAssertEqual(
                menu.items.filter { $0.action == action.action }.count,
                1
            )
        }
    }

    @MainActor
    func testControllerWrapsMatchesInBothDirections() {
        let controller = CurrentNoteFindController()
        controller.update(
            page: DayPage(
                dateKey: "2026-08-19",
                noteText: "one one one",
                createdAt: .distantPast,
                updatedAt: .distantPast
            ),
            locale: Locale(identifier: "en_US")
        )
        controller.query = "one"

        XCTAssertEqual(controller.positionLabel, "1/3")
        controller.moveSelection(by: -1)
        XCTAssertEqual(controller.positionLabel, "3/3")
        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.positionLabel, "1/3")
    }

    @MainActor
    func testSearchHandoffPresentsFindAndSelectsTheOpenedOccurrence() {
        let controller = CurrentNoteFindController()
        let page = DayPage(
            dateKey: "2026-08-19",
            noteText: "transaction one\ntransaction two\ntransaction three",
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
        controller.update(page: page, locale: Locale(identifier: "en_US"))
        let request = NoteRevealRequest(
            dateKey: page.dateKey,
            query: "transaction",
            location: .note(range: NSRange(location: 16, length: 11))
        )

        controller.presentSearchHandoff(request)

        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(controller.query, "transaction")
        XCTAssertEqual(controller.positionLabel, "2/3")
        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.positionLabel, "3/3")
        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.positionLabel, "1/3")
    }

    private func find(_ query: String, in text: String) -> [CurrentNoteFindMatch] {
        CurrentNoteFindEngine.matches(
            query: query,
            noteText: text,
            imageText: [],
            locale: Locale(identifier: "en_US")
        )
    }
}

private final class ContextMenuActionTarget: NSObject {
    @objc func findInNote(_ sender: Any?) {}
    @objc func goToNote(_ sender: Any?) {}
    @objc func backToToday(_ sender: Any?) {}
}

private extension CurrentNoteFindMatch {
    var noteRange: NSRange? {
        guard case let .note(range) = location else {
            return nil
        }
        return range
    }
}

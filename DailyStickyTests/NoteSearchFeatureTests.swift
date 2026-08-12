import AppKit
import XCTest
@testable import Pinaday

@MainActor
final class NoteSearchFeatureTests: XCTestCase {
    func testControllerIndexesPagesAndRefreshesResultsAfterPageChanges() {
        let controller = NoteSearchController()
        var pages = [
            "2026-08-01": page("2026-08-01", "project alpha"),
            "2026-08-02": page("2026-08-02", "project beta")
        ]

        controller.rebuildIndex(with: pages)
        controller.query = "alpha"
        XCTAssertEqual(controller.indexedDocumentCount, 2)
        XCTAssertEqual(controller.results.map(\.dateKey), ["2026-08-01"])

        pages["2026-08-03"] = page("2026-08-03", "alpha follow up")
        controller.rebuildIndex(with: pages)
        XCTAssertEqual(controller.results.map(\.dateKey), ["2026-08-03", "2026-08-01"])

        controller.releaseIndex()
        XCTAssertEqual(controller.indexedDocumentCount, 0)
        XCTAssertTrue(controller.results.isEmpty)
    }

    func testControllerKeyboardSelectionStopsAtFirstAndLastResults() {
        let controller = NoteSearchController()
        controller.rebuildIndex(with: [
            "2026-08-01": page("2026-08-01", "shared result"),
            "2026-08-02": page("2026-08-02", "shared result")
        ])
        controller.query = "shared"

        XCTAssertEqual(controller.selectedResult?.dateKey, "2026-08-02")
        XCTAssertFalse(controller.moveSelection(by: -1))
        XCTAssertEqual(controller.selectedResult?.dateKey, "2026-08-02")

        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.selectedResult?.dateKey, "2026-08-01")

        XCTAssertFalse(controller.moveSelection(by: 1))
        XCTAssertEqual(controller.selectedResult?.dateKey, "2026-08-01")

        controller.moveSelection(by: -1)
        XCTAssertEqual(controller.selectedResult?.dateKey, "2026-08-02")
    }

    func testClearingQueryRemovesResultsAndKeepsIndexReady() {
        let controller = NoteSearchController()
        controller.rebuildIndex(with: [
            "2026-08-01": page("2026-08-01", "shared result")
        ])
        controller.query = "shared"

        XCTAssertFalse(controller.results.isEmpty)
        controller.clearQuery()

        XCTAssertEqual(controller.query, "")
        XCTAssertTrue(controller.results.isEmpty)
        XCTAssertEqual(controller.indexedDocumentCount, 1)
    }

    func testEscapeClearsAQueryBeforeRequestingPopoverDismissal() {
        let controller = NoteSearchController()
        controller.rebuildIndex(with: [
            "2026-08-01": page("2026-08-01", "shared result")
        ])
        controller.query = "shared"

        XCTAssertTrue(controller.handleEscape())
        XCTAssertEqual(controller.query, "")
        XCTAssertTrue(controller.results.isEmpty)
        XCTAssertFalse(controller.handleEscape())
    }

    func testSearchFieldCommandsUseTheAppKitFieldEditorSelectors() {
        XCTAssertEqual(
            NoteSearchFieldCommand.resolve(#selector(NSResponder.moveDown(_:))),
            .moveSelection(offset: 1)
        )
        XCTAssertEqual(
            NoteSearchFieldCommand.resolve(#selector(NSResponder.moveUp(_:))),
            .moveSelection(offset: -1)
        )
        XCTAssertEqual(
            NoteSearchFieldCommand.resolve(#selector(NSResponder.insertNewline(_:))),
            .submit
        )
        XCTAssertEqual(
            NoteSearchFieldCommand.resolve(#selector(NSResponder.cancelOperation(_:))),
            .cancel
        )
        XCTAssertNil(NoteSearchFieldCommand.resolve(#selector(NSResponder.moveLeft(_:))))
    }

    func testKeyboardScrollOnlyRevealsSelectionsOutsideTheViewport() {
        let viewportFrame = CGRect(x: 40, y: 100, width: 300, height: 300)

        XCTAssertNil(
            NoteSearchScrollPolicy.alignment(
                for: CGRect(x: 40, y: 120, width: 300, height: 62),
                viewportFrame: viewportFrame,
                direction: 1
            )
        )
        XCTAssertEqual(
            NoteSearchScrollPolicy.alignment(
                for: CGRect(x: 40, y: 90, width: 300, height: 62),
                viewportFrame: viewportFrame,
                direction: -1
            ),
            .top
        )
        XCTAssertEqual(
            NoteSearchScrollPolicy.alignment(
                for: CGRect(x: 40, y: 370, width: 300, height: 62),
                viewportFrame: viewportFrame,
                direction: 1
            ),
            .bottom
        )
        XCTAssertEqual(
            NoteSearchScrollPolicy.alignment(
                for: nil,
                viewportFrame: viewportFrame,
                direction: -1
            ),
            .top
        )
    }

    func testStationaryPointerDoesNotOverrideKeyboardSelectionAfterScrolling() {
        let keyboardPointerLocation = CGPoint(x: 120, y: 240)

        XCTAssertFalse(
            NoteSearchPointerSelectionPolicy.shouldSelectHoveredResult(
                keyboardPointerLocation: keyboardPointerLocation,
                currentPointerLocation: keyboardPointerLocation
            )
        )
        XCTAssertFalse(
            NoteSearchPointerSelectionPolicy.shouldSelectHoveredResult(
                keyboardPointerLocation: keyboardPointerLocation,
                currentPointerLocation: CGPoint(x: 120.5, y: 240.5)
            )
        )
        XCTAssertTrue(
            NoteSearchPointerSelectionPolicy.shouldSelectHoveredResult(
                keyboardPointerLocation: keyboardPointerLocation,
                currentPointerLocation: CGPoint(x: 124, y: 240)
            )
        )
        XCTAssertTrue(
            NoteSearchPointerSelectionPolicy.shouldSelectHoveredResult(
                keyboardPointerLocation: nil,
                currentPointerLocation: keyboardPointerLocation
            )
        )
    }

    func testSearchPanelPlacementIsIndependentOfCompactNoteWidth() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let compactSearchAnchor = NSRect(x: 250, y: 820, width: 28, height: 28)

        let frame = NoteSearchPanelPlacement.frame(
            panelSize: NSSize(width: 360, height: 351),
            anchorRect: compactSearchAnchor,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.size, NSSize(width: 360, height: 351))
        XCTAssertEqual(frame.midX, compactSearchAnchor.midX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, compactSearchAnchor.minY - 6, accuracy: 0.001)
    }

    func testSearchPanelPlacementClampsToScreenEdges() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 800, height: 600)
        let topLeftAnchor = NSRect(x: 102, y: 620, width: 28, height: 28)

        let frame = NoteSearchPanelPlacement.frame(
            panelSize: NSSize(width: 360, height: 351),
            anchorRect: topLeftAnchor,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.minX, visibleFrame.minX + 8, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY + 8)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY - 8)
    }

    func testIndependentSearchPanelOwnsItsVisibilityAndFixedSize() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")
        let controller = NoteSearchPanelController(appState: appState)

        controller.show(
            relativeTo: NSRect(x: 250, y: 820, width: 28, height: 28),
            noteWindowFrame: NSRect(x: 100, y: 500, width: 320, height: 312)
        )

        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(
            controller.currentPanelFrame?.size,
            NSSize(width: 360, height: 351)
        )
        XCTAssertTrue(appState.isNoteSearchPresented)

        controller.dismiss()

        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(appState.isNoteSearchPresented)
    }

    func testSearchPanelCanBeShownAgainAfterDismissal() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")
        let controller = NoteSearchPanelController(appState: appState)
        let anchor = NSRect(x: 250, y: 820, width: 28, height: 28)

        controller.show(relativeTo: anchor, noteWindowFrame: nil)
        XCTAssertTrue(controller.isVisible)

        controller.dismiss()
        XCTAssertFalse(controller.isVisible)

        controller.show(relativeTo: anchor, noteWindowFrame: nil)
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(appState.isNoteSearchPresented)

        controller.dismiss()
    }

    func testOpeningSearchResultCanReturnToOriginalFutureWorkingDate() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")

        appState.presentNoteSearch()
        appState.openSearchResult("2026-07-28")

        XCTAssertEqual(appState.currentDateKey, "2026-07-28")
        XCTAssertEqual(appState.searchReturnDateKey, "2026-08-10")
        XCTAssertEqual(
            appState.headerReturnState,
            .searchOrigin(dateKey: "2026-08-10")
        )
        XCTAssertFalse(appState.isNoteSearchPresented)

        appState.returnToSearchOrigin()

        XCTAssertEqual(appState.currentDateKey, "2026-08-10")
        XCTAssertNil(appState.searchReturnDateKey)
        XCTAssertEqual(appState.headerReturnState, .today)
    }

    func testOpeningSeveralSearchResultsKeepsTheFirstWorkingDateAsOrigin() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")

        appState.openSearchResult("2026-07-28")
        appState.openSearchResult("2026-06-12")

        XCTAssertEqual(appState.currentDateKey, "2026-06-12")
        XCTAssertEqual(appState.searchReturnDateKey, "2026-08-10")
    }

    func testManualNavigationBackToOriginClearsSearchJourney() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")

        appState.openSearchResult("2026-08-09")
        appState.goToNextDay()

        XCTAssertEqual(appState.currentDateKey, "2026-08-10")
        XCTAssertNil(appState.searchReturnDateKey)
    }

    func testManualNavigationAwayFromSearchResultAlwaysClearsSearchJourney() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")

        appState.openSearchResult("2026-07-28")
        appState.goToPreviousDay()

        XCTAssertEqual(appState.currentDateKey, "2026-07-27")
        XCTAssertNil(appState.searchReturnDateKey)
        XCTAssertEqual(appState.headerReturnState, .today)
    }

    func testSearchReturnStateTakesPrecedenceWhileViewingOffTodayResult() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")

        appState.openSearchResult("2026-07-28")

        XCTAssertFalse(appState.isShowingToday)
        XCTAssertEqual(
            appState.headerReturnState,
            .searchOrigin(dateKey: "2026-08-10")
        )
    }

    func testSearchOpenedFromTodayUsesTodayChipInsteadOfSpecialReturnState() {
        let dateKeyService = DateKeyService()
        let todayDateKey = dateKeyService.todayDateKey()
        let resultDateKey = dateKeyService.dateKey(byAddingDays: -7, to: todayDateKey)!
        let appState = makeAppState(
            lastOpenedDateKey: todayDateKey,
            dateKeyService: dateKeyService
        )

        appState.openSearchResult(resultDateKey)

        XCTAssertEqual(appState.currentDateKey, resultDateKey)
        XCTAssertNil(appState.searchReturnDateKey)
        XCTAssertEqual(appState.headerReturnState, .today)
    }

    func testHeaderReturnStateIsEmptyWhenViewingToday() {
        let dateKeyService = DateKeyService()
        let todayDateKey = dateKeyService.todayDateKey()
        let appState = makeAppState(
            lastOpenedDateKey: todayDateKey,
            dateKeyService: dateKeyService
        )

        XCTAssertEqual(appState.headerReturnState, .none)
    }

    func testReturnChipDateUsesLocalizedMonthAndDayWithoutYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let englishService = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        let chineseService = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertEqual(englishService.shortDisplayTitle(for: "2026-08-12"), "Aug 12")
        XCTAssertEqual(
            englishService.accessibleShortDisplayTitle(for: "2026-08-12"),
            "August 12"
        )
        XCTAssertEqual(chineseService.shortDisplayTitle(for: "2026-08-12"), "8月12日")
        XCTAssertFalse(chineseService.shortDisplayTitle(for: "2026-08-12").contains("2026"))
    }

    func testCompactNavigationDateKeepsLocalizedWeekdayAndDropsYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let englishService = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        let chineseService = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertEqual(
            englishService.compactNavigationTitle(for: "2026-08-12"),
            "Wed, Aug 12"
        )
        let chineseTitle = chineseService.compactNavigationTitle(for: "2026-08-12")
        XCTAssertTrue(chineseTitle.contains("8月12日"))
        XCTAssertTrue(chineseTitle.contains("周三"))
        XCTAssertFalse(chineseTitle.contains("2026"))
        XCTAssertFalse(
            englishService.compactNavigationTitle(for: "2026-08-12").contains("2026")
        )
    }

    func testOpeningCurrentDateFromSearchDoesNotCreateReturnJourney() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")

        appState.openSearchResult("2026-08-10")

        XCTAssertNil(appState.searchReturnDateKey)
    }

    func testSearchShortcutRequiresCommandFWithoutExtraModifiers() {
        XCTAssertTrue(
            NoteSearchShortcut.matches(
                charactersIgnoringModifiers: "f",
                modifierFlags: .command
            )
        )
        XCTAssertFalse(
            NoteSearchShortcut.matches(
                charactersIgnoringModifiers: "f",
                modifierFlags: [.command, .shift]
            )
        )
        XCTAssertFalse(
            NoteSearchShortcut.matches(
                charactersIgnoringModifiers: "f",
                modifierFlags: []
            )
        )
    }

    private func makeAppState(
        lastOpenedDateKey: String,
        dateKeyService: DateKeyService = DateKeyService()
    ) -> AppState {
        let data = AppData(
            schemaVersion: 1,
            pages: [lastOpenedDateKey: page(lastOpenedDateKey, "working note")],
            settings: AppSettings(
                lastOpenedDateKey: lastOpenedDateKey,
                isPinned: false,
                windowFrame: nil
            )
        )
        return AppState(
            dataStore: InMemoryAppDataStore(data: data),
            dateKeyService: dateKeyService
        )
    }

    private func page(_ dateKey: String, _ text: String) -> DayPage {
        DayPage(
            dateKey: dateKey,
            noteText: text,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private final class InMemoryAppDataStore: AppDataStore {
    let dataFileURL = URL(fileURLWithPath: "/tmp/pinaday-search-tests.json")
    private var data: AppData

    init(data: AppData) {
        self.data = data
    }

    func load(defaultDateKey: String) throws -> AppData {
        data
    }

    func save(_ data: AppData) throws {
        self.data = data
    }
}

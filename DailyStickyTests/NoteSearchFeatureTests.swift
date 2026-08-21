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

    func testReturnChipDateUsesUSMonthDayOrderWithoutYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let englishService = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        let britishService = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
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
        XCTAssertEqual(britishService.shortDisplayTitle(for: "2026-08-12"), "Aug 12")
        XCTAssertEqual(
            britishService.accessibleShortDisplayTitle(for: "2026-08-12"),
            "August 12"
        )
        XCTAssertTrue(chineseService.shortDisplayTitle(for: "2026-08-12").contains("8月"))
        XCTAssertTrue(chineseService.shortDisplayTitle(for: "2026-08-12").contains("12"))
        XCTAssertFalse(chineseService.shortDisplayTitle(for: "2026-08-12").contains("2026"))
    }

    func testAllHeaderDatesUseConsistentUSOrdering() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let britishService = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )
        let chineseService = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertEqual(
            britishService.displayTitle(for: "2026-08-12"),
            "Wednesday, August 12, 2026"
        )
        XCTAssertEqual(
            britishService.compactDisplayTitle(for: "2026-08-12"),
            "Aug 12, 2026"
        )
        XCTAssertEqual(
            britishService.compactNavigationTitle(for: "2026-08-12"),
            "Wed, Aug 12"
        )
        let chineseTitle = chineseService.compactNavigationTitle(for: "2026-08-12")
        XCTAssertTrue(chineseTitle.contains("8月"))
        XCTAssertTrue(chineseTitle.contains("12"))
        XCTAssertTrue(chineseTitle.contains("周三"))
        XCTAssertFalse(chineseTitle.contains("2026"))
        XCTAssertFalse(
            britishService.compactNavigationTitle(for: "2026-08-12").contains("2026")
        )
    }

    func testHeaderDateTiersReserveEnoughWidthForEverySupportedLanguage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let representativeDateKeys = [
            "2026-01-28",
            "2026-02-18",
            "2026-08-31",
            "2026-09-30",
            "2026-12-23"
        ]

        for language in AppLanguage.allCases {
            let service = DateKeyService(calendar: calendar, locale: language.locale)
            for dateKey in representativeDateKeys {
                let titles: [(DateHeaderTitleTier, String)] = [
                    (.full, service.displayTitle(for: dateKey)),
                    (.compact, service.compactDisplayTitle(for: dateKey)),
                    (.navigation, service.compactNavigationTitle(for: dateKey))
                ]

                for (tier, title) in titles {
                    XCTAssertLessThanOrEqual(
                        DateHeaderTitleMetrics.measuredWidth(of: title),
                        DateHeaderTitleMetrics.reservedWidth(
                            for: tier,
                            locale: language.locale
                        ),
                        "\(language.rawValue) \(tier.rawValue) title exceeded its stable header width"
                    )
                }
            }
        }
    }

    func testEverySupportedLanguageHasCoreTranslationsAndLocalizedDateOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        for language in AppLanguage.allCases {
            XCTAssertNotEqual(
                language.localized("Settings"),
                language == .english ? "" : "Settings",
                "Missing Settings translation for \(language.rawValue)"
            )
            for key in [
                "Search notes",
                "Go to Note",
                "Go to note",
                "Search notes or enter a date",
                "No matching notes or dates",
                "Empty note",
                "Clear query",
                "Find and Go To",
                "Find in this note",
                "Move through matches",
                "Find text in images",
                "Go to any note",
                "Search by date",
                "Return to your day"
            ] {
                XCTAssertNotEqual(
                    language.localized(key),
                    language == .english ? "" : key,
                    "Missing \(key) translation for \(language.rawValue)"
                )
            }

            let service = DateKeyService(calendar: calendar, locale: language.locale)
            let title = service.displayTitle(for: "2026-08-12")
            XCTAssertTrue(title.contains("2026"))
            XCTAssertTrue(title.contains("12"))
        }

        let english = DateKeyService(calendar: calendar, locale: AppLanguage.english.locale)
        XCTAssertEqual(english.compactNavigationTitle(for: "2026-08-12"), "Wed, Aug 12")

        let chinese = DateKeyService(
            calendar: calendar,
            locale: AppLanguage.simplifiedChinese.locale
        )
        XCTAssertTrue(chinese.compactNavigationTitle(for: "2026-08-12").contains("8月"))

        let japanese = DateKeyService(calendar: calendar, locale: AppLanguage.japanese.locale)
        XCTAssertTrue(japanese.shortDisplayTitle(for: "2026-08-12").contains("8月"))
    }

    func testLanguageSettingPersistsAndImmediatelyUpdatesDateFormatting() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")

        appState.updateLanguage(.french)

        XCTAssertEqual(appState.language, .french)
        XCTAssertEqual(appState.data.settings.language, .french)
        XCTAssertEqual(appState.localized("Today"), "Aujourd’hui")
        XCTAssertTrue(appState.currentDateTitle.localizedCaseInsensitiveContains("août"))
    }

    func testLegacySettingsWithoutLanguageDecodeAsEnglish() throws {
        let json = """
        {
          "lastOpenedDateKey": "2026-08-12",
          "isPinned": true,
          "theme": "yellow",
          "noteOpacity": 1,
          "hasSeenWelcome": true
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.language, .english)
    }

    func testLocalizedMatchCountsCoverSingularPluralAndCJK() {
        XCTAssertEqual(AppLanguage.english.matchCount(1), "1 match")
        XCTAssertEqual(AppLanguage.english.matchCount(3), "3 matches")
        XCTAssertEqual(AppLanguage.french.matchCount(2), "2 résultats")
        XCTAssertEqual(AppLanguage.simplifiedChinese.matchCount(3), "3 个匹配项")
        XCTAssertEqual(AppLanguage.japanese.matchCount(2), "2 件一致")
        XCTAssertEqual(AppLanguage.korean.matchCount(4), "4개 일치")
    }

    func testOpeningCurrentDateFromSearchDoesNotCreateReturnJourney() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")

        appState.openSearchResult("2026-08-10")

        XCTAssertNil(appState.searchReturnDateKey)
    }

    func testOpeningContentSearchResultCreatesPreciseRevealRequest() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")
        let location = NoteSearchMatchLocation.note(range: NSRange(location: 4, length: 6))
        let result = NoteSearchResult(
            dateKey: "2026-08-09",
            snippet: "deploy",
            score: 1,
            matchingLineCount: 1,
            source: .note,
            matchLocation: location
        )

        appState.openSearchResult(result, query: "deploy")

        XCTAssertEqual(appState.currentDateKey, "2026-08-09")
        XCTAssertEqual(appState.noteRevealRequest?.dateKey, "2026-08-09")
        XCTAssertEqual(appState.noteRevealRequest?.query, "deploy")
        XCTAssertEqual(appState.noteRevealRequest?.location, location)
    }

    func testDateNavigationResultDoesNotCreateRevealRequest() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")
        let result = NoteSearchResult(
            dateKey: "2026-08-09",
            snippet: "Sunday, August 9, 2026",
            score: 1,
            matchingLineCount: 0,
            source: .note,
            kind: .date
        )

        appState.openSearchResult(result, query: "Aug 9")

        XCTAssertEqual(appState.currentDateKey, "2026-08-09")
        XCTAssertNil(appState.noteRevealRequest)
    }

    func testManualNavigationAndEditingClearSearchRevealRequest() {
        let appState = makeAppState(lastOpenedDateKey: "2026-08-10")
        let result = NoteSearchResult(
            dateKey: "2026-08-09",
            snippet: "deploy",
            score: 1,
            matchingLineCount: 1,
            source: .note,
            matchLocation: .note(range: NSRange(location: 0, length: 6))
        )

        appState.openSearchResult(result, query: "deploy")
        XCTAssertNotNil(appState.noteRevealRequest)

        appState.updateNoteText("changed")
        XCTAssertNil(appState.noteRevealRequest)

        appState.openSearchResult(result, query: "deploy")
        XCTAssertNotNil(appState.noteRevealRequest)
        appState.goToPreviousDay()
        XCTAssertNil(appState.noteRevealRequest)
    }

    func testCurrentNoteFindShortcutRequiresCommandFWithoutExtraModifiers() {
        XCTAssertTrue(
            CurrentNoteFindShortcut.matches(
                charactersIgnoringModifiers: "f",
                modifierFlags: .command
            )
        )
        XCTAssertFalse(
            CurrentNoteFindShortcut.matches(
                charactersIgnoringModifiers: "f",
                modifierFlags: [.command, .shift]
            )
        )
        XCTAssertFalse(
            CurrentNoteFindShortcut.matches(
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

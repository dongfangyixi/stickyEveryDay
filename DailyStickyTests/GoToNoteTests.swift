import Foundation
import XCTest
@testable import Pinaday

final class GoToNoteTests: XCTestCase {
    func testLocalizedMonthDayQueryFindsExistingDatesAcrossYears() {
        var engine = NoteDateSearchEngine()
        engine.rebuild(
            with: [
                document("2025-08-01", "older plan"),
                document("2026-08-01", "newer plan"),
                document("2026-08-02", "different day")
            ],
            locale: Locale(identifier: "en_US")
        )

        let monthFirstResults = engine.search("Aug 1")
        let dayFirstResults = engine.search("1 Aug")

        XCTAssertEqual(monthFirstResults.map(\.dateKey), ["2026-08-01", "2025-08-01"])
        XCTAssertEqual(dayFirstResults.map(\.dateKey), monthFirstResults.map(\.dateKey))
        XCTAssertTrue(dayFirstResults.allSatisfy { $0.kind == .date })
    }

    func testDateLookupAcceptsEitherComponentOrderWithAYear() {
        var engine = NoteDateSearchEngine()
        engine.rebuild(
            with: [
                document("2025-08-25", "older plan"),
                document("2026-08-25", "current plan")
            ],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(engine.search("Aug 25 2026").first?.dateKey, "2026-08-25")
        XCTAssertEqual(engine.search("25 Aug 2026").first?.dateKey, "2026-08-25")
    }

    func testLocalizedDateLookupDoesNotRequireTheLocaleDisplayOrder() {
        var engine = NoteDateSearchEngine()
        engine.rebuild(
            with: [document("2026-08-25", "plan")],
            locale: Locale(identifier: "fr_FR")
        )

        XCTAssertEqual(engine.search("août 25").first?.dateKey, "2026-08-25")
        XCTAssertEqual(engine.search("25 août").first?.dateKey, "2026-08-25")
    }

    func testDateLookupUsesChineseAndJapaneseLocalizedForms() {
        let documents = [document("2026-08-01", "旅行计划")]
        var chineseEngine = NoteDateSearchEngine()
        chineseEngine.rebuild(
            with: documents,
            locale: Locale(identifier: "zh_Hans_CN")
        )
        var japaneseEngine = NoteDateSearchEngine()
        japaneseEngine.rebuild(
            with: documents,
            locale: Locale(identifier: "ja_JP")
        )

        XCTAssertEqual(chineseEngine.search("8月1日").first?.dateKey, "2026-08-01")
        XCTAssertEqual(japaneseEngine.search("8月1日").first?.dateKey, "2026-08-01")
    }

    func testDateLookupToleratesASmallMonthTypingError() {
        var engine = NoteDateSearchEngine()
        engine.rebuild(
            with: [document("2026-08-01", "travel")],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(engine.search("Augst 1 2026").first?.dateKey, "2026-08-01")
    }

    @MainActor
    func testControllerMergesDateNavigationAndContentSearchWithoutDuplicates() {
        let controller = NoteSearchController()
        controller.rebuildIndex(
            with: [
                document("2026-08-01", "August launch checklist"),
                document("2026-07-12", "deploy billing update")
            ],
            locale: Locale(identifier: "en_US")
        )

        controller.query = "Aug 1"
        XCTAssertEqual(controller.results.map(\.dateKey), ["2026-08-01"])
        XCTAssertEqual(controller.results.first?.kind, .date)

        controller.query = "billing"
        XCTAssertEqual(controller.results.map(\.dateKey), ["2026-07-12"])
        XCTAssertEqual(controller.results.first?.kind, .content)
    }

    @MainActor
    func testControllerKeepsContentResultsSortedByMatchCountThenDate() {
        let controller = NoteSearchController()
        controller.rebuildIndex(with: [
            document("2026-08-22", "transaction ages today"),
            document(
                "2026-08-19",
                "transaction one\ntransaction two\ntransaction three"
            ),
            document("2026-08-15", "transaction-held-across-await")
        ])

        controller.query = "transaction"

        XCTAssertEqual(
            controller.results.map(\.dateKey),
            ["2026-08-19", "2026-08-22", "2026-08-15"]
        )
    }

    func testGoToNoteShortcutIsCommandPOnly() {
        XCTAssertTrue(GoToNoteShortcut.matches(
            charactersIgnoringModifiers: "p",
            modifierFlags: [.command]
        ))
        XCTAssertFalse(GoToNoteShortcut.matches(
            charactersIgnoringModifiers: "f",
            modifierFlags: [.command]
        ))
        XCTAssertFalse(GoToNoteShortcut.matches(
            charactersIgnoringModifiers: "p",
            modifierFlags: [.command, .shift]
        ))
    }

    func testDateLookupAcrossTenThousandNotesStaysLightweight() {
        let calendar = Calendar(identifier: .gregorian)
        let startDate = Date(timeIntervalSince1970: 0)
        let dateService = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        let documents = (0..<10_000).compactMap { offset -> NoteSearchDocument? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }
            return document(dateService.dateKey(for: date), "Daily note \(offset)")
        }

        let buildStart = CFAbsoluteTimeGetCurrent()
        var engine = NoteDateSearchEngine()
        engine.rebuild(with: documents, locale: Locale(identifier: "en_US"))
        let buildDuration = CFAbsoluteTimeGetCurrent() - buildStart

        let searchStart = CFAbsoluteTimeGetCurrent()
        let results = engine.search("May 18 1995")
        let searchDuration = CFAbsoluteTimeGetCurrent() - searchStart

        XCTAssertEqual(results.first?.dateKey, "1995-05-18")
        XCTAssertLessThan(buildDuration, 5.0, "Date index build took \(buildDuration) seconds")
        XCTAssertLessThan(searchDuration, 0.9, "Date lookup took \(searchDuration) seconds")
    }

    private func document(_ dateKey: String, _ text: String) -> NoteSearchDocument {
        NoteSearchDocument(
            dateKey: dateKey,
            text: text,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

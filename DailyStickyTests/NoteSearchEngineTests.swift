import XCTest
@testable import Pinaday

final class NoteSearchEngineTests: XCTestCase {
    func testExactMatchesRankAheadOfFuzzyMatchesAndNewestBreaksTies() {
        let engine = NoteSearchEngine(documents: [
            document("2026-08-01", "Plan the Vietnam trip"),
            document("2026-08-03", "Vietnam packing list"),
            document("2026-08-04", "Vietman typo in a draft")
        ])

        let results = engine.search("Vietnam")

        XCTAssertEqual(results.map(\.dateKey), ["2026-08-03", "2026-08-01", "2026-08-04"])
    }

    func testEnglishFuzzyMatchToleratesSmallTypingErrors() {
        let engine = NoteSearchEngine(documents: [
            document("2026-08-01", "Prepare the quarterly billing review")
        ])

        XCTAssertEqual(engine.search("bililng revie").first?.dateKey, "2026-08-01")
    }

    func testChineseSearchWorksWithoutWhitespaceTokenBoundaries() {
        let engine = NoteSearchEngine(documents: [
            document("2026-08-01", "完成旅行计划并预订酒店"),
            document("2026-08-02", "整理项目文档")
        ])

        XCTAssertEqual(engine.search("旅行计划").map(\.dateKey), ["2026-08-01"])
        XCTAssertEqual(engine.search("旅行计画").first?.dateKey, "2026-08-01")
    }

    func testJapaneseSearchNormalizesKanaAndCharacterWidth() {
        let engine = NoteSearchEngine(documents: [
            document("2026-08-01", "カタカナのテストと資料レビュー")
        ])

        XCTAssertEqual(engine.search("かたかな").first?.dateKey, "2026-08-01")
        XCTAssertEqual(engine.search("資料ﾚﾋﾞｭｰ").first?.dateKey, "2026-08-01")
    }

    func testMarkdownIsRemovedFromResultSnippetWithoutChangingSearchability() {
        let engine = NoteSearchEngine(documents: [
            document(
                "2026-08-01",
                """
                # Planning
                - [ ] **Book** the hotel
                """
            )
        ])

        let result = engine.search("book hotel").first

        XCTAssertEqual(result?.snippet, "Book the hotel")
        XCTAssertEqual(result?.matchingLineCount, 1)
    }

    func testOneRankedResultIsReturnedPerDayAndBlankPagesAreNotIndexed() {
        let engine = NoteSearchEngine(documents: [
            document("2026-08-01", "alpha first line\nalpha second line"),
            document("2026-08-02", "   \n")
        ])

        XCTAssertEqual(engine.documentCount, 1)
        XCTAssertEqual(engine.search("alpha").count, 1)
        XCTAssertEqual(engine.search("alpha").first?.matchingLineCount, 2)
        XCTAssertEqual(engine.search("alpha").first?.matchCountLabel, "2 matches")
    }

    func testSingleMatchingLineUsesAnExplicitSingularCountLabel() {
        let engine = NoteSearchEngine(documents: [
            document("2026-08-01", "deploy the update")
        ])

        let result = engine.search("deploy").first

        XCTAssertEqual(result?.matchingLineCount, 1)
        XCTAssertEqual(result?.matchCountLabel, "1 match")
    }

    func testResultLimitIsAppliedAfterRanking() {
        let engine = NoteSearchEngine(documents: (1...20).map { index in
            document(String(format: "2026-08-%02d", index), "shared query \(index)")
        })

        let results = engine.search("shared query", limit: 5)

        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(results.first?.dateKey, "2026-08-20")
    }

    func testSearchAcrossTenThousandNotesStaysLightweight() {
        let documents = (0..<10_000).map { index in
            document(
                String(format: "synthetic-%05d", index),
                "Daily planning note \(index) with project status and follow up tasks"
            )
        } + [document("2027-12-31", "稀有目标词 quarterlyneedle")]

        let buildStart = CFAbsoluteTimeGetCurrent()
        let engine = NoteSearchEngine(documents: documents)
        let buildDuration = CFAbsoluteTimeGetCurrent() - buildStart

        let searchStart = CFAbsoluteTimeGetCurrent()
        let results = engine.search("quarterlynedle")
        let searchDuration = CFAbsoluteTimeGetCurrent() - searchStart

        XCTAssertEqual(engine.documentCount, 10_001)
        XCTAssertEqual(results.first?.dateKey, "2027-12-31")
        XCTAssertLessThan(buildDuration, 4.0, "Index build took \(buildDuration) seconds")
        XCTAssertLessThan(searchDuration, 0.75, "Search took \(searchDuration) seconds")
    }

    func testFuzzyCJKSearchAcrossFiveThousandNotesStaysLightweight() {
        let documents = (0..<5_000).map { index in
            document(
                String(format: "cjk-%05d", index),
                "整理项目资料并完成每周计划第\(index)项"
            )
        } + [document("2027-12-30", "准备旅行计划并预订酒店")]
        let engine = NoteSearchEngine(documents: documents)

        let searchStart = CFAbsoluteTimeGetCurrent()
        let results = engine.search("旅行计画")
        let searchDuration = CFAbsoluteTimeGetCurrent() - searchStart

        XCTAssertEqual(results.first?.dateKey, "2027-12-30")
        XCTAssertLessThan(searchDuration, 1.25, "CJK search took \(searchDuration) seconds")
    }

    private func document(_ dateKey: String, _ text: String) -> NoteSearchDocument {
        NoteSearchDocument(dateKey: dateKey, text: text, updatedAt: Date(timeIntervalSince1970: 0))
    }
}

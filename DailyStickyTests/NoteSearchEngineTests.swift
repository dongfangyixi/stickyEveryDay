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
        XCTAssertEqual(engine.search("alpha").first?.matchCountLabel(language: .english), "2 matches")
    }

    func testSingleMatchingLineUsesAnExplicitSingularCountLabel() {
        let engine = NoteSearchEngine(documents: [
            document("2026-08-01", "deploy the update")
        ])

        let result = engine.search("deploy").first

        XCTAssertEqual(result?.matchingLineCount, 1)
        XCTAssertEqual(result?.matchCountLabel(language: .english), "1 match")
    }

    func testResultLimitIsAppliedAfterRanking() {
        let engine = NoteSearchEngine(documents: (1...20).map { index in
            document(String(format: "2026-08-%02d", index), "shared query \(index)")
        })

        let results = engine.search("shared query", limit: 5)

        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(results.first?.dateKey, "2026-08-20")
    }

    func testSynchronizeReusesUnchangedDocumentsAndUpdatesOnlyChangedDates() {
        let first = document("2026-08-01", "alpha note")
        let second = document("2026-08-02", "beta note")
        var engine = NoteSearchEngine(documents: [first, second])

        XCTAssertEqual(
            engine.synchronize(with: [first, second]),
            NoteSearchIndexUpdate(insertedOrUpdatedCount: 0, removedCount: 0)
        )

        let changedSecond = document("2026-08-02", "gamma note")
        XCTAssertEqual(
            engine.synchronize(with: [changedSecond]),
            NoteSearchIndexUpdate(insertedOrUpdatedCount: 1, removedCount: 1)
        )
        XCTAssertTrue(engine.search("alpha").isEmpty)
        XCTAssertEqual(engine.search("gamma").map(\.dateKey), ["2026-08-02"])
    }

    func testDateSearchSynchronizeReusesAliasesAndRefreshesThePreview() {
        let locale = Locale(identifier: "en_US")
        var engine = NoteDateSearchEngine()
        engine.rebuild(
            with: [document("2026-08-12", "# Original preview\nolder details")],
            locale: locale
        )

        XCTAssertEqual(engine.search("Aug 12 2026").first?.snippet, "Original preview")

        engine.synchronize(
            with: [document("2026-08-12", "\n**Updated preview**\nnew details")],
            locale: locale
        )

        let result = engine.search("Aug 12 2026").first
        XCTAssertEqual(result?.dateKey, "2026-08-12")
        XCTAssertEqual(result?.snippet, "Updated preview")
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

    func testLargeMixedCorpusSearchAndReopenStayInteractive() {
        let documents = benchmarkDocuments()
        let buildStart = CFAbsoluteTimeGetCurrent()
        var engine = NoteSearchEngine(documents: documents)
        var dateEngine = NoteDateSearchEngine()
        dateEngine.rebuild(with: documents, locale: Locale(identifier: "en_US"))
        let buildDuration = CFAbsoluteTimeGetCurrent() - buildStart
        let queries = ["project", "proejct", "旅行计画", "ocrneedle", "Aug 12 2025"]

        var durations: [String: TimeInterval] = [:]
        for query in queries {
            let searchStart = CFAbsoluteTimeGetCurrent()
            _ = engine.search(query, limit: 40)
            _ = dateEngine.search(query, limit: 40)
            durations[query] = CFAbsoluteTimeGetCurrent() - searchStart
        }

        let reopenStart = CFAbsoluteTimeGetCurrent()
        let update = engine.synchronize(with: documents)
        let reopenDuration = CFAbsoluteTimeGetCurrent() - reopenStart

        XCTAssertEqual(update, NoteSearchIndexUpdate(insertedOrUpdatedCount: 0, removedCount: 0))
        XCTAssertEqual(engine.search("ocrneedle").first?.dateKey, "2026-12-31")
        XCTAssertEqual(dateEngine.search("Aug 12 2025").first?.dateKey, "2025-08-12")
        XCTAssertLessThan(buildDuration, 1.0, "Mixed index build took \(buildDuration) seconds")
        XCTAssertLessThan(reopenDuration, 0.1, "Unchanged reopen took \(reopenDuration) seconds")
        for (query, duration) in durations {
            XCTAssertLessThan(duration, 0.35, "Search for \(query) took \(duration) seconds")
        }

    }

    private func benchmarkDocuments() -> [NoteSearchDocument] {
        var documents = (0..<1_000).map { index in
            document(
                String(
                    format: "%04d-%02d-%02d",
                    2024 + index / 336,
                    (index % 336) / 28 + 1,
                    index % 28 + 1
                ),
                "Daily project planning note \(index) with deployment status, follow up tasks, and review notes."
            )
        }
        let article = (0..<600).map { line in
            "Section \(line) discusses project architecture, searchable records, deployment, and performance."
        }.joined(separator: "\n")
        documents.append(
            NoteSearchDocument(
                dateKey: "2026-12-31",
                text: article + "\n准备旅行计划并预订酒店",
                updatedAt: .distantPast,
                supplementalLines: [
                    NoteSearchSupplementalLine(
                        text: "OCR screenshot contains ocrneedle and billing details",
                        source: .image(attachmentPath: "attachments/benchmark.png")
                    )
                ]
            )
        )
        return documents
    }

    private func document(_ dateKey: String, _ text: String) -> NoteSearchDocument {
        NoteSearchDocument(dateKey: dateKey, text: text, updatedAt: Date(timeIntervalSince1970: 0))
    }
}

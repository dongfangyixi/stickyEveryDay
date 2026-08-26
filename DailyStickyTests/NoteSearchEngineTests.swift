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

        XCTAssertEqual(results.map(\.dateKey), ["2026-08-03", "2026-08-01"])
    }

    func testEnglishFuzzyMatchToleratesSmallTypingErrors() {
        let engine = NoteSearchEngine(documents: [
            document("2026-08-01", "Prepare the quarterly billing review"),
            document("2026-08-02", "Review notes for the billing meeting")
        ])

        XCTAssertEqual(engine.search("bililng revie").first?.dateKey, "2026-08-01")
        XCTAssertEqual(engine.search("billing meeting").first?.dateKey, "2026-08-02")
    }

    func testMultiwordQueryDoesNotMatchAParagraphWithOnlyCommonWords() {
        let paragraph = """
        Two ground rules for the rig first. Its hidden variables are put in by hand — that is what a rig is — but each one has been verified on real robots: demonstrator style is a measured training hazard at industrial scale<sup><a href="#ref-28">[28]</a></sup>, and the overfitting itself is documented in industrial ablations up to 100,000 action-hours<sup><a href="#ref-4">[4]</a></sup>; the rig exists to isolate the mechanism, not to prove the phenomenon. And its knobs set its multipliers — export the shape of each result, not the constants.
        """
        let engine = NoteSearchEngine(documents: [
            document("2026-08-25", paragraph)
        ])

        XCTAssertTrue(engine.search("find me the").isEmpty)
    }

    func testMultiwordQueryDoesNotCombineTokensAcrossSeparateLines() {
        let engine = NoteSearchEngine(documents: [
            document(
                "2026-08-25",
                "find the deployment notes\nmeasured results\nthe final report"
            )
        ])

        XCTAssertTrue(engine.search("find me the").isEmpty)
    }

    func testMultiwordQueryDoesNotTreatAnApproximateSubstringAsAWordTypo() {
        let unrelated = """
        With LPT also off (your finding — now the code default, see below), the final config measured
        """
        let engine = NoteSearchEngine(documents: [
            document("2026-08-24", unrelated),
            document("2026-08-25", "Document the finding and fix before release")
        ])

        XCTAssertEqual(engine.search("find fix").map(\.dateKey), ["2026-08-25"])
        XCTAssertEqual(engine.search("find fiz").map(\.dateKey), ["2026-08-25"])
    }

    func testExactTransactionDoesNotMatchSimilarTranslationWords() {
        let engine = NoteSearchEngine(documents: [
            document(
                "2026-08-21",
                "- [x] document translation cloud version credit verification"
            ),
            document(
                "2026-08-22",
                "That same study finds generalization with a striking practical translation."
            ),
            document(
                "2026-08-23",
                "- [ ] blog must release, or just for a paper translation is good."
            ),
            document(
                "2026-08-24",
                "Use the transaction-held-across-await path"
            )
        ])

        let results = engine.search("transaction")

        XCTAssertEqual(results.map(\.dateKey), ["2026-08-24"])
        XCTAssertEqual(results.first?.snippet, "Use the transaction-held-across-await path")
    }

    func testExactTransactionLineWinsInsideANoteContainingTranslationText() {
        let engine = NoteSearchEngine(documents: [
            document(
                "2026-08-24",
                """
                - [x] document translation cloud version credit verification
                A practical translation appears in this paragraph.
                Use the transaction-held-across-await path
                """
            )
        ])

        let result = engine.search("transaction").first

        XCTAssertEqual(result?.dateKey, "2026-08-24")
        XCTAssertEqual(result?.snippet, "Use the transaction-held-across-await path")
    }

    func testTwoLetterQueryRequiresACompleteToken() {
        let engine = NoteSearchEngine(documents: [
            document("2026-08-24", "The mechanism was measured carefully"),
            document("2026-08-25", "Send me the report")
        ])

        XCTAssertEqual(engine.search("me").map(\.dateKey), ["2026-08-25"])
        XCTAssertEqual(engine.search("send me the").map(\.dateKey), ["2026-08-25"])
    }

    func testSearchQualityPrecisionAndRecallAcrossRepresentativeCorpus() {
        let documents = [
            document("exact-transaction", "Use the transaction-held-across-await path"),
            document("translation-task", "- [x] document translation cloud version credit verification"),
            document("translation-article", "A practical translation appears in this paper."),
            document("affect", "Measure how lighting can affect the result"),
            document("effect", "Measure the lighting effect on the result"),
            document("form", "Submit the reimbursement form"),
            document("from", "Collect the package from reception"),
            document("find-fix", "Document the finding and fix before release"),
            document("finding-final", "The finding is included in the final configuration"),
            document("deployment", "Review the project deployment status"),
            document("separate-lines", "find the notes\nmeasured output\nthe final report"),
            document("quarterly", "Track the quarterlyneedle benchmark"),
            document("short-token", "Send me the report"),
            document("zh-trip", "完成旅行计划并预订酒店"),
            document("zh-docs", "整理项目文档并检查数据"),
            document("ja-review", "カタカナのテストと資料レビュー"),
            document("ko-review", "배포 전에 자료 검토를 완료하세요"),
            document("es-meeting", "Preparar la reunión de planificación"),
            document("fr-billing", "Vérifier la facturation du client"),
            document("markdown", "- [ ] **Book** the hotel for Friday"),
            NoteSearchDocument(
                dateKey: "ocr-invoice",
                text: "Accounting screenshot",
                updatedAt: .distantPast,
                supplementalLines: [
                    NoteSearchSupplementalLine(
                        text: "Invoice total USD 420",
                        source: .image(attachmentPath: "attachments/invoice.png")
                    )
                ]
            )
        ]
        let cases: [(query: String, relevant: Set<String>)] = [
            ("transaction", ["exact-transaction"]),
            ("translation", ["translation-task", "translation-article"]),
            ("affect", ["affect"]),
            ("effect", ["effect"]),
            ("form", ["form"]),
            ("from", ["from"]),
            ("find fix", ["find-fix"]),
            ("find fiz", ["find-fix"]),
            ("project deployment", ["deployment"]),
            ("proejct deployment", ["deployment"]),
            ("find me the", []),
            ("quarterlynedle", ["quarterly"]),
            ("me", ["short-token"]),
            ("旅行计划", ["zh-trip"]),
            ("旅行计画", ["zh-trip"]),
            ("かたかな", ["ja-review"]),
            ("자료 검토", ["ko-review"]),
            ("reunion", ["es-meeting"]),
            ("facturation", ["fr-billing"]),
            ("book hotel", ["markdown"]),
            ("invoice 420", ["ocr-invoice"])
        ]
        let engine = NoteSearchEngine(documents: documents)
        var precisionTotal = 0.0
        var recallTotal = 0.0

        for qualityCase in cases {
            let retrieved = Set(engine.search(qualityCase.query, limit: 100).map(\.dateKey))
            let truePositives = retrieved.intersection(qualityCase.relevant).count
            let precision = retrieved.isEmpty
                ? (qualityCase.relevant.isEmpty ? 1.0 : 0.0)
                : Double(truePositives) / Double(retrieved.count)
            let recall = qualityCase.relevant.isEmpty
                ? (retrieved.isEmpty ? 1.0 : 0.0)
                : Double(truePositives) / Double(qualityCase.relevant.count)
            precisionTotal += precision
            recallTotal += recall

            XCTAssertEqual(
                retrieved,
                qualityCase.relevant,
                "Unexpected results for query: \(qualityCase.query)"
            )
        }

        let macroPrecision = precisionTotal / Double(cases.count)
        let macroRecall = recallTotal / Double(cases.count)
        XCTAssertGreaterThanOrEqual(macroPrecision, 0.95)
        XCTAssertGreaterThanOrEqual(macroRecall, 0.95)
    }

    func testFuzzyTypoPrecisionAndRecallAcrossProductVocabulary() {
        let vocabulary: [(word: String, typo: String)] = [
            ("architecture", "architecure"),
            ("deployment", "deplyoment"),
            ("transaction", "transction"),
            ("subscription", "subscripton"),
            ("verification", "verfication"),
            ("performance", "perfomance"),
            ("repository", "repositroy"),
            ("synchronization", "synchonization"),
            ("invoice", "invioce"),
            ("calendar", "calender"),
            ("accessibility", "accesibility"),
            ("environment", "enviroment")
        ]
        let documents = vocabulary.enumerated().map { index, item in
            document("vocabulary-\(index)", "Review the \(item.word) implementation")
        } + [
            document("distractor-translation", "Complete the document translation"),
            document("distractor-performance", "Prepare the quarterly presentation"),
            document("distractor-environment", "Update the runtime variables")
        ]
        let engine = NoteSearchEngine(documents: documents)
        var truePositiveCount = 0
        var retrievedCount = 0

        for (index, item) in vocabulary.enumerated() {
            let retrieved = Set(engine.search(item.typo, limit: 100).map(\.dateKey))
            let expected = Set(["vocabulary-\(index)"])
            truePositiveCount += retrieved.intersection(expected).count
            retrievedCount += retrieved.count
            XCTAssertEqual(retrieved, expected, "Unexpected results for typo: \(item.typo)")
        }

        let precision = Double(truePositiveCount) / Double(max(retrievedCount, 1))
        let recall = Double(truePositiveCount) / Double(vocabulary.count)
        XCTAssertGreaterThanOrEqual(precision, 0.95)
        XCTAssertGreaterThanOrEqual(recall, 0.95)
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

    func testMatchCountIncludesEveryOccurrenceOnTheSameLine() {
        let engine = NoteSearchEngine(documents: [
            document("2026-08-19", "transaction then another transaction")
        ])

        let result = engine.search("transaction").first

        XCTAssertEqual(result?.matchingLineCount, 2)
        XCTAssertEqual(result?.matchCountLabel(language: .english), "2 matches")
    }

    func testResultLimitIsAppliedAfterRanking() {
        let engine = NoteSearchEngine(documents: (1...20).map { index in
            document(String(format: "2026-08-%02d", index), "shared query \(index)")
        })

        let results = engine.search("shared query", limit: 5)

        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(results.first?.dateKey, "2026-08-20")
    }

    func testResultsSortByMatchCountThenNewestDate() {
        let engine = NoteSearchEngine(documents: [
            document("2026-08-22", "transaction ages today"),
            document(
                "2026-08-19",
                "transaction one\ntransaction two\ntransaction three"
            ),
            document("2026-08-15", "transaction-held-across-await")
        ])

        let results = engine.search("transaction")

        XCTAssertEqual(results.map(\.dateKey), ["2026-08-19", "2026-08-22", "2026-08-15"])
        XCTAssertEqual(results.map(\.matchingLineCount), [3, 1, 1])
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

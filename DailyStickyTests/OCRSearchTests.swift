import CoreGraphics
import Foundation
import XCTest
@testable import Pinaday

final class OCRSearchTests: XCTestCase {
    func testMarkdownImageParserFindsImagePathsAndPreservesWidth() {
        let markdown = """
        regular text
        ![diagram](attachments/2026-08-19/image-one.png){width=420}
        ![](attachments/2026-08-19/image-two.png)
        """

        let references = MarkdownImageReferenceParser.references(in: markdown)

        XCTAssertEqual(references.count, 2)
        XCTAssertEqual(references[0].altText, "diagram")
        XCTAssertEqual(references[0].path, "attachments/2026-08-19/image-one.png")
        XCTAssertEqual(references[0].width, 420)
        XCTAssertEqual(references[1].path, "attachments/2026-08-19/image-two.png")
    }

    func testOCRRepositoryCachesRecognitionAndInvalidatesWhenImageChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("image.png")
        let cacheURL = directory.appendingPathComponent("ocr-cache.json")
        try Data([1, 2, 3]).write(to: imageURL)

        let recognizer = StubOCRRecognizer(outputs: [
            [observation("first recognized value")],
            [observation("updated recognized value")]
        ])
        let repository = ImageOCRRepository(
            recognizer: recognizer,
            imageURL: { _ in imageURL },
            cacheURL: cacheURL
        )

        let first = await repository.observations(for: "attachments/image.png")
        let cached = await repository.observations(for: "attachments/image.png")

        XCTAssertEqual(first.map(\.text), ["first recognized value"])
        XCTAssertEqual(cached, first)
        let cachedCallCount = await recognizer.callCount()
        XCTAssertEqual(cachedCallCount, 1)

        try Data([1, 2, 3, 4, 5]).write(to: imageURL, options: .atomic)
        let updated = await repository.observations(for: "attachments/image.png")

        XCTAssertEqual(updated.map(\.text), ["updated recognized value"])
        let updatedCallCount = await recognizer.callCount()
        XCTAssertEqual(updatedCallCount, 2)
    }

    func testOCRCacheSurvivesRepositoryRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("image.png")
        let cacheURL = directory.appendingPathComponent("ocr-cache.json")
        try Data([7, 8, 9]).write(to: imageURL)

        let firstRecognizer = StubOCRRecognizer(outputs: [[observation("persisted OCR")]])
        let firstRepository = ImageOCRRepository(
            recognizer: firstRecognizer,
            imageURL: { _ in imageURL },
            cacheURL: cacheURL
        )
        _ = await firstRepository.observations(for: "attachments/image.png")

        let secondRecognizer = StubOCRRecognizer(outputs: [[observation("should not run")]])
        let secondRepository = ImageOCRRepository(
            recognizer: secondRecognizer,
            imageURL: { _ in imageURL },
            cacheURL: cacheURL
        )
        let restored = await secondRepository.observations(for: "attachments/image.png")

        XCTAssertEqual(restored.map(\.text), ["persisted OCR"])
        let restoredCallCount = await secondRecognizer.callCount()
        XCTAssertEqual(restoredCallCount, 0)
    }

    func testOCRIndexerMakesRecognizedTextSearchableAsAnImageMatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let attachmentPath = "attachments/2026-08-19/receipt.png"
        let imageURL = directory.appendingPathComponent("receipt.png")
        try Data([1]).write(to: imageURL)
        let recognizer = StubOCRRecognizer(outputs: [[
            observation("Invoice total 438 dollars"),
            observation("Payment received")
        ]])
        let repository = ImageOCRRepository(
            recognizer: recognizer,
            imageURL: { _ in imageURL },
            cacheURL: nil
        )
        let indexer = OCRSearchIndexer(repository: repository)
        let page = DayPage(
            dateKey: "2026-08-19",
            noteText: "Today receipt\n![](\(attachmentPath)){width=300}",
            createdAt: .distantPast,
            updatedAt: .distantPast
        )

        let documents = await indexer.documents(for: [page.dateKey: page])
        let engine = NoteSearchEngine(documents: documents)
        let result = engine.search("invoice 438").first

        XCTAssertEqual(result?.dateKey, page.dateKey)
        XCTAssertEqual(result?.snippet, "Invoice total 438 dollars")
        XCTAssertEqual(result?.source, .image(attachmentPath: attachmentPath))
    }

    func testRepeatedImageReferenceIsRecognizedOnlyOncePerIndexBuild() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("shared.png")
        try Data([1]).write(to: imageURL)
        let recognizer = StubOCRRecognizer(outputs: [[observation("shared image text")]])
        let repository = ImageOCRRepository(
            recognizer: recognizer,
            imageURL: { _ in imageURL },
            cacheURL: nil
        )
        let indexer = OCRSearchIndexer(repository: repository)
        let pages = Dictionary(uniqueKeysWithValues: (1...100).map { day in
            let dateKey = String(format: "2026-09-%03d", day)
            return (
                dateKey,
                DayPage(
                    dateKey: dateKey,
                    noteText: "![](attachments/shared.png)",
                    createdAt: .distantPast,
                    updatedAt: .distantPast
                )
            )
        })

        _ = await indexer.documents(for: pages)

        let callCount = await recognizer.callCount()
        XCTAssertEqual(callCount, 1)
    }

    private func observation(_ text: String) -> OCRTextObservation {
        OCRTextObservation(
            text: text,
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.1),
            characterBoxes: []
        )
    }
}

private actor StubOCRRecognizer: ImageOCRRecognizing {
    private var outputs: [[OCRTextObservation]]
    private var calls = 0

    init(outputs: [[OCRTextObservation]]) {
        self.outputs = outputs
    }

    func recognizeText(in imageURL: URL) async -> [OCRTextObservation] {
        defer { calls += 1 }
        guard !outputs.isEmpty else {
            return []
        }
        return outputs.removeFirst()
    }

    func callCount() -> Int {
        calls
    }
}

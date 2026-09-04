import CloudKit
import XCTest
import UIKit
@testable import Pinaday

final class PinadayIOSFoundationTests: XCTestCase {
    func testDialUsesTheApprovedCompactGeometry() {
        XCTAssertEqual(IOSDateDialMetrics.width, 184)
        XCTAssertEqual(IOSDateDialMetrics.height, 40)
        XCTAssertEqual(IOSDateDialMetrics.numberPitch, 46)
        XCTAssertEqual(IOSDateDialMetrics.selectedWidth, 92)
        XCTAssertEqual(IOSDateDialMetrics.anglePerDay, 20)
        XCTAssertEqual(IOSDateDialMetrics.dragPointsPerDay, 44)
        XCTAssertEqual(IOSDateDialMetrics.perspective, 300)
        XCTAssertEqual(IOSDateDialMetrics.maximumFlickDays, 5)
    }

    func testDialDragRotatesInTheExpectedDirection() {
        XCTAssertEqual(IOSDateDialMetrics.rotation(for: -44), 20)
        XCTAssertEqual(IOSDateDialMetrics.rotation(for: 44), -20)
    }

    func testDialProjectionCurvesAndCullsFaces() {
        let center = IOSDateDialMetrics.projection(offset: 0, visualRotation: 0)
        let neighbor = IOSDateDialMetrics.projection(offset: 1, visualRotation: 0)
        let hidden = IOSDateDialMetrics.projection(offset: 3, visualRotation: 0)

        XCTAssertEqual(center.x, 0, accuracy: 0.001)
        XCTAssertEqual(center.scaleX, 1, accuracy: 0.001)
        XCTAssertTrue(neighbor.isVisible)
        XCTAssertGreaterThan(neighbor.x, 0)
        XCTAssertLessThan(neighbor.scaleX, center.scaleX)
        XCTAssertFalse(hidden.isVisible)
    }

    func testTodayFaceDoesNotDuplicateAtTheRim() {
        let visible = IOSDateDialMetrics.visibleOffsets(
            visualRotation: 0,
            todayOffset: 2
        )

        XCTAssertFalse(visible.contains(2))
        XCTAssertTrue(visible.contains(0))
    }

    func testEastAsianTickerUsesBareDayAndMonthDayWeekdayOrder() throws {
        let calendar = Calendar(identifier: .gregorian)
        let service = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "zh_Hans_CN")
        )
        let content = try XCTUnwrap(service.tickerFaceContent(for: "2026-09-03"))

        XCTAssertEqual(content.day, "3")
        XCTAssertEqual(content.order, .monthDayWeekday)
    }

    func testOrdinaryNumberedTextIsNotTreatedAsATask() {
        let text = "1. "
        XCTAssertTrue(MarkdownTaskParser.todoLines(in: text).isEmpty)
        XCTAssertNil(
            MarkdownTaskParser.newlineEdit(
                in: text,
                selectedRange: NSRange(location: (text as NSString).length, length: 0)
            )
        )
    }

    func testFreshInstallLanguageUsesTheFirstSupportedSystemLanguage() {
        XCTAssertEqual(
            IOSSystemLanguageResolver.language(for: ["it-IT", "ja-JP", "en-US"]),
            .japanese
        )
        XCTAssertEqual(
            IOSSystemLanguageResolver.language(for: ["pt-PT"]),
            .portugueseBrazil
        )
        XCTAssertEqual(
            IOSSystemLanguageResolver.language(for: ["it-IT"]),
            .english
        )
    }

    func testImageDataIsSavedAndReadableFromIOSApplicationSupport() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 8, height: 8)))
        }
        let data = try XCTUnwrap(image.pngData())
        let path = try AttachmentStore.saveImageData(data, dateKey: "2099-12-31")
        let url = try XCTUnwrap(AttachmentStore.imageURL(for: path))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(path.hasPrefix("attachments/2099-12-31/image-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNotNil(UIImage(contentsOfFile: url.path))
        XCTAssertTrue(AttachmentStore.syncSnapshot().contains { $0.relativePath == path })

        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(AttachmentStore.syncSnapshot().contains { $0.relativePath == path })
    }

    func testRoutineCloudFetchExcludesAssetsButKeepsAttachmentMetadata() {
        XCTAssertFalse(
            CloudKitSyncService.remoteSnapshotDesiredKeys.contains(
                CloudKitSyncService.Schema.file
            )
        )
        XCTAssertTrue(
            CloudKitSyncService.remoteSnapshotDesiredKeys.contains(
                CloudKitSyncService.Schema.relativePath
            )
        )
        XCTAssertEqual(
            Set(CloudKitSyncService.attachmentAssetDesiredKeys),
            [
                CloudKitSyncService.Schema.relativePath,
                CloudKitSyncService.Schema.file
            ]
        )
        XCTAssertEqual(CloudKitSyncService.attachmentFetchBatchSize, 200)
    }

    func testOnlyAttachmentsMissingFromIOSStorageAreDownloaded() throws {
        let fileManager = FileManager.default
        let existingURL = fileManager.temporaryDirectory
            .appendingPathComponent("pinaday-existing-\(UUID().uuidString).png")
        try Data("present".utf8).write(to: existingURL)
        defer { try? fileManager.removeItem(at: existingURL) }

        let existingPath = "attachments/2026-09-04/existing.png"
        let missingPath = "attachments/2026-09-04/missing.png"
        let localAttachments = CloudKitSyncService.existingLocalAttachments(
            in: [
                CloudAttachment(
                    relativePath: existingPath,
                    fileURL: existingURL,
                    modifiedAt: Date()
                ),
                CloudAttachment(
                    relativePath: missingPath,
                    fileURL: existingURL.appendingPathExtension("deleted"),
                    modifiedAt: Date()
                )
            ]
        )
        let zoneID = CKRecordZone.ID(
            zoneName: CloudKitSyncService.Schema.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let existingRecord = cloudAttachmentRecord(
            name: "attachment-existing",
            relativePath: existingPath,
            zoneID: zoneID
        )
        let missingRecord = cloudAttachmentRecord(
            name: "attachment-missing",
            relativePath: missingPath,
            zoneID: zoneID
        )

        let recordIDs = CloudKitSyncService.attachmentRecordIDsToDownload(
            from: [existingRecord, missingRecord],
            localPaths: Set(localAttachments.map(\.relativePath))
        )

        XCTAssertEqual(localAttachments.map(\.relativePath), [existingPath])
        XCTAssertEqual(recordIDs, [missingRecord.recordID])
    }

    func testAttachmentUploadRecordRestoresOnSecondIOSDeviceSnapshot() throws {
        let fileManager = FileManager.default
        let testID = UUID().uuidString
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("pinaday-ios-cloud-round-trip-\(testID)", isDirectory: true)
        let sourceURL = temporaryDirectory.appendingPathComponent("source.bin")
        let cloudAssetURL = temporaryDirectory.appendingPathComponent("cloud-asset.bin")
        let relativePath = "attachments/ios-cloud-round-trip-\(testID)/image.bin"
        let payload = Data("attachment from iPhone A".utf8)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try payload.write(to: sourceURL)

        let destinationURL = try XCTUnwrap(AttachmentStore.imageURL(for: relativePath))
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
            try? fileManager.removeItem(at: destinationURL.deletingLastPathComponent())
        }

        let deviceAAttachment = CloudAttachment(
            relativePath: relativePath,
            fileURL: sourceURL,
            modifiedAt: Date()
        )
        let uploadedRecord = CloudKitSyncService().attachmentRecord(for: deviceAAttachment)
        let uploadedAsset = try XCTUnwrap(
            uploadedRecord[CloudKitSyncService.Schema.file] as? CKAsset
        )
        let uploadedAssetURL = try XCTUnwrap(uploadedAsset.fileURL)
        try fileManager.copyItem(at: uploadedAssetURL, to: cloudAssetURL)

        try fileManager.removeItem(at: sourceURL)
        uploadedRecord[CloudKitSyncService.Schema.file] = CKAsset(fileURL: cloudAssetURL)
        XCTAssertTrue(
            CloudKitSyncService.existingLocalAttachments(in: [deviceAAttachment]).isEmpty
        )

        try CloudKitSyncService.restoreMissingAttachments(
            from: [uploadedRecord],
            localPaths: []
        )
        XCTAssertEqual(try Data(contentsOf: destinationURL), payload)
    }

    private func cloudAttachmentRecord(
        name: String,
        relativePath: String,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitSyncService.Schema.attachmentRecordType,
            recordID: CKRecord.ID(recordName: name, zoneID: zoneID)
        )
        record[CloudKitSyncService.Schema.relativePath] = relativePath as CKRecordValue
        return record
    }
}

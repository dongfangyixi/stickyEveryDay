import XCTest
@testable import Pinaday

final class AppDataMigrationTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinadayMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        try super.tearDownWithError()
    }

    func testLegacyFixtureMigratesSequentiallyAndPreservesUserContent() throws {
        let originalData = try fixtureData(named: "app-data-v0")
        let dataFileURL = temporaryDirectoryURL.appendingPathComponent("daily-sticky.json")
        try originalData.write(to: dataFileURL)

        let attachmentURL = temporaryDirectoryURL
            .appendingPathComponent("attachments/2026-08-20", isDirectory: true)
            .appendingPathComponent("image-legacy.png")
        try FileManager.default.createDirectory(
            at: attachmentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let attachmentBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        try attachmentBytes.write(to: attachmentURL)

        let store = makeStore()
        let loaded = try store.load(defaultDateKey: "2026-08-20")

        XCTAssertEqual(loaded.schemaVersion, AppData.currentSchemaVersion)
        XCTAssertEqual(loaded.settings.theme, .yellow)
        XCTAssertEqual(loaded.settings.language, .english)
        XCTAssertEqual(loaded.settings.noteOpacity, 1.0)
        XCTAssertEqual(loaded.settings.storageMode, .localOnly)
        XCTAssertEqual(loaded.settings.noteZoom, 1.0)
        XCTAssertFalse(loaded.settings.hasSeenWelcome)
        XCTAssertFalse(loaded.settings.hasChosenStorageMode)

        let note = try XCTUnwrap(loaded.pages["2026-08-20"]?.noteText)
        XCTAssertTrue(note.contains("- [x] Preserve this task"))
        XCTAssertTrue(note.contains("中文和日本語 stay intact."))
        XCTAssertTrue(note.contains("attachments/2026-08-20/image-legacy.png"))
        XCTAssertEqual(try Data(contentsOf: attachmentURL), attachmentBytes)

        let persisted = try AppDataJSONCodec.decode(Data(contentsOf: dataFileURL))
        XCTAssertEqual(persisted, loaded)

        let backups = try backupURLs(containing: "before-v0-to-v2")
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), originalData)
    }

    func testVersionOneMigrationKeepsExistingSettingsInsteadOfReplacingThem() throws {
        var document = try fixtureDocument(named: "app-data-v0")
        document["schemaVersion"] = 1
        var settings = try XCTUnwrap(document["settings"] as? [String: Any])
        settings["theme"] = "dark"
        settings["language"] = "japanese"
        settings["noteOpacity"] = 0.65
        document["settings"] = settings
        try write(document)

        let loaded = try makeStore().load(defaultDateKey: "2026-08-20")

        XCTAssertEqual(loaded.schemaVersion, 2)
        XCTAssertEqual(loaded.settings.theme, .dark)
        XCTAssertEqual(loaded.settings.language, .japanese)
        XCTAssertEqual(loaded.settings.noteOpacity, 0.65)
        XCTAssertEqual(try backupURLs(containing: "before-v1-to-v2").count, 1)
    }

    func testCurrentSchemaLoadsWithoutRewritingOrCreatingBackup() throws {
        let appData = AppData.empty(
            todayDateKey: "2026-08-31",
            now: Date(timeIntervalSince1970: 1_777_777_777)
        )
        let originalData = try AppDataJSONCodec.encode(appData)
        let dataFileURL = temporaryDirectoryURL.appendingPathComponent("daily-sticky.json")
        try originalData.write(to: dataFileURL)

        let loaded = try makeStore().load(defaultDateKey: "2026-08-31")

        XCTAssertEqual(loaded, appData)
        XCTAssertEqual(try Data(contentsOf: dataFileURL), originalData)
        XCTAssertTrue(try backupURLs(containing: "before-").isEmpty)
    }

    func testMalformedDataIsPreservedAndBlocksLaterWrites() throws {
        let originalData = Data("{ definitely not valid JSON".utf8)
        let dataFileURL = temporaryDirectoryURL.appendingPathComponent("daily-sticky.json")
        try originalData.write(to: dataFileURL)
        let store = makeStore()

        XCTAssertThrowsError(try store.load(defaultDateKey: "2026-08-31")) { error in
            guard case StorageError.couldNotPrepareData = error else {
                return XCTFail("Expected couldNotPrepareData, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: dataFileURL), originalData)
        XCTAssertEqual(try backupURLs(containing: "recovery").count, 1)

        XCTAssertThrowsError(
            try store.save(AppData.empty(todayDateKey: "2026-08-31"))
        ) { error in
            guard case StorageError.writesBlocked = error else {
                return XCTFail("Expected writesBlocked, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: dataFileURL), originalData)
    }

    func testNewerSchemaIsNeverDowngradedOrOverwritten() throws {
        var document = try fixtureDocument(named: "app-data-v0")
        document["schemaVersion"] = 99
        let originalData = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        let dataFileURL = temporaryDirectoryURL.appendingPathComponent("daily-sticky.json")
        try originalData.write(to: dataFileURL)
        let store = makeStore()

        XCTAssertThrowsError(try store.load(defaultDateKey: "2026-08-20")) { error in
            guard case StorageError.couldNotPrepareData(_, _, let underlying) = error,
                  case AppDataMigrationError.newerSchema(found: 99, supported: 2) = underlying
            else {
                return XCTFail("Expected newerSchema, got \(error)")
            }
        }

        XCTAssertThrowsError(try store.save(AppData.empty(todayDateKey: "2026-08-20")))
        XCTAssertEqual(try Data(contentsOf: dataFileURL), originalData)
    }

    func testFailedMigrationLeavesOriginalBytesIntactAndBlocksWrites() throws {
        enum ExpectedFailure: Error {
            case stopped
        }

        let originalData = try fixtureData(named: "app-data-v0")
        let dataFileURL = temporaryDirectoryURL.appendingPathComponent("daily-sticky.json")
        try originalData.write(to: dataFileURL)
        let failingPlan = AppDataMigrationPlan(
            currentVersion: 1,
            steps: [
                AppDataMigrationStep(sourceVersion: 0, destinationVersion: 1) { _ in
                    throw ExpectedFailure.stopped
                }
            ]
        )
        let store = makeStore(migrationPlan: failingPlan)

        XCTAssertThrowsError(try store.load(defaultDateKey: "2026-08-20"))
        XCTAssertEqual(try Data(contentsOf: dataFileURL), originalData)
        XCTAssertEqual(try backupURLs(containing: "recovery").count, 1)
        XCTAssertThrowsError(try store.save(AppData.empty(todayDateKey: "2026-08-20")))
        XCTAssertEqual(try Data(contentsOf: dataFileURL), originalData)
    }

    func testDuplicateMigrationStepsFailClosedWithoutChangingTheOriginalFile() throws {
        let originalData = try fixtureData(named: "app-data-v0")
        let dataFileURL = temporaryDirectoryURL.appendingPathComponent("daily-sticky.json")
        try originalData.write(to: dataFileURL)
        let duplicatePlan = AppDataMigrationPlan(
            currentVersion: 1,
            steps: [
                AppDataMigrationStep(sourceVersion: 0, destinationVersion: 1) { document in
                    var migrated = document
                    migrated["schemaVersion"] = 1
                    return migrated
                },
                AppDataMigrationStep(sourceVersion: 0, destinationVersion: 1) { document in
                    var migrated = document
                    migrated["schemaVersion"] = 1
                    return migrated
                }
            ]
        )
        let store = makeStore(migrationPlan: duplicatePlan)

        XCTAssertThrowsError(try store.load(defaultDateKey: "2026-08-20"))
        XCTAssertEqual(try Data(contentsOf: dataFileURL), originalData)
        XCTAssertEqual(try backupURLs(containing: "recovery").count, 1)
        XCTAssertThrowsError(try store.save(AppData.empty(todayDateKey: "2026-08-20")))
        XCTAssertEqual(try Data(contentsOf: dataFileURL), originalData)
    }

    private func makeStore(
        migrationPlan: AppDataMigrationPlan = .production
    ) -> JSONAppDataStore {
        JSONAppDataStore(
            directoryURL: temporaryDirectoryURL,
            migrationPlan: migrationPlan,
            now: { Date(timeIntervalSince1970: 1_777_777_777) }
        )
    }

    private func fixtureData(named name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }

    private func fixtureDocument(named name: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: fixtureData(named: name))
        return try XCTUnwrap(object as? [String: Any])
    }

    private func write(_ document: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        try data.write(to: temporaryDirectoryURL.appendingPathComponent("daily-sticky.json"))
    }

    private func backupURLs(containing text: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: temporaryDirectoryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(text) }
    }
}

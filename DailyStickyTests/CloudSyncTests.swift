import CloudKit
import XCTest
@testable import Pinaday

final class CloudSyncTests: XCTestCase {
    func testRemoteSnapshotFetchExcludesAttachmentAssetData() {
        XCTAssertFalse(
            CloudKitSyncService.remoteSnapshotDesiredKeys.contains(
                CloudKitSyncService.Schema.file
            ),
            "Routine refreshes must not download every CKAsset again"
        )
        XCTAssertEqual(
            Set(CloudKitSyncService.attachmentAssetDesiredKeys),
            [
                CloudKitSyncService.Schema.relativePath,
                CloudKitSyncService.Schema.file
            ]
        )
    }

    func testOnlyMissingLocalAttachmentsAreScheduledForAssetDownload() {
        let zoneID = CKRecordZone.ID(
            zoneName: "PinadayNotes",
            ownerName: CKCurrentUserDefaultName
        )
        let existingAttachment = cloudAttachmentRecord(
            name: "attachment-existing",
            relativePath: "attachments/2026-09-04/existing.png",
            zoneID: zoneID
        )
        let missingAttachment = cloudAttachmentRecord(
            name: "attachment-missing",
            relativePath: "attachments/2026-09-04/missing.png",
            zoneID: zoneID
        )
        let pageRecord = CKRecord(
            recordType: CloudKitSyncService.Schema.pageRecordType,
            recordID: CKRecord.ID(recordName: "page-2026-09-04", zoneID: zoneID)
        )

        let recordIDs = CloudKitSyncService.attachmentRecordIDsToDownload(
            from: [existingAttachment, missingAttachment, pageRecord],
            localPaths: ["attachments/2026-09-04/existing.png"]
        )

        XCTAssertEqual(recordIDs, [missingAttachment.recordID])
    }

    func testStorageDefaultsToLocalOnlyAndRequiresAChoice() throws {
        let json = """
        {
          "lastOpenedDateKey": "2026-08-13",
          "isPinned": true
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.storageMode, .localOnly)
        XCTAssertFalse(settings.hasChosenStorageMode)
    }

    func testFirstCloudMergePreservesDifferentContentFromBothDevices() {
        let local = page("local draft", updatedAt: 20)
        let remote = page("remote draft", updatedAt: 10)

        let result = SyncMergeEngine.merge(
            localPages: [local.dateKey: local],
            remotePages: [remote.dateKey: remote],
            metadata: .empty
        )

        let text = result.pages[local.dateKey]?.noteText ?? ""
        XCTAssertTrue(text.contains("local draft"))
        XCTAssertTrue(text.contains("remote draft"))
        XCTAssertTrue(text.contains("Sync conflict copy"))
        XCTAssertEqual(result.dateKeysToUpload, [local.dateKey])
    }

    func testOnlyRemoteChangeWinsAfterACommonSync() {
        let original = page("original", updatedAt: 10)
        let local = page("original", updatedAt: 10)
        let remote = page("changed elsewhere", updatedAt: 20)
        let metadata = CloudSyncMetadata(
            pageHashes: [original.dateKey: SyncMergeEngine.contentHash(for: original)]
        )

        let result = SyncMergeEngine.merge(
            localPages: [local.dateKey: local],
            remotePages: [remote.dateKey: remote],
            metadata: metadata
        )

        XCTAssertEqual(result.pages[original.dateKey]?.noteText, "changed elsewhere")
        XCTAssertTrue(result.dateKeysToUpload.isEmpty)
    }

    func testOnlyLocalChangeIsUploadedAfterACommonSync() {
        let original = page("original", updatedAt: 10)
        let local = page("changed here", updatedAt: 20)
        let remote = page("original", updatedAt: 10)
        let metadata = CloudSyncMetadata(
            pageHashes: [original.dateKey: SyncMergeEngine.contentHash(for: original)]
        )

        let result = SyncMergeEngine.merge(
            localPages: [local.dateKey: local],
            remotePages: [remote.dateKey: remote],
            metadata: metadata
        )

        XCTAssertEqual(result.pages[original.dateKey]?.noteText, "changed here")
        XCTAssertEqual(result.dateKeysToUpload, [original.dateKey])
    }

    func testIndependentDatesMergeWithoutConflict() {
        let local = page("local", dateKey: "2026-08-12", updatedAt: 20)
        let remote = page("remote", dateKey: "2026-08-13", updatedAt: 20)

        let result = SyncMergeEngine.merge(
            localPages: [local.dateKey: local],
            remotePages: [remote.dateKey: remote],
            metadata: .empty
        )

        XCTAssertEqual(result.pages[local.dateKey], local)
        XCTAssertEqual(result.pages[remote.dateKey], remote)
        XCTAssertEqual(result.dateKeysToUpload, [local.dateKey])
    }

    @MainActor
    func testLocalOnlyModeNeverContactsCloudService() async throws {
        let service = FakeCloudSyncService()
        let store = TestAppDataStore(data: appData(storageMode: .localOnly, hasChosen: true))
        let state = makeAppState(dataStore: store, cloudService: service)

        state.updateNoteText("still private")
        state.saveImmediately()
        try await Task.sleep(nanoseconds: 80_000_000)

        let counts = await service.callCounts
        XCTAssertEqual(counts.account, 0)
        XCTAssertEqual(counts.sync, 0)
        XCTAssertEqual(state.storageMode, .localOnly)
        XCTAssertEqual(state.cloudSyncStatus, .localOnly)
    }

    @MainActor
    func testChoosingICloudKeepsLocalDataAndStartsSync() async throws {
        let didSync = expectation(description: "Cloud sync started")
        let remotePage = page("cloud copy", updatedAt: 30)
        let service = FakeCloudSyncService(
            result: CloudSyncResult(
                pages: [remotePage.dateKey: remotePage],
                metadata: CloudSyncMetadata(
                    pageHashes: [remotePage.dateKey: SyncMergeEngine.contentHash(for: remotePage)]
                ),
                synchronizedAt: Date(timeIntervalSince1970: 40)
            ),
            didSync: didSync
        )
        let store = TestAppDataStore(data: appData(storageMode: .localOnly, hasChosen: false))
        let state = makeAppState(dataStore: store, cloudService: service)

        state.chooseStorageMode(.iCloud)
        await fulfillment(of: [didSync], timeout: 1)
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(state.storageMode, .iCloud)
        XCTAssertTrue(state.hasChosenStorageMode)
        XCTAssertEqual(state.currentPage.noteText, "cloud copy")
        XCTAssertEqual(store.savedData?.settings.storageMode, .iCloud)
        XCTAssertEqual(state.cloudSyncStatus, .upToDate(Date(timeIntervalSince1970: 40)))
    }

    @MainActor
    func testSwitchingBackToLocalOnlyPersistsChoice() async throws {
        let didSync = expectation(description: "Cloud sync started")
        let service = FakeCloudSyncService(didSync: didSync)
        let store = TestAppDataStore(data: appData(storageMode: .localOnly, hasChosen: true))
        let state = makeAppState(dataStore: store, cloudService: service)

        state.chooseStorageMode(.iCloud)
        await fulfillment(of: [didSync], timeout: 1)
        state.chooseStorageMode(.localOnly)

        XCTAssertEqual(state.storageMode, .localOnly)
        XCTAssertEqual(state.cloudSyncStatus, .localOnly)
        XCTAssertEqual(store.savedData?.settings.storageMode, .localOnly)
    }

    @MainActor
    func testSwitchingToLocalOnlyDiscardsAnInFlightCloudResult() async throws {
        let didSync = expectation(description: "Cloud sync started")
        let remotePage = page("stale cloud copy", updatedAt: 30)
        let service = FakeCloudSyncService(
            result: CloudSyncResult(
                pages: [remotePage.dateKey: remotePage],
                metadata: CloudSyncMetadata(
                    pageHashes: [remotePage.dateKey: SyncMergeEngine.contentHash(for: remotePage)]
                ),
                synchronizedAt: Date(timeIntervalSince1970: 40)
            ),
            didSync: didSync,
            delayNanoseconds: 100_000_000
        )
        let store = TestAppDataStore(data: appData(storageMode: .localOnly, hasChosen: true))
        let state = makeAppState(dataStore: store, cloudService: service)

        state.chooseStorageMode(.iCloud)
        await fulfillment(of: [didSync], timeout: 1)
        state.chooseStorageMode(.localOnly)
        try await Task.sleep(nanoseconds: 160_000_000)

        XCTAssertEqual(state.storageMode, .localOnly)
        XCTAssertEqual(state.cloudSyncStatus, .localOnly)
        XCTAssertEqual(state.currentPage.noteText, "local copy")
        XCTAssertEqual(store.savedData?.settings.storageMode, .localOnly)
    }

    @MainActor
    func testTypingWhileSyncIsInFlightCannotBeReplacedByItsOlderResult() async throws {
        let didSync = expectation(description: "Initial cloud sync started")
        let stalePage = page("", updatedAt: 10)
        let service = FakeCloudSyncService(
            result: CloudSyncResult(
                pages: [stalePage.dateKey: stalePage],
                metadata: CloudSyncMetadata(
                    pageHashes: [stalePage.dateKey: SyncMergeEngine.contentHash(for: stalePage)]
                ),
                synchronizedAt: Date(timeIntervalSince1970: 40)
            ),
            didSync: didSync,
            delayNanoseconds: 120_000_000
        )
        let store = TestAppDataStore(
            data: appData(storageMode: .iCloud, hasChosen: true, noteText: "")
        )
        let state = makeAppState(dataStore: store, cloudService: service)

        await fulfillment(of: [didSync], timeout: 1)
        state.updateNoteText("typed while iCloud was syncing")
        try await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertEqual(state.currentPage.noteText, "typed while iCloud was syncing")
        XCTAssertEqual(store.savedData?.pages[state.currentDateKey]?.noteText, "typed while iCloud was syncing")
    }

    @MainActor
    func testConcurrentLocalAndRemoteEditsAreBothPreserved() async throws {
        let didSync = expectation(description: "Initial cloud sync started")
        let remotePage = page("edit from the other device", updatedAt: 30)
        let service = FakeCloudSyncService(
            result: CloudSyncResult(
                pages: [remotePage.dateKey: remotePage],
                metadata: CloudSyncMetadata(
                    pageHashes: [remotePage.dateKey: SyncMergeEngine.contentHash(for: remotePage)]
                ),
                synchronizedAt: Date(timeIntervalSince1970: 40)
            ),
            didSync: didSync,
            delayNanoseconds: 120_000_000
        )
        let store = TestAppDataStore(
            data: appData(storageMode: .iCloud, hasChosen: true, noteText: "common version")
        )
        let state = makeAppState(dataStore: store, cloudService: service)

        await fulfillment(of: [didSync], timeout: 1)
        state.updateNoteText("edit made here during sync")
        try await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertTrue(state.currentPage.noteText.contains("edit made here during sync"))
        XCTAssertTrue(state.currentPage.noteText.contains("edit from the other device"))
        XCTAssertTrue(state.currentPage.noteText.contains("Sync conflict copy"))
    }

    @MainActor
    func testActiveDevicesAutomaticallyExchangeCloudEdits() async throws {
        let service = SharedCloudSyncService()
        let storeA = TestAppDataStore(
            data: appData(storageMode: .iCloud, hasChosen: true, noteText: "shared start")
        )
        let storeB = TestAppDataStore(
            data: appData(storageMode: .iCloud, hasChosen: true, noteText: "shared start")
        )
        let deviceA = makeAppState(
            dataStore: storeA,
            cloudService: service,
            cloudRefreshInterval: 0.05
        )
        let deviceB = makeAppState(
            dataStore: storeB,
            cloudService: service,
            cloudRefreshInterval: 0.05
        )

        let bothDevicesStarted = await waitUntil { await service.syncCallCount >= 2 }
        XCTAssertTrue(bothDevicesStarted)

        deviceA.updateNoteText("written on device A")
        deviceA.saveImmediately()
        deviceA.syncNow()

        let deviceBReceivedEdit = await waitUntil {
            deviceB.currentPage.noteText == "written on device A"
        }
        XCTAssertTrue(deviceBReceivedEdit)

        deviceB.updateNoteText("continued on device B")
        deviceB.saveImmediately()
        deviceB.syncNow()

        let deviceAReceivedEdit = await waitUntil {
            deviceA.currentPage.noteText == "continued on device B"
        }
        XCTAssertTrue(deviceAReceivedEdit)

        deviceA.chooseStorageMode(.localOnly)
        deviceB.chooseStorageMode(.localOnly)
    }

    @MainActor
    private func makeAppState(
        dataStore: TestAppDataStore,
        cloudService: CloudSyncServicing,
        cloudRefreshInterval: TimeInterval = 20
    ) -> AppState {
        let metadataURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinaday-cloud-tests-\(UUID().uuidString).json")
        return AppState(
            dataStore: dataStore,
            dateKeyService: DateKeyService(),
            cloudSyncService: cloudService,
            cloudSyncMetadataStore: CloudSyncMetadataStore(fileURL: metadataURL),
            cloudRefreshInterval: cloudRefreshInterval
        )
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await condition()
    }

    private func appData(
        storageMode: StorageMode,
        hasChosen: Bool,
        noteText: String = "local copy"
    ) -> AppData {
        let localPage = page(noteText, updatedAt: 10)
        return AppData(
            schemaVersion: 1,
            pages: [localPage.dateKey: localPage],
            settings: AppSettings(
                lastOpenedDateKey: localPage.dateKey,
                isPinned: false,
                windowFrame: nil,
                storageMode: storageMode,
                hasChosenStorageMode: hasChosen
            )
        )
    }

    private func page(
        _ text: String,
        dateKey: String = "2026-08-13",
        updatedAt: TimeInterval
    ) -> DayPage {
        DayPage(
            dateKey: dateKey,
            noteText: text,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
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

private actor SharedCloudSyncService: CloudSyncServicing {
    private var remotePages: [String: DayPage] = [:]
    private(set) var syncCallCount = 0

    func accountAvailability() async -> CloudAccountAvailability {
        .available
    }

    func synchronize(
        localSnapshot: CloudSyncSnapshot,
        metadata: CloudSyncMetadata
    ) async throws -> CloudSyncResult {
        syncCallCount += 1
        let merge = SyncMergeEngine.merge(
            localPages: localSnapshot.pages,
            remotePages: remotePages,
            metadata: metadata
        )
        remotePages = merge.pages
        return CloudSyncResult(
            pages: merge.pages,
            metadata: merge.metadata,
            synchronizedAt: Date()
        )
    }
}

private actor FakeCloudSyncService: CloudSyncServicing {
    private(set) var accountCallCount = 0
    private(set) var syncCallCount = 0
    private let result: CloudSyncResult?
    private let didSync: XCTestExpectation?
    private let delayNanoseconds: UInt64

    var callCounts: (account: Int, sync: Int) {
        (accountCallCount, syncCallCount)
    }

    init(
        result: CloudSyncResult? = nil,
        didSync: XCTestExpectation? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.result = result
        self.didSync = didSync
        self.delayNanoseconds = delayNanoseconds
    }

    func accountAvailability() async -> CloudAccountAvailability {
        accountCallCount += 1
        return .available
    }

    func synchronize(
        localSnapshot: CloudSyncSnapshot,
        metadata: CloudSyncMetadata
    ) async throws -> CloudSyncResult {
        syncCallCount += 1
        didSync?.fulfill()
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return result ?? CloudSyncResult(
            pages: localSnapshot.pages,
            metadata: metadata,
            synchronizedAt: Date(timeIntervalSince1970: 40)
        )
    }
}

private final class TestAppDataStore: AppDataStore {
    let dataFileURL = URL(fileURLWithPath: "/tmp/pinaday-cloud-app-data.json")
    private let initialData: AppData
    private(set) var savedData: AppData?

    init(data: AppData) {
        initialData = data
    }

    func load(defaultDateKey: String) throws -> AppData {
        initialData
    }

    func save(_ data: AppData) throws {
        savedData = data
    }
}

import CloudKit
import CryptoKit
import Foundation
import Security

final class CloudKitSyncService: CloudSyncServicing {
    private enum Schema {
        static let containerIdentifier = "iCloud.com.makeeverydaybetter.dailysticky"
        static let zoneName = "PinadayNotes"
        static let pageRecordType = "DayPage"
        static let attachmentRecordType = "Attachment"

        static let dateKey = "dateKey"
        static let noteText = "noteText"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let relativePath = "relativePath"
        static let file = "file"
    }

    private let containerIdentifier: String
    private lazy var container = CKContainer(identifier: containerIdentifier)
    private lazy var database = container.privateCloudDatabase
    private let zoneID: CKRecordZone.ID

    init(containerIdentifier: String = Schema.containerIdentifier) {
        self.containerIdentifier = containerIdentifier
        self.zoneID = CKRecordZone.ID(zoneName: Schema.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    func accountAvailability() async -> CloudAccountAvailability {
        guard hasRequiredCloudKitEntitlement else {
            return .capabilityUnavailable
        }

        return await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in
                let availability: CloudAccountAvailability
                switch status {
                case .available:
                    availability = .available
                case .noAccount:
                    availability = .noAccount
                case .restricted:
                    availability = .restricted
                case .couldNotDetermine, .temporarilyUnavailable:
                    availability = .couldNotDetermine
                @unknown default:
                    availability = .couldNotDetermine
                }
                continuation.resume(returning: availability)
            }
        }
    }

    private var hasRequiredCloudKitEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) as? [String]
        else {
            return false
        }
        return value.contains(containerIdentifier)
    }

    func synchronize(
        localSnapshot: CloudSyncSnapshot,
        metadata: CloudSyncMetadata
    ) async throws -> CloudSyncResult {
        do {
            return try await performSync(localSnapshot: localSnapshot, metadata: metadata)
        } catch where Self.isServerRecordChanged(error) {
            // Another device won the race. Fetch its version and run the lossless merge again.
            return try await performSync(localSnapshot: localSnapshot, metadata: metadata)
        }
    }

    private func performSync(
        localSnapshot: CloudSyncSnapshot,
        metadata: CloudSyncMetadata
    ) async throws -> CloudSyncResult {
        guard await accountAvailability() == .available else {
            throw CloudSyncServiceError.accountUnavailable
        }

        try await ensureZoneExists()
        let remoteRecords = try await fetchAllRecords()
        let remotePages = try decodePages(from: remoteRecords)
        let merge = SyncMergeEngine.merge(
            localPages: localSnapshot.pages,
            remotePages: remotePages,
            metadata: metadata
        )

        let remotePageRecords: [String: CKRecord] = Dictionary(
            uniqueKeysWithValues: remoteRecords.compactMap { record in
                guard record.recordType == Schema.pageRecordType,
                      let dateKey = record[Schema.dateKey] as? String
                else {
                    return nil
                }
                return (dateKey, record)
            }
        )
        let pageRecords = merge.dateKeysToUpload.compactMap { dateKey in
            merge.pages[dateKey].map {
                pageRecord(for: $0, existingRecord: remotePageRecords[dateKey])
            }
        }
        let existingAttachmentPaths = Set(remoteRecords.compactMap { record -> String? in
            guard record.recordType == Schema.attachmentRecordType else {
                return nil
            }
            return record[Schema.relativePath] as? String
        })
        let attachmentRecords = localSnapshot.attachments
            .filter { !existingAttachmentPaths.contains($0.relativePath) }
            .map(attachmentRecord(for:))

        try await save(records: pageRecords + attachmentRecords)
        try restoreMissingAttachments(from: remoteRecords, localSnapshot: localSnapshot)

        return CloudSyncResult(
            pages: merge.pages,
            metadata: merge.metadata,
            synchronizedAt: Date()
        )
    }

    private func ensureZoneExists() async throws {
        let zones = try await allRecordZones()
        if zones.contains(where: { $0.zoneID == zoneID }) {
            return
        }

        let zone = CKRecordZone(zoneID: zoneID)
        let results = try await database.modifyRecordZones(saving: [zone], deleting: [])
        guard let result = results.saveResults[zoneID] else {
            throw CloudSyncServiceError.partialFailure("The Pinaday iCloud zone was not created.")
        }
        _ = try result.get()
    }

    private func allRecordZones() async throws -> [CKRecordZone] {
        try await withCheckedThrowingContinuation { continuation in
            database.fetchAllRecordZones { zones, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: zones ?? [])
                }
            }
        }
    }

    private func fetchAllRecords() async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var changeToken: CKServerChangeToken?
        var moreComing = true

        while moreComing {
            let response = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken
            )
            for (_, result) in response.modificationResultsByID {
                records.append(try result.get().record)
            }
            changeToken = response.changeToken
            moreComing = response.moreComing
        }

        return records.filter {
            $0.recordType == Schema.pageRecordType || $0.recordType == Schema.attachmentRecordType
        }
    }

    private func decodePages(from records: [CKRecord]) throws -> [String: DayPage] {
        var pages: [String: DayPage] = [:]

        for record in records where record.recordType == Schema.pageRecordType {
            guard let dateKey = record[Schema.dateKey] as? String,
                  let noteText = record[Schema.noteText] as? String,
                  let createdAt = record[Schema.createdAt] as? Date,
                  let updatedAt = record[Schema.updatedAt] as? Date
            else {
                throw CloudSyncServiceError.malformedRecord(record.recordID.recordName)
            }

            pages[dateKey] = DayPage(
                dateKey: dateKey,
                noteText: noteText,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }

        return pages
    }

    private func pageRecord(for page: DayPage, existingRecord: CKRecord?) -> CKRecord {
        let record: CKRecord
        if let existingRecord {
            record = existingRecord
        } else {
            let recordID = CKRecord.ID(recordName: "page-\(page.dateKey)", zoneID: zoneID)
            record = CKRecord(recordType: Schema.pageRecordType, recordID: recordID)
        }
        record[Schema.dateKey] = page.dateKey as CKRecordValue
        record[Schema.noteText] = page.noteText as CKRecordValue
        record[Schema.createdAt] = page.createdAt as CKRecordValue
        record[Schema.updatedAt] = page.updatedAt as CKRecordValue
        return record
    }

    private func attachmentRecord(for attachment: CloudAttachment) -> CKRecord {
        let digest = SHA256.hash(data: Data(attachment.relativePath.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let recordID = CKRecord.ID(recordName: "attachment-\(hash)", zoneID: zoneID)
        let record = CKRecord(recordType: Schema.attachmentRecordType, recordID: recordID)
        record[Schema.relativePath] = attachment.relativePath as CKRecordValue
        record[Schema.updatedAt] = attachment.modifiedAt as CKRecordValue
        record[Schema.file] = CKAsset(fileURL: attachment.fileURL)
        return record
    }

    private func save(records: [CKRecord]) async throws {
        guard !records.isEmpty else {
            return
        }

        for batch in records.chunked(into: 200) {
            let results = try await database.modifyRecords(
                saving: batch,
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: false
            )
            for (_, result) in results.saveResults {
                _ = try result.get()
            }
        }
    }

    private func restoreMissingAttachments(
        from records: [CKRecord],
        localSnapshot: CloudSyncSnapshot
    ) throws {
        let localPaths = Set(localSnapshot.attachments.map(\.relativePath))

        for record in records where record.recordType == Schema.attachmentRecordType {
            guard let relativePath = record[Schema.relativePath] as? String,
                  !localPaths.contains(relativePath),
                  let asset = record[Schema.file] as? CKAsset,
                  let sourceURL = asset.fileURL
            else {
                continue
            }
            try AttachmentStore.importSyncedAttachment(from: sourceURL, relativePath: relativePath)
        }
    }

    private static func isServerRecordChanged(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else {
            return false
        }
        if cloudError.code == .serverRecordChanged {
            return true
        }
        return cloudError.partialErrorsByItemID?.values.contains {
            ($0 as? CKError)?.code == .serverRecordChanged
        } == true
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return []
        }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}

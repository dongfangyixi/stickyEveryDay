import CryptoKit
import Foundation

struct SyncMergeOutput: Equatable {
    var pages: [String: DayPage]
    var dateKeysToUpload: Set<String>
    var metadata: CloudSyncMetadata
}

enum SyncMergeEngine {
    static func reconcileChangesMadeDuringSync(
        currentPages: [String: DayPage],
        synchronizedPages: [String: DayPage],
        sourcePages: [String: DayPage]
    ) -> SyncMergeOutput {
        merge(
            localPages: currentPages,
            remotePages: synchronizedPages,
            metadata: metadata(for: sourcePages)
        )
    }

    static func metadata(for pages: [String: DayPage]) -> CloudSyncMetadata {
        CloudSyncMetadata(
            pageHashes: pages.mapValues(contentHash(for:))
        )
    }

    static func merge(
        localPages: [String: DayPage],
        remotePages: [String: DayPage],
        metadata: CloudSyncMetadata
    ) -> SyncMergeOutput {
        let dateKeys = Set(localPages.keys).union(remotePages.keys)
        var mergedPages: [String: DayPage] = [:]
        var dateKeysToUpload: Set<String> = []
        var hashes: [String: String] = [:]

        for dateKey in dateKeys.sorted() {
            let local = localPages[dateKey]
            let remote = remotePages[dateKey]
            let baselineHash = metadata.pageHashes[dateKey]
            let merged = mergePage(local: local, remote: remote, baselineHash: baselineHash)

            guard let merged else {
                continue
            }

            mergedPages[dateKey] = merged
            let mergedHash = contentHash(for: merged)
            hashes[dateKey] = mergedHash

            if remote.map(contentHash(for:)) != mergedHash {
                dateKeysToUpload.insert(dateKey)
            }
        }

        return SyncMergeOutput(
            pages: mergedPages,
            dateKeysToUpload: dateKeysToUpload,
            metadata: CloudSyncMetadata(pageHashes: hashes)
        )
    }

    static func contentHash(for page: DayPage) -> String {
        let digest = SHA256.hash(data: Data(page.noteText.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func mergePage(
        local: DayPage?,
        remote: DayPage?,
        baselineHash: String?
    ) -> DayPage? {
        switch (local, remote) {
        case (nil, nil):
            return nil
        case let (local?, nil):
            return local
        case let (nil, remote?):
            return remote
        case let (local?, remote?):
            let localHash = contentHash(for: local)
            let remoteHash = contentHash(for: remote)

            guard localHash != remoteHash else {
                return local.updatedAt >= remote.updatedAt ? local : remote
            }

            if let baselineHash {
                let localChanged = localHash != baselineHash
                let remoteChanged = remoteHash != baselineHash

                if localChanged && !remoteChanged {
                    return local
                }
                if remoteChanged && !localChanged {
                    return remote
                }
            } else {
                if local.noteText.isEmpty && !remote.noteText.isEmpty {
                    return remote
                }
                if remote.noteText.isEmpty && !local.noteText.isEmpty {
                    return local
                }
            }

            return preservingConflict(local: local, remote: remote)
        }
    }

    private static func preservingConflict(local: DayPage, remote: DayPage) -> DayPage {
        let localIsPrimary = local.updatedAt >= remote.updatedAt
        let primary = localIsPrimary ? local : remote
        let secondary = localIsPrimary ? remote : local
        let separator = primary.noteText.isEmpty ? "" : "\n\n"
        let conflictText = "\(primary.noteText)\(separator)---\n\n## Sync conflict copy\n\n\(secondary.noteText)"

        return DayPage(
            dateKey: primary.dateKey,
            noteText: conflictText,
            createdAt: min(local.createdAt, remote.createdAt),
            updatedAt: max(local.updatedAt, remote.updatedAt).addingTimeInterval(0.001)
        )
    }
}

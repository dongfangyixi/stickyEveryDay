import Foundation

struct CloudSyncMetadata: Codable, Equatable {
    var pageHashes: [String: String]

    static let empty = CloudSyncMetadata(pageHashes: [:])
}

struct CloudSyncResult: Equatable {
    var pages: [String: DayPage]
    var metadata: CloudSyncMetadata
    var synchronizedAt: Date
}

struct CloudAttachment: Equatable {
    var relativePath: String
    var fileURL: URL
    var modifiedAt: Date
}

struct CloudSyncSnapshot: Equatable {
    var pages: [String: DayPage]
    var attachments: [CloudAttachment]
}

protocol CloudSyncServicing {
    func accountAvailability() async -> CloudAccountAvailability
    func synchronize(
        localSnapshot: CloudSyncSnapshot,
        metadata: CloudSyncMetadata
    ) async throws -> CloudSyncResult
}

enum CloudSyncServiceError: LocalizedError {
    case accountUnavailable
    case malformedRecord(String)
    case partialFailure(String)

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            return "Sign in to iCloud to sync your Pinaday notes."
        case let .malformedRecord(recordName):
            return "Pinaday could not read the iCloud record \(recordName)."
        case let .partialFailure(message):
            return "Some Pinaday notes could not sync: \(message)"
        }
    }
}

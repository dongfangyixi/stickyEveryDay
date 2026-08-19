import Foundation

enum StorageMode: String, Codable, CaseIterable, Identifiable {
    case localOnly
    case iCloud

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .localOnly:
            return "Local only"
        case .iCloud:
            return "Sync with iCloud"
        }
    }
}

enum CloudSyncStatus: Equatable {
    case localOnly
    case checkingAccount
    case syncing
    case upToDate(Date)
    case offline
    case accountUnavailable
    case capabilityUnavailable
    case failed(String)
}

enum CloudAccountAvailability: Equatable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case capabilityUnavailable
}

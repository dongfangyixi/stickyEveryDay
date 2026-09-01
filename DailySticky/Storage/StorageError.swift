import Foundation

enum StorageError: LocalizedError {
    case couldNotCreateDirectory(URL, Error)
    case couldNotRead(URL, Error)
    case couldNotDecode(URL, Error)
    case couldNotPrepareData(URL, recoveryBackupURL: URL?, Error)
    case couldNotCommitMigration(URL, Error)
    case writesBlocked(URL, Error)
    case invalidSchemaVersionForSave(expected: Int, found: Int)
    case couldNotSave(URL, Error)

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDirectory(let url, let error):
            return "Could not create storage directory at \(url.path): \(error.localizedDescription)"
        case .couldNotRead(let url, let error):
            return "Could not read data file at \(url.path): \(error.localizedDescription)"
        case .couldNotDecode(let url, let error):
            return "Could not decode data file at \(url.path): \(error.localizedDescription)"
        case .couldNotPrepareData(let url, let backupURL, let error):
            let backupMessage = backupURL.map { " A recovery copy was saved at \($0.path)." } ?? ""
            return "Pinaday could not open the data file at \(url.path). The original file was not changed and saving is disabled for this session.\(backupMessage) \(error.localizedDescription)"
        case .couldNotCommitMigration(let url, let error):
            return "Pinaday could not safely update the data file at \(url.path). A pre-migration backup was preserved and saving is disabled for this session: \(error.localizedDescription)"
        case .writesBlocked(let url, let error):
            return "Saving to \(url.path) is disabled because its existing data could not be loaded safely: \(error.localizedDescription)"
        case .invalidSchemaVersionForSave(let expected, let found):
            return "Refused to save schema version \(found); this version of Pinaday requires schema version \(expected)."
        case .couldNotSave(let url, let error):
            return "Could not save data file at \(url.path): \(error.localizedDescription)"
        }
    }
}

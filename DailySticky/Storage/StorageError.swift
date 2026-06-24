import Foundation

enum StorageError: LocalizedError {
    case couldNotCreateDirectory(URL, Error)
    case couldNotRead(URL, Error)
    case couldNotDecode(URL, Error)
    case couldNotSave(URL, Error)

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDirectory(let url, let error):
            return "Could not create storage directory at \(url.path): \(error.localizedDescription)"
        case .couldNotRead(let url, let error):
            return "Could not read data file at \(url.path): \(error.localizedDescription)"
        case .couldNotDecode(let url, let error):
            return "Could not decode data file at \(url.path): \(error.localizedDescription)"
        case .couldNotSave(let url, let error):
            return "Could not save data file at \(url.path): \(error.localizedDescription)"
        }
    }
}


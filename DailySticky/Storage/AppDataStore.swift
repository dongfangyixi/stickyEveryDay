import Foundation

protocol AppDataStore {
    var dataFileURL: URL { get }

    func load(defaultDateKey: String) throws -> AppData
    func save(_ data: AppData) throws
}


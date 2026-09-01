import Foundation

final class JSONAppDataStore: AppDataStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let migrationPlan: AppDataMigrationPlan
    private let now: () -> Date
    private var writeBlockReason: Error?

    let dataFileURL: URL

    init(
        fileManager: FileManager = .default,
        appDirectoryName: String = "DailySticky",
        fileName: String = "daily-sticky.json",
        migrationPlan: AppDataMigrationPlan = .production,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.migrationPlan = migrationPlan
        self.now = now

        let applicationSupportURL = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        self.directoryURL = applicationSupportURL.appendingPathComponent(appDirectoryName, isDirectory: true)
        self.dataFileURL = directoryURL.appendingPathComponent(fileName)
    }

    init(
        fileManager: FileManager = .default,
        directoryURL: URL,
        fileName: String = "daily-sticky.json",
        migrationPlan: AppDataMigrationPlan = .production,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        self.dataFileURL = directoryURL.appendingPathComponent(fileName)
        self.migrationPlan = migrationPlan
        self.now = now
    }

    func load(defaultDateKey: String) throws -> AppData {
        try ensureDirectoryExists()

        guard fileManager.fileExists(atPath: dataFileURL.path) else {
            let emptyData = AppData.empty(todayDateKey: defaultDateKey)
            try save(emptyData)
            return emptyData
        }

        let rawData: Data
        do {
            rawData = try Data(contentsOf: dataFileURL)
        } catch {
            throw StorageError.couldNotRead(dataFileURL, error)
        }

        let preparation: AppDataMigrationResult
        do {
            preparation = try migrationPlan.prepare(rawData)
        } catch {
            let backupURL = try? createBackup(label: "recovery")
            let storageError = StorageError.couldNotPrepareData(
                dataFileURL,
                recoveryBackupURL: backupURL,
                error
            )
            writeBlockReason = storageError
            throw storageError
        }

        if let migratedData = preparation.migratedData {
            let label = "before-v\(preparation.sourceVersion)-to-v\(migrationPlan.currentVersion)"
            do {
                _ = try createBackup(label: label)
                try migratedData.write(to: dataFileURL, options: [.atomic])
            } catch {
                let storageError = StorageError.couldNotCommitMigration(dataFileURL, error)
                writeBlockReason = storageError
                throw storageError
            }
        }

        writeBlockReason = nil
        return preparation.appData
    }

    func save(_ data: AppData) throws {
        try ensureDirectoryExists()

        if let writeBlockReason {
            throw StorageError.writesBlocked(dataFileURL, writeBlockReason)
        }

        guard data.schemaVersion == migrationPlan.currentVersion else {
            throw StorageError.invalidSchemaVersionForSave(
                expected: migrationPlan.currentVersion,
                found: data.schemaVersion
            )
        }

        do {
            let rawData = try AppDataJSONCodec.encode(data)
            try rawData.write(to: dataFileURL, options: [.atomic])
        } catch {
            throw StorageError.couldNotSave(dataFileURL, error)
        }
    }

    private func ensureDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw StorageError.couldNotCreateDirectory(directoryURL, error)
        }
    }

    private func createBackup(label: String) throws -> URL {
        let baseName = dataFileURL.deletingPathExtension().lastPathComponent
        let fileExtension = dataFileURL.pathExtension
        let timestamp = Self.backupTimestamp(for: now())
        var suffix = 1

        while true {
            let suffixText = suffix == 1 ? "" : "-\(suffix)"
            let fileName = "\(baseName)-\(label)-\(timestamp)\(suffixText)"
            let backupURL = directoryURL
                .appendingPathComponent(fileName)
                .appendingPathExtension(fileExtension)
            guard fileManager.fileExists(atPath: backupURL.path) else {
                try fileManager.copyItem(at: dataFileURL, to: backupURL)
                return backupURL
            }
            suffix += 1
        }
    }

    private static func backupTimestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

import Foundation

final class JSONAppDataStore: AppDataStore {
    private let fileManager: FileManager
    private let directoryURL: URL

    let dataFileURL: URL

    init(
        fileManager: FileManager = .default,
        appDirectoryName: String = "DailySticky",
        fileName: String = "daily-sticky.json"
    ) {
        self.fileManager = fileManager

        let applicationSupportURL = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        self.directoryURL = applicationSupportURL.appendingPathComponent(appDirectoryName, isDirectory: true)
        self.dataFileURL = directoryURL.appendingPathComponent(fileName)
    }

    func load(defaultDateKey: String) throws -> AppData {
        try ensureDirectoryExists()

        guard fileManager.fileExists(atPath: dataFileURL.path) else {
            let emptyData = AppData.empty(todayDateKey: defaultDateKey)
            try save(emptyData)
            return emptyData
        }

        do {
            let rawData = try Data(contentsOf: dataFileURL)
            return try Self.decoder.decode(AppData.self, from: rawData)
        } catch let decodingError as DecodingError {
            backupCorruptedFile()
            let emptyData = AppData.empty(todayDateKey: defaultDateKey)
            try save(emptyData)
            throw StorageError.couldNotDecode(dataFileURL, decodingError)
        } catch {
            throw StorageError.couldNotRead(dataFileURL, error)
        }
    }

    func save(_ data: AppData) throws {
        try ensureDirectoryExists()

        do {
            let rawData = try Self.encoder.encode(data)
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

    private func backupCorruptedFile() {
        guard fileManager.fileExists(atPath: dataFileURL.path) else {
            return
        }

        let backupURL = directoryURL.appendingPathComponent("daily-sticky-corrupt-\(Self.backupTimestamp()).json")

        do {
            try fileManager.copyItem(at: dataFileURL, to: backupURL)
        } catch {
            // Backup is best-effort. The app still recovers into an empty data file.
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601Formatter.string(from: date))
        }
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            if let date = iso8601Formatter.date(from: string) {
                return date
            }

            if let date = fractionalISO8601Formatter.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date string."
            )
        }
        return decoder
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}


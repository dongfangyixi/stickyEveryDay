import Foundation

final class CloudSyncMetadataStore {
    private let fileManager: FileManager
    let fileURL: URL

    init(
        fileManager: FileManager = .default,
        appDirectoryName: String = "DailySticky",
        fileName: String = "cloud-sync-metadata.json"
    ) {
        self.fileManager = fileManager

        let applicationSupportURL = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        fileURL = applicationSupportURL
            .appendingPathComponent(appDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    init(fileManager: FileManager = .default, fileURL: URL) {
        self.fileManager = fileManager
        self.fileURL = fileURL
    }

    func load() -> CloudSyncMetadata {
        guard let data = try? Data(contentsOf: fileURL),
              let metadata = try? JSONDecoder().decode(CloudSyncMetadata.self, from: data)
        else {
            return .empty
        }
        return metadata
    }

    func save(_ metadata: CloudSyncMetadata) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: fileURL, options: [.atomic])
    }
}

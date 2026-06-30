import AppKit
import Foundation

enum AttachmentStore {
    private static let appDirectoryName = "DailySticky"

    static func savePastedImage(_ image: NSImage, dateKey: String) throws -> String {
        guard let pngData = pngData(from: image) else {
            throw AttachmentStoreError.couldNotEncodeImage
        }

        let folderPath = "attachments/\(dateKey)"
        let directoryURL = try appSupportDirectory()
            .appendingPathComponent(folderPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let filename = "image-\(UUID().uuidString).png"
        let fileURL = directoryURL.appendingPathComponent(filename)
        try pngData.write(to: fileURL, options: [.atomic])
        return "\(folderPath)/\(filename)"
    }

    static func imageURL(for markdownPath: String) -> URL? {
        let trimmedPath = markdownPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmedPath),
           url.isFileURL {
            return url
        }

        guard !trimmedPath.contains("://") else {
            return nil
        }

        do {
            return try appSupportDirectory().appendingPathComponent(trimmedPath)
        } catch {
            return nil
        }
    }

    private static func appSupportDirectory() throws -> URL {
        let applicationSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupportURL.appendingPathComponent(appDirectoryName, isDirectory: true)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}

enum AttachmentStoreError: LocalizedError {
    case couldNotEncodeImage

    var errorDescription: String? {
        switch self {
        case .couldNotEncodeImage:
            return "Could not encode pasted image."
        }
    }
}

import CoreGraphics
import Foundation
import ImageIO
import Vision

struct OCRTextObservation: Codable, Equatable, Sendable {
    let text: String
    let boundingBox: CGRect
    let characterBoxes: [CGRect]
}

protocol ImageOCRRecognizing: Sendable {
    func recognizeText(in imageURL: URL) async -> [OCRTextObservation]
}

struct VisionImageOCRRecognizer: ImageOCRRecognizing {
    func recognizeText(in imageURL: URL) async -> [OCRTextObservation] {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                return []
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            do {
                let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
                try handler.perform([request])
                return (request.results ?? []).compactMap(Self.observation(from:))
            } catch {
                return []
            }
        }.value
    }

    private static func observation(from result: VNRecognizedTextObservation) -> OCRTextObservation? {
        guard let candidate = result.topCandidates(1).first else {
            return nil
        }

        let bounds = result.boundingBox
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        var characterBoxes: [CGRect] = []
        var index = candidate.string.startIndex
        while index < candidate.string.endIndex {
            let nextIndex = candidate.string.index(after: index)
            let characterBox: CGRect
            do {
                characterBox = try candidate.boundingBox(
                    for: index..<nextIndex
                )?.boundingBox ?? .zero
            } catch {
                characterBox = .zero
            }
            characterBoxes.append(characterBox)
            index = nextIndex
        }

        return OCRTextObservation(
            text: candidate.string,
            boundingBox: bounds,
            characterBoxes: characterBoxes
        )
    }
}

actor ImageOCRRepository {
    static let shared = ImageOCRRepository()

    private struct CacheFile: Codable {
        var version: Int
        var entries: [String: CacheEntry]
    }

    private struct CacheEntry: Codable {
        let fileSize: Int64
        let modificationTime: TimeInterval
        let observations: [OCRTextObservation]
    }

    private static let cacheVersion = 1

    private let recognizer: any ImageOCRRecognizing
    private let imageURL: @Sendable (String) -> URL?
    private let cacheURL: URL?
    private let fileManager: FileManager
    private var entries: [String: CacheEntry] = [:]
    private var hasLoadedCache = false
    private var inFlight: [String: Task<[OCRTextObservation], Never>] = [:]

    init(
        recognizer: any ImageOCRRecognizing = VisionImageOCRRecognizer(),
        imageURL: @escaping @Sendable (String) -> URL? = {
            AttachmentStore.imageURL(for: $0)
        },
        cacheURL: URL? = AttachmentStore.ocrCacheURL(),
        fileManager: FileManager = .default
    ) {
        self.recognizer = recognizer
        self.imageURL = imageURL
        self.cacheURL = cacheURL
        self.fileManager = fileManager
    }

    func observations(for attachmentPath: String) async -> [OCRTextObservation] {
        loadCacheIfNeeded()
        guard let fileURL = imageURL(attachmentPath),
              let fingerprint = fingerprint(for: fileURL)
        else {
            return []
        }

        if let entry = entries[attachmentPath],
           entry.fileSize == fingerprint.fileSize,
           entry.modificationTime == fingerprint.modificationTime {
            return entry.observations
        }

        if let task = inFlight[attachmentPath] {
            return await task.value
        }

        let recognizer = self.recognizer
        let task = Task {
            await recognizer.recognizeText(in: fileURL)
        }
        inFlight[attachmentPath] = task
        let observations = await task.value
        inFlight.removeValue(forKey: attachmentPath)

        entries[attachmentPath] = CacheEntry(
            fileSize: fingerprint.fileSize,
            modificationTime: fingerprint.modificationTime,
            observations: observations
        )
        saveCache()
        return observations
    }

    private func fingerprint(for url: URL) -> (fileSize: Int64, modificationTime: TimeInterval)? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular
        else {
            return nil
        }

        return (
            (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        )
    }

    private func loadCacheIfNeeded() {
        guard !hasLoadedCache else {
            return
        }
        hasLoadedCache = true

        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(CacheFile.self, from: data),
              cache.version == Self.cacheVersion
        else {
            return
        }
        entries = cache.entries
    }

    private func saveCache() {
        guard let cacheURL else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let cache = CacheFile(version: Self.cacheVersion, entries: entries)
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // OCR remains available for this session when the cache cannot be written.
        }
    }
}

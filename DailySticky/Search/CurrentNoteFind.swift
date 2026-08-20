import Combine
import Foundation

enum NoteSearchMatchLocation: Equatable, Sendable {
    case note(range: NSRange)
    case image(
        attachmentPath: String,
        markdownRange: NSRange,
        observationIndex: Int,
        characterRange: NSRange,
        normalizedBoundingBox: CGRect
    )

    var source: NoteSearchLineSource {
        switch self {
        case .note:
            return .note
        case let .image(attachmentPath, _, _, _, _):
            return .image(attachmentPath: attachmentPath)
        }
    }
}

struct NoteRevealRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let dateKey: String
    let query: String
    let location: NoteSearchMatchLocation

    init(
        id: UUID = UUID(),
        dateKey: String,
        query: String,
        location: NoteSearchMatchLocation
    ) {
        self.id = id
        self.dateKey = dateKey
        self.query = query
        self.location = location
    }
}

struct SearchableImageText: Equatable, Sendable {
    let attachmentPath: String
    let markdownRange: NSRange
    let observationIndex: Int
    let text: String
    let normalizedBoundingBox: CGRect
}

struct CurrentNoteFindMatch: Identifiable, Equatable, Sendable {
    let id: String
    let location: NoteSearchMatchLocation
}

struct CurrentNoteFindEngine {
    static func matches(
        query: String,
        noteText: String,
        imageText: [SearchableImageText],
        locale: Locale
    ) -> [CurrentNoteFindMatch] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let imageMarkdownRanges = MarkdownImageReferenceParser.references(in: noteText)
            .map(\.markdownRange)
        let noteMatches = ranges(of: trimmedQuery, in: noteText, locale: locale)
            .filter { matchRange in
                !imageMarkdownRanges.contains { $0.intersection(matchRange) != nil }
            }
            .enumerated()
            .map { index, range in
                CurrentNoteFindMatch(
                    id: "note-\(range.location)-\(index)",
                    location: .note(range: range)
                )
            }

        let imageMatches = imageText.flatMap { line in
            ranges(of: trimmedQuery, in: line.text, locale: locale)
                .enumerated()
                .map { occurrence, range in
                    CurrentNoteFindMatch(
                        id: "image-\(line.attachmentPath)-\(line.observationIndex)-\(range.location)-\(occurrence)",
                        location: .image(
                            attachmentPath: line.attachmentPath,
                            markdownRange: line.markdownRange,
                            observationIndex: line.observationIndex,
                            characterRange: range,
                            normalizedBoundingBox: line.normalizedBoundingBox
                        )
                    )
                }
        }

        return (noteMatches + imageMatches).sorted { left, right in
            let leftOrder = documentOrder(for: left.location)
            let rightOrder = documentOrder(for: right.location)
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return left.id < right.id
        }
    }

    private static func ranges(
        of query: String,
        in text: String,
        locale: Locale
    ) -> [NSRange] {
        let candidate = text as NSString
        let queryLength = (query as NSString).length
        guard queryLength > 0, candidate.length >= queryLength else {
            return []
        }

        let options: NSString.CompareOptions = [
            .caseInsensitive,
            .diacriticInsensitive,
            .widthInsensitive
        ]
        var matches: [NSRange] = []
        var searchLocation = 0
        while searchLocation < candidate.length {
            let searchRange = NSRange(
                location: searchLocation,
                length: candidate.length - searchLocation
            )
            let match = candidate.range(
                of: query,
                options: options,
                range: searchRange,
                locale: locale
            )
            guard match.location != NSNotFound, match.length > 0 else {
                break
            }
            matches.append(match)
            searchLocation = NSMaxRange(match)
        }
        return matches
    }

    private static func documentOrder(for location: NoteSearchMatchLocation) -> Int {
        switch location {
        case let .note(range):
            return range.location * 2
        case let .image(_, markdownRange, observationIndex, _, _):
            return markdownRange.location * 2 + min(observationIndex, 1)
        }
    }
}

@MainActor
final class CurrentNoteFindController: ObservableObject {
    @Published private(set) var isPresented = false
    @Published var query = "" {
        didSet {
            selectedMatchIndex = 0
            refreshMatches()
        }
    }
    @Published private(set) var matches: [CurrentNoteFindMatch] = []
    @Published private(set) var selectedMatchIndex = 0
    @Published private(set) var isIndexingImageText = false
    @Published private(set) var focusRequestID = UUID()

    private let repository: ImageOCRRepository
    private var page = DayPage.empty(dateKey: "1970-01-01", now: .distantPast)
    private var locale = Locale(identifier: "en_US")
    private var searchableImageText: [SearchableImageText] = []
    private var indexedImageSignature = ""
    private var ocrTask: Task<Void, Never>?

    init(repository: ImageOCRRepository = .shared) {
        self.repository = repository
    }

    deinit {
        ocrTask?.cancel()
    }

    var selectedMatch: CurrentNoteFindMatch? {
        guard matches.indices.contains(selectedMatchIndex) else {
            return nil
        }
        return matches[selectedMatchIndex]
    }

    var positionLabel: String {
        guard !matches.isEmpty else {
            return "0/0"
        }
        return "\(selectedMatchIndex + 1)/\(matches.count)"
    }

    func present() {
        isPresented = true
        focusRequestID = UUID()
        beginOCRIndexingIfNeeded()
    }

    func close() {
        query = ""
        isPresented = false
        ocrTask?.cancel()
        ocrTask = nil
        isIndexingImageText = false
    }

    @discardableResult
    func handleEscape() -> Bool {
        if !query.isEmpty {
            query = ""
            return true
        }
        close()
        return false
    }

    func update(page: DayPage, locale: Locale) {
        let dateChanged = self.page.dateKey != page.dateKey
        self.page = page
        self.locale = locale
        if dateChanged {
            selectedMatchIndex = 0
        }

        let signature = imageSignature(for: page.noteText)
        if signature != indexedImageSignature {
            indexedImageSignature = signature
            searchableImageText = []
            beginOCRIndexingIfNeeded(force: true)
        }
        refreshMatches()
    }

    @discardableResult
    func moveSelection(by offset: Int) -> Bool {
        guard !matches.isEmpty, offset != 0 else {
            return false
        }

        let count = matches.count
        selectedMatchIndex = (selectedMatchIndex + offset % count + count) % count
        return true
    }

    private func refreshMatches() {
        matches = CurrentNoteFindEngine.matches(
            query: query,
            noteText: page.noteText,
            imageText: searchableImageText,
            locale: locale
        )
        selectedMatchIndex = min(selectedMatchIndex, max(0, matches.count - 1))
    }

    private func imageSignature(for noteText: String) -> String {
        MarkdownImageReferenceParser.references(in: noteText)
            .map { "\($0.path)|\($0.markdownRange.location)|\($0.markdownRange.length)" }
            .joined(separator: "\n")
    }

    private func beginOCRIndexingIfNeeded(force: Bool = false) {
        guard isPresented else {
            return
        }
        let references = MarkdownImageReferenceParser.references(in: page.noteText)
        guard !references.isEmpty else {
            searchableImageText = []
            isIndexingImageText = false
            refreshMatches()
            return
        }
        guard force || searchableImageText.isEmpty else {
            return
        }

        ocrTask?.cancel()
        isIndexingImageText = true
        let repository = self.repository
        let expectedSignature = indexedImageSignature
        ocrTask = Task { [weak self] in
            var lines: [SearchableImageText] = []
            for reference in references {
                guard !Task.isCancelled else {
                    return
                }
                let observations = await repository.observations(for: reference.path)
                lines.append(contentsOf: observations.enumerated().map { index, observation in
                    SearchableImageText(
                        attachmentPath: reference.path,
                        markdownRange: reference.markdownRange,
                        observationIndex: index,
                        text: observation.text,
                        normalizedBoundingBox: observation.boundingBox
                    )
                })
            }

            guard let self,
                  !Task.isCancelled,
                  self.indexedImageSignature == expectedSignature
            else {
                return
            }
            self.searchableImageText = lines
            self.isIndexingImageText = false
            self.ocrTask = nil
            self.refreshMatches()
        }
    }
}

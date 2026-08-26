import Combine
import Foundation

@MainActor
final class NoteSearchController: ObservableObject {
    @Published var query = "" {
        didSet {
            selectedResultIndex = 0
            refreshResults()
        }
    }
    @Published private(set) var results: [NoteSearchResult] = []
    @Published private(set) var selectedResultIndex = 0
    @Published private(set) var isIndexingImageText = false

    private var engine = NoteSearchEngine()
    private var dateEngine = NoteDateSearchEngine()
    private var indexedDocuments: [NoteSearchDocument] = []
    private var locale = Locale(identifier: "en_US")
    private var indexedLocaleIdentifier: String?

    var indexedDocumentCount: Int {
        engine.documentCount
    }

    var selectedResult: NoteSearchResult? {
        guard results.indices.contains(selectedResultIndex) else {
            return nil
        }
        return results[selectedResultIndex]
    }

    func rebuildIndex(
        with pages: [String: DayPage],
        locale: Locale = Locale(identifier: "en_US")
    ) {
        rebuildIndex(
            with: pages.values.map {
                NoteSearchDocument(
                    dateKey: $0.dateKey,
                    text: $0.noteText,
                    updatedAt: $0.updatedAt
                )
            },
            locale: locale
        )
    }

    func rebuildIndex(
        with documents: [NoteSearchDocument],
        locale: Locale? = nil
    ) {
        let selectedResultID = selectedResult?.id
        if let locale {
            self.locale = locale
        }
        let localeIdentifier = self.locale.identifier
        let localeChanged = indexedLocaleIdentifier != localeIdentifier
        let update = engine.synchronize(with: documents)
        indexedDocuments = documents
        if update.hasChanges || localeChanged {
            dateEngine.synchronize(with: documents, locale: self.locale)
            indexedLocaleIdentifier = localeIdentifier
        }
        refreshResults(preferredResultID: selectedResultID)
    }

    func updateLocale(_ locale: Locale) {
        let selectedResultID = selectedResult?.id
        self.locale = locale
        dateEngine.rebuild(with: indexedDocuments, locale: locale)
        refreshResults(preferredResultID: selectedResultID)
    }

    func setIndexingImageText(_ isIndexing: Bool) {
        isIndexingImageText = isIndexing
    }

    func clearQuery() {
        query = ""
    }

    func handleEscape() -> Bool {
        guard !query.isEmpty else {
            return false
        }

        clearQuery()
        return true
    }

    func releaseIndex() {
        engine.rebuild(with: [NoteSearchDocument]())
        dateEngine.releaseIndex()
        indexedDocuments = []
        indexedLocaleIdentifier = nil
        results = []
        selectedResultIndex = 0
        isIndexingImageText = false
    }

    @discardableResult
    func moveSelection(by offset: Int) -> Bool {
        guard !results.isEmpty else {
            selectedResultIndex = 0
            return false
        }

        let nextIndex = min(
            max(selectedResultIndex + offset, results.startIndex),
            results.index(before: results.endIndex)
        )
        guard nextIndex != selectedResultIndex else {
            return false
        }

        selectedResultIndex = nextIndex
        return true
    }

    func selectResult(at index: Int) {
        guard results.indices.contains(index) else {
            return
        }
        selectedResultIndex = index
    }

    func selectResult(id: String) {
        guard let index = results.firstIndex(where: { $0.id == id }) else {
            return
        }
        selectedResultIndex = index
    }

    private func refreshResults(preferredResultID: String? = nil) {
        let contentResults = engine.search(query, limit: 80)
        let dateResults = dateEngine.search(query, limit: 80)
        var resultByDateKey = Dictionary(
            uniqueKeysWithValues: contentResults.map { ($0.dateKey, $0) }
        )
        for result in dateResults {
            resultByDateKey[result.dateKey] = result
        }
        results = resultByDateKey.values.sorted {
            if $0.kind != $1.kind {
                return $0.kind == .date
            }
            if $0.kind == .content,
               $0.matchingLineCount != $1.matchingLineCount {
                return $0.matchingLineCount > $1.matchingLineCount
            }
            if $0.dateKey != $1.dateKey {
                return $0.dateKey > $1.dateKey
            }
            return $0.score > $1.score
        }
        .prefix(40)
        .map { $0 }
        if let preferredResultID,
           let preservedIndex = results.firstIndex(where: { $0.id == preferredResultID }) {
            selectedResultIndex = preservedIndex
        } else {
            selectedResultIndex = min(selectedResultIndex, max(0, results.count - 1))
        }
    }
}

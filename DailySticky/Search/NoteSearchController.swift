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
        if let locale {
            self.locale = locale
        }
        indexedDocuments = documents
        engine.rebuild(with: documents)
        dateEngine.rebuild(with: documents, locale: self.locale)
        refreshResults()
    }

    func updateLocale(_ locale: Locale) {
        self.locale = locale
        dateEngine.rebuild(with: indexedDocuments, locale: locale)
        refreshResults()
    }

    func setIndexingImageText(_ isIndexing: Bool) {
        isIndexingImageText = isIndexing
    }

    func reset() {
        query = ""
        results = []
        selectedResultIndex = 0
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

    private func refreshResults() {
        let contentResults = engine.search(query, limit: 80)
        let dateResults = dateEngine.search(query, limit: 80)
        var resultByDateKey = Dictionary(
            uniqueKeysWithValues: contentResults.map { ($0.dateKey, $0) }
        )
        for result in dateResults {
            resultByDateKey[result.dateKey] = result
        }
        results = resultByDateKey.values.sorted {
            if abs($0.score - $1.score) > 0.0001 {
                return $0.score > $1.score
            }
            return $0.dateKey > $1.dateKey
        }
        .prefix(40)
        .map { $0 }
        selectedResultIndex = min(selectedResultIndex, max(0, results.count - 1))
    }
}

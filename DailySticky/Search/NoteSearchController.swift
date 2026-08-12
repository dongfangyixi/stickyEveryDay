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

    private var engine = NoteSearchEngine()

    var indexedDocumentCount: Int {
        engine.documentCount
    }

    var selectedResult: NoteSearchResult? {
        guard results.indices.contains(selectedResultIndex) else {
            return nil
        }
        return results[selectedResultIndex]
    }

    func rebuildIndex(with pages: [String: DayPage]) {
        engine.rebuild(with: pages)
        refreshResults()
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
        results = []
        selectedResultIndex = 0
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
        results = engine.search(query)
        selectedResultIndex = min(selectedResultIndex, max(0, results.count - 1))
    }
}

import Foundation

struct OCRSearchIndexer: Sendable {
    let repository: ImageOCRRepository

    init(repository: ImageOCRRepository = .shared) {
        self.repository = repository
    }

    func documents(for pages: [String: DayPage]) async -> [NoteSearchDocument] {
        let attachmentPaths = Set(
            pages.values.flatMap { page in
                MarkdownImageReferenceParser.references(in: page.noteText).map(\.path)
            }
        )
        let imageTextByPath = await recognizedText(for: Array(attachmentPaths))

        return pages.values.map { page in
            let imageLines = MarkdownImageReferenceParser.references(in: page.noteText).flatMap { reference in
                (imageTextByPath[reference.path] ?? []).map { text in
                    NoteSearchSupplementalLine(
                        text: text,
                        source: .image(attachmentPath: reference.path)
                    )
                }
            }
            return NoteSearchDocument(
                dateKey: page.dateKey,
                text: page.noteText,
                updatedAt: page.updatedAt,
                supplementalLines: imageLines
            )
        }
    }

    private func recognizedText(for paths: [String]) async -> [String: [String]] {
        await withTaskGroup(of: (String, [String]).self) { group in
            var iterator = paths.makeIterator()
            let concurrentTaskLimit = min(3, paths.count)

            for _ in 0..<concurrentTaskLimit {
                guard let path = iterator.next() else {
                    break
                }
                addTask(for: path, to: &group)
            }

            var results: [String: [String]] = [:]
            while let (path, lines) = await group.next() {
                results[path] = lines
                if let nextPath = iterator.next() {
                    addTask(for: nextPath, to: &group)
                }
            }
            return results
        }
    }

    private func addTask(
        for path: String,
        to group: inout TaskGroup<(String, [String])>
    ) {
        let repository = self.repository
        group.addTask {
            let lines = await repository.observations(for: path)
                .map(\.text)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return (path, lines)
        }
    }
}

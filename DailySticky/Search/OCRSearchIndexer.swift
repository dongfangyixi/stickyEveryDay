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
                (imageTextByPath[reference.path] ?? []).enumerated().map { index, observation in
                    NoteSearchSupplementalLine(
                        text: observation.text,
                        source: .image(attachmentPath: reference.path),
                        location: .image(
                            attachmentPath: reference.path,
                            markdownRange: reference.markdownRange,
                            observationIndex: index,
                            characterRange: NSRange(
                                location: 0,
                                length: (observation.text as NSString).length
                            )
                        )
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

    private func recognizedText(for paths: [String]) async -> [String: [OCRTextObservation]] {
        await withTaskGroup(of: (String, [OCRTextObservation]).self) { group in
            var iterator = paths.makeIterator()
            let concurrentTaskLimit = min(3, paths.count)

            for _ in 0..<concurrentTaskLimit {
                guard let path = iterator.next() else {
                    break
                }
                addTask(for: path, to: &group)
            }

            var results: [String: [OCRTextObservation]] = [:]
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
        to group: inout TaskGroup<(String, [OCRTextObservation])>
    ) {
        let repository = self.repository
        group.addTask {
            let lines = await repository.observations(for: path)
                .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return (path, lines)
        }
    }
}

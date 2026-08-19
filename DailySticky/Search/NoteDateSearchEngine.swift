import Foundation

struct NoteDateSearchEngine {
    private struct IndexedDate {
        let document: NoteSearchDocument
        let month: Int
        let numericComponents: Set<Int>
    }

    private var indexedDates: [IndexedDate] = []
    private var monthEngine = NoteSearchEngine()
    private var snippetByDateKey: [String: String] = [:]

    mutating func rebuild(
        with documents: [NoteSearchDocument],
        locale: Locale
    ) {
        let formatters = Self.formatters(for: locale)
        monthEngine.rebuild(with: Self.monthDocuments(for: locale))
        snippetByDateKey = Dictionary(
            uniqueKeysWithValues: documents.map { document in
                (document.dateKey, Self.previewText(for: document))
            }
        )
        indexedDates = documents.compactMap { document in
            guard let date = Self.date(from: document.dateKey),
                  let components = Self.numericComponents(from: document.dateKey)
            else {
                return nil
            }
            return IndexedDate(
                document: NoteSearchDocument(
                    dateKey: document.dateKey,
                    text: Self.aliases(for: date, dateKey: document.dateKey, formatters: formatters)
                        .joined(separator: "\n"),
                    updatedAt: document.updatedAt
                ),
                month: components.month,
                numericComponents: Set([components.year, components.month, components.day])
            )
        }
    }

    mutating func releaseIndex() {
        indexedDates = []
        monthEngine.rebuild(with: [])
        snippetByDateKey = [:]
    }

    func search(_ query: String, limit: Int = 40) -> [NoteSearchResult] {
        let numericQueryComponents = query
            .split { !$0.isNumber }
            .compactMap { Int($0) }
        let recognizedMonth = recognizedMonth(in: query)
        guard !numericQueryComponents.isEmpty || recognizedMonth != nil else {
            return []
        }

        let candidateDocuments = indexedDates
            .filter { indexedDate in
                let monthMatches = recognizedMonth.map { indexedDate.month == $0 } ?? true
                return monthMatches
                    && numericQueryComponents.allSatisfy(indexedDate.numericComponents.contains)
            }
            .map(\.document)
        let candidateEngine = NoteSearchEngine(documents: candidateDocuments)

        return candidateEngine.search(query, limit: max(limit, candidateEngine.documentCount))
            .map { result in
                NoteSearchResult(
                    dateKey: result.dateKey,
                    snippet: snippetByDateKey[result.dateKey] ?? "",
                    score: result.score + 1,
                    matchingLineCount: 0,
                    source: .note,
                    kind: .date
                )
            }
            .sorted {
                if abs($0.score - $1.score) > 0.0001 {
                    return $0.score > $1.score
                }
                return $0.dateKey > $1.dateKey
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func aliases(
        for date: Date,
        dateKey: String,
        formatters: [DateFormatter]
    ) -> [String] {
        var seen = Set<String>()
        return ([dateKey] + formatters.map { $0.string(from: date) }).filter {
            seen.insert($0).inserted
        }
    }

    private func recognizedMonth(in query: String) -> Int? {
        let words = SearchTextNormalizer.normalize(query)
            .split { character in
                character.unicodeScalars.allSatisfy { !CharacterSet.letters.contains($0) }
            }
            .filter { $0.count >= 2 }

        return words.lazy.compactMap { word in
            monthEngine.search(String(word), limit: 1).first.flatMap {
                Int($0.dateKey)
            }
        }.first
    }

    private static func monthDocuments(for locale: Locale) -> [NoteSearchDocument] {
        let formatters = ["MMMM", "MMM", "LLLL", "LLL"].map { template in
            let formatter = DateFormatter()
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            formatter.calendar = calendar
            formatter.locale = normalizedLocale(locale)
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        return (1...12).compactMap { month in
            guard let date = calendar.date(from: DateComponents(year: 2000, month: month, day: 1)) else {
                return nil
            }
            var seen = Set<String>()
            let aliases = formatters.map { $0.string(from: date) }.filter {
                seen.insert($0).inserted
            }
            return NoteSearchDocument(
                dateKey: String(month),
                text: aliases.joined(separator: "\n"),
                updatedAt: .distantPast
            )
        }
    }

    private static func formatters(for locale: Locale) -> [DateFormatter] {
        [
            "yMMMMEEEEd",
            "yMMMMd",
            "yMMMd",
            "yMd",
            "MMMMd",
            "MMMd",
            "Md",
            "MMMdEEE"
        ].map { template in
            let formatter = DateFormatter()
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            formatter.calendar = calendar
            formatter.locale = Self.normalizedLocale(locale)
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
    }

    private static func previewText(for document: NoteSearchDocument) -> String {
        let notePreview = document.text
            .components(separatedBy: .newlines)
            .lazy
            .map(SearchTextNormalizer.displayText)
            .first { !$0.isEmpty }
        if let notePreview {
            return notePreview
        }
        return document.supplementalLines.lazy
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private static func date(from dateKey: String) -> Date? {
        dateKeyFormatter.date(from: dateKey)
    }

    private static func numericComponents(
        from dateKey: String
    ) -> (year: Int, month: Int, day: Int)? {
        let components = dateKey.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else {
            return nil
        }
        return (components[0], components[1], components[2])
    }

    private static func normalizedLocale(_ locale: Locale) -> Locale {
        guard locale.language.languageCode?.identifier == "en" else {
            return locale
        }
        return Locale(identifier: "en_US")
    }

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()
}

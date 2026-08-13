import Foundation
import NaturalLanguage

struct NoteSearchDocument: Equatable {
    let dateKey: String
    let text: String
    let updatedAt: Date
}

struct NoteSearchResult: Identifiable, Equatable {
    var id: String { dateKey }

    func matchCountLabel(language: AppLanguage) -> String {
        language.matchCount(matchingLineCount)
    }

    let dateKey: String
    let snippet: String
    let score: Double
    let matchingLineCount: Int
}

struct NoteSearchEngine {
    private struct IndexedLine {
        let displayText: String
        let normalizedText: String
        let tokens: [String]
    }

    private struct IndexedDocument {
        let dateKey: String
        let updatedAt: Date
        let normalizedText: String
        let tokens: [String]
        let lines: [IndexedLine]
    }

    private var documents: [IndexedDocument] = []

    var documentCount: Int {
        documents.count
    }

    init(documents: [NoteSearchDocument] = []) {
        rebuild(with: documents)
    }

    init(pages: [String: DayPage]) {
        rebuild(with: pages.values.map {
            NoteSearchDocument(dateKey: $0.dateKey, text: $0.noteText, updatedAt: $0.updatedAt)
        })
    }

    mutating func rebuild(with documents: [NoteSearchDocument]) {
        self.documents = documents.compactMap(Self.indexDocument)
    }

    mutating func rebuild(with pages: [String: DayPage]) {
        rebuild(with: pages.values.map {
            NoteSearchDocument(dateKey: $0.dateKey, text: $0.noteText, updatedAt: $0.updatedAt)
        })
    }

    func search(_ query: String, limit: Int = 40) -> [NoteSearchResult] {
        let normalizedQuery = SearchTextNormalizer.normalize(query)
        guard !normalizedQuery.isEmpty, limit > 0 else {
            return []
        }

        let queryTokens = SearchTextNormalizer.tokens(in: normalizedQuery)
        guard !queryTokens.isEmpty else {
            return []
        }

        return documents.compactMap { document -> NoteSearchResult? in
            guard let documentScore = Self.matchScore(
                query: normalizedQuery,
                queryTokens: queryTokens,
                candidate: document.normalizedText,
                candidateTokens: document.tokens
            ) else {
                return nil
            }

            let rankedLines = document.lines.compactMap { line -> (IndexedLine, Double)? in
                guard let score = Self.partialMatchScore(
                    query: normalizedQuery,
                    queryTokens: queryTokens,
                    candidate: line.normalizedText,
                    candidateTokens: line.tokens
                ) else {
                    return nil
                }
                return (line, score)
            }

            let bestLine = rankedLines.max { $0.1 < $1.1 }?.0 ?? document.lines[0]
            let matchingLineCount = max(
                1,
                rankedLines.filter { $0.1 >= Self.minimumAcceptedScore }.count
            )

            return NoteSearchResult(
                dateKey: document.dateKey,
                snippet: bestLine.displayText,
                score: documentScore,
                matchingLineCount: matchingLineCount
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

    private static let minimumAcceptedScore = 0.61

    private static func indexDocument(_ document: NoteSearchDocument) -> IndexedDocument? {
        let lines = document.text
            .components(separatedBy: .newlines)
            .compactMap { rawLine -> IndexedLine? in
                let displayText = SearchTextNormalizer.displayText(from: rawLine)
                let normalizedText = SearchTextNormalizer.normalize(displayText)
                guard !normalizedText.isEmpty else {
                    return nil
                }

                return IndexedLine(
                    displayText: displayText,
                    normalizedText: normalizedText,
                    tokens: SearchTextNormalizer.tokens(in: normalizedText)
                )
            }

        guard !lines.isEmpty else {
            return nil
        }

        let normalizedText = lines.map(\.normalizedText).joined(separator: " ")
        return IndexedDocument(
            dateKey: document.dateKey,
            updatedAt: document.updatedAt,
            normalizedText: normalizedText,
            tokens: lines.flatMap(\.tokens),
            lines: lines
        )
    }

    private static func matchScore(
        query: String,
        queryTokens: [String],
        candidate: String,
        candidateTokens: [String]
    ) -> Double? {
        if let exactRange = candidate.range(of: query) {
            let position = candidate.distance(from: candidate.startIndex, to: exactRange.lowerBound)
            let positionBonus = 0.08 / Double(position + 1)
            return min(1, 0.91 + positionBonus)
        }

        if SearchTextNormalizer.containsCJK(query),
           let compactScore = compactWindowScore(query: query, candidate: candidate),
           compactScore >= 0.70 {
            return min(0.89, compactScore + 0.08)
        }

        let tokenScores = queryTokens.map { queryToken in
            candidateTokens.lazy
                .map { tokenSimilarity(query: queryToken, candidate: $0) }
                .max() ?? 0
        }

        guard let weakest = tokenScores.min(), weakest >= 0.52 else {
            return nil
        }

        let average = tokenScores.reduce(0, +) / Double(tokenScores.count)
        let coverageBonus = min(0.06, Double(queryTokens.count - 1) * 0.02)
        let score = average * 0.92 + coverageBonus
        return score >= minimumAcceptedScore ? min(score, 0.90) : nil
    }

    private static func partialMatchScore(
        query: String,
        queryTokens: [String],
        candidate: String,
        candidateTokens: [String]
    ) -> Double? {
        if let score = matchScore(
            query: query,
            queryTokens: queryTokens,
            candidate: candidate,
            candidateTokens: candidateTokens
        ) {
            return score
        }

        let strongestToken = queryTokens.lazy
            .flatMap { queryToken in
                candidateTokens.lazy.map { tokenSimilarity(query: queryToken, candidate: $0) }
            }
            .max() ?? 0
        return strongestToken >= 0.52 ? strongestToken * 0.75 : nil
    }

    private static func compactWindowScore(query: String, candidate: String) -> Double? {
        let compactQuery = Array(query.filter { !$0.isWhitespace })
        let compactCandidate = Array(candidate.filter { !$0.isWhitespace })
        let maximumDistance = allowedEditDistance(for: compactQuery.count)
        guard maximumDistance > 0,
              let distance = bestBoundedDistance(
                  query: compactQuery,
                  candidate: compactCandidate,
                  maximumDistance: maximumDistance
              )
        else {
            return nil
        }
        return 1 - Double(distance) / Double(max(compactQuery.count, 1))
    }

    private static func tokenSimilarity(query: String, candidate: String) -> Double {
        guard !query.isEmpty, !candidate.isEmpty else {
            return 0
        }
        if query == candidate {
            return 1
        }
        if candidate.hasPrefix(query) {
            return query.count >= 2 ? 0.93 : 0.74
        }
        if candidate.contains(query) {
            return query.count >= 2 ? 0.88 : 0.68
        }

        let queryCharacters = Array(query)
        let candidateCharacters = Array(candidate)
        let maximumDistance = allowedEditDistance(for: queryCharacters.count)
        guard maximumDistance > 0 else {
            return 0
        }

        let distance = bestBoundedDistance(
            query: queryCharacters,
            candidate: candidateCharacters,
            maximumDistance: maximumDistance
        )
        guard let distance else {
            return 0
        }

        return 1 - (Double(distance) / Double(max(queryCharacters.count, candidateCharacters.count)))
    }

    private static func allowedEditDistance(for length: Int) -> Int {
        switch length {
        case 0...2:
            return 0
        case 3...5:
            return 1
        case 6...9:
            return 2
        default:
            return max(2, Int(Double(length) * 0.24))
        }
    }

    private static func bestBoundedDistance(
        query: [Character],
        candidate: [Character],
        maximumDistance: Int
    ) -> Int? {
        let minimumWindowLength = max(1, query.count - maximumDistance)
        let maximumWindowLength = min(candidate.count, query.count + maximumDistance)

        guard minimumWindowLength <= maximumWindowLength else {
            return boundedLevenshteinDistance(query, candidate, maximumDistance: maximumDistance)
        }

        var bestDistance: Int?
        for windowLength in minimumWindowLength...maximumWindowLength {
            guard windowLength <= candidate.count else {
                continue
            }

            for start in 0...(candidate.count - windowLength) {
                let window = Array(candidate[start..<(start + windowLength)])
                if let distance = boundedLevenshteinDistance(
                    query,
                    window,
                    maximumDistance: min(maximumDistance, bestDistance ?? maximumDistance)
                ) {
                    bestDistance = min(bestDistance ?? distance, distance)
                    if bestDistance == 0 {
                        return 0
                    }
                }
            }
        }
        return bestDistance
    }

    private static func boundedLevenshteinDistance(
        _ left: [Character],
        _ right: [Character],
        maximumDistance: Int
    ) -> Int? {
        guard abs(left.count - right.count) <= maximumDistance else {
            return nil
        }
        if left.isEmpty {
            return right.count <= maximumDistance ? right.count : nil
        }
        if right.isEmpty {
            return left.count <= maximumDistance ? left.count : nil
        }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            var rowMinimum = current[0]

            for rightIndex in 1...right.count {
                let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    min(previous[rightIndex] + 1, current[rightIndex - 1] + 1),
                    previous[rightIndex - 1] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[rightIndex])
            }

            if rowMinimum > maximumDistance {
                return nil
            }
            swap(&previous, &current)
        }

        return previous[right.count] <= maximumDistance ? previous[right.count] : nil
    }
}

private enum SearchTextNormalizer {
    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    static func normalize(_ text: String) -> String {
        let compatibilityNormalized = text.precomposedStringWithCompatibilityMapping
        let folded = compatibilityNormalized.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let kanaNormalized = folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded

        var scalars = String.UnicodeScalarView()
        var previousWasSpace = true
        for scalar in kanaNormalized.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.symbols.contains(scalar) {
                scalars.append(scalar)
                previousWasSpace = false
            } else if !previousWasSpace {
                scalars.append(" ")
                previousWasSpace = true
            }
        }

        return String(scalars).trimmingCharacters(in: .whitespaces)
    }

    static func tokens(in normalizedText: String) -> [String] {
        guard !normalizedText.isEmpty else {
            return []
        }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = normalizedText
        let tokenRanges = tokenizer.tokens(for: normalizedText.startIndex..<normalizedText.endIndex)
        let tokens = tokenRanges.map { String(normalizedText[$0]) }.filter { !$0.isEmpty }
        return tokens.isEmpty ? normalizedText.split(separator: " ").map(String.init) : tokens
    }

    static func displayText(from rawLine: String) -> String {
        var text = rawLine.trimmingCharacters(in: .whitespaces)
        text = stripBlockPrefix(from: text)

        for marker in ["**", "__", "~~", "`"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func stripBlockPrefix(from text: String) -> String {
        if let taskContent = taskContent(in: text) {
            return taskContent
        }

        var index = text.startIndex
        while index < text.endIndex, text[index] == "#" {
            index = text.index(after: index)
        }
        if index > text.startIndex, index < text.endIndex, text[index].isWhitespace {
            return String(text[text.index(after: index)...])
        }

        if let first = text.first, ["-", "*", "+", ">"].contains(first) {
            let next = text.index(after: text.startIndex)
            if next < text.endIndex, text[next].isWhitespace {
                return String(text[text.index(after: next)...])
            }
        }

        if let orderedEnd = orderedPrefixEnd(in: text) {
            return String(text[orderedEnd...])
        }
        return text
    }

    private static func taskContent(in text: String) -> String? {
        let prefixes = ["- [ ] ", "- [x] ", "- [X] ", "-[ ] ", "-[x] ", "-[X] ", "-[] "]
        guard let prefix = prefixes.first(where: text.hasPrefix) else {
            return nil
        }
        return String(text.dropFirst(prefix.count))
    }

    private static func orderedPrefixEnd(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex, text[index].isNumber {
            index = text.index(after: index)
        }
        guard index > text.startIndex, index < text.endIndex, text[index] == "." else {
            return nil
        }
        index = text.index(after: index)
        guard index < text.endIndex, text[index].isWhitespace else {
            return nil
        }
        return text.index(after: index)
    }
}

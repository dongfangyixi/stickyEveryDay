import Foundation
import NaturalLanguage

enum NoteSearchLineSource: Equatable, Sendable {
    case note
    case image(attachmentPath: String)
}

struct NoteSearchSupplementalLine: Equatable, Sendable {
    let text: String
    let source: NoteSearchLineSource
    let location: NoteSearchMatchLocation?

    init(
        text: String,
        source: NoteSearchLineSource,
        location: NoteSearchMatchLocation? = nil
    ) {
        self.text = text
        self.source = source
        self.location = location
    }
}

struct NoteSearchDocument: Equatable, Sendable {
    let dateKey: String
    let text: String
    let updatedAt: Date
    let supplementalLines: [NoteSearchSupplementalLine]

    init(
        dateKey: String,
        text: String,
        updatedAt: Date,
        supplementalLines: [NoteSearchSupplementalLine] = []
    ) {
        self.dateKey = dateKey
        self.text = text
        self.updatedAt = updatedAt
        self.supplementalLines = supplementalLines
    }
}

enum NoteSearchResultKind: Equatable, Sendable {
    case content
    case date
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
    let source: NoteSearchLineSource
    let kind: NoteSearchResultKind
    let matchLocation: NoteSearchMatchLocation?

    init(
        dateKey: String,
        snippet: String,
        score: Double,
        matchingLineCount: Int,
        source: NoteSearchLineSource,
        kind: NoteSearchResultKind = .content,
        matchLocation: NoteSearchMatchLocation? = nil
    ) {
        self.dateKey = dateKey
        self.snippet = snippet
        self.score = score
        self.matchingLineCount = matchingLineCount
        self.source = source
        self.kind = kind
        self.matchLocation = matchLocation
    }
}

struct NoteSearchIndexUpdate: Equatable {
    let insertedOrUpdatedCount: Int
    let removedCount: Int

    var hasChanges: Bool {
        insertedOrUpdatedCount > 0 || removedCount > 0
    }
}

struct NoteSearchEngine {
    private struct IndexedToken {
        let text: String
        let containsCJK: Bool

        init(_ text: String) {
            self.text = text
            self.containsCJK = SearchTextNormalizer.containsCJK(text)
        }
    }

    private struct TokenPair: Hashable {
        let query: String
        let candidate: String
    }

    private struct IndexedLine {
        let rawText: String
        let displayText: String
        let normalizedText: String
        let tokens: [IndexedToken]
        let containsCJK: Bool
        let source: NoteSearchLineSource
        let location: NoteSearchMatchLocation?
    }

    private struct IndexedDocument {
        let dateKey: String
        let updatedAt: Date
        let normalizedText: String
        let tokens: [IndexedToken]
        let containsCJK: Bool
        let cjkCandidateText: String?
        let lines: [IndexedLine]
    }

    private var sourceDocumentsByDateKey: [String: NoteSearchDocument] = [:]
    private var documentsByDateKey: [String: IndexedDocument] = [:]

    var documentCount: Int {
        documentsByDateKey.count
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
        sourceDocumentsByDateKey = [:]
        documentsByDateKey = [:]
        for document in documents {
            sourceDocumentsByDateKey[document.dateKey] = document
            if let indexedDocument = Self.indexDocument(document) {
                documentsByDateKey[document.dateKey] = indexedDocument
            }
        }
    }

    mutating func rebuild(with pages: [String: DayPage]) {
        rebuild(with: pages.values.map {
            NoteSearchDocument(dateKey: $0.dateKey, text: $0.noteText, updatedAt: $0.updatedAt)
        })
    }

    @discardableResult
    mutating func synchronize(with documents: [NoteSearchDocument]) -> NoteSearchIndexUpdate {
        var incomingByDateKey: [String: NoteSearchDocument] = [:]
        for document in documents {
            incomingByDateKey[document.dateKey] = document
        }

        let removedDateKeys = sourceDocumentsByDateKey.keys.filter {
            incomingByDateKey[$0] == nil
        }
        for dateKey in removedDateKeys {
            sourceDocumentsByDateKey.removeValue(forKey: dateKey)
            documentsByDateKey.removeValue(forKey: dateKey)
        }

        var insertedOrUpdatedCount = 0
        for (dateKey, document) in incomingByDateKey {
            guard sourceDocumentsByDateKey[dateKey] != document else {
                continue
            }
            sourceDocumentsByDateKey[dateKey] = document
            if let indexedDocument = Self.indexDocument(document) {
                documentsByDateKey[dateKey] = indexedDocument
            } else {
                documentsByDateKey.removeValue(forKey: dateKey)
            }
            insertedOrUpdatedCount += 1
        }

        return NoteSearchIndexUpdate(
            insertedOrUpdatedCount: insertedOrUpdatedCount,
            removedCount: removedDateKeys.count
        )
    }

    func search(_ query: String, limit: Int = 40) -> [NoteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = SearchTextNormalizer.normalize(trimmedQuery)
        guard !normalizedQuery.isEmpty, limit > 0 else {
            return []
        }

        let queryTokens = SearchTextNormalizer.tokens(in: normalizedQuery).map(IndexedToken.init)
        guard !queryTokens.isEmpty else {
            return []
        }

        var similarityCache: [TokenPair: Double] = [:]
        var results: [NoteSearchResult] = []
        for document in documentsByDateKey.values {
            guard let documentScore = Self.matchScore(
                query: normalizedQuery,
                queryTokens: queryTokens,
                candidate: document.normalizedText,
                candidateTokens: document.tokens,
                candidateContainsCJK: document.containsCJK,
                cjkCandidate: document.cjkCandidateText,
                similarityCache: &similarityCache
            ) else {
                continue
            }

            let exactLines = document.lines.compactMap { line -> (IndexedLine, Double)? in
                guard let range = line.normalizedText.range(of: normalizedQuery) else {
                    return nil
                }
                let position = line.normalizedText.distance(
                    from: line.normalizedText.startIndex,
                    to: range.lowerBound
                )
                return (line, min(1, 0.91 + 0.08 / Double(position + 1)))
            }
            let rankedLines = exactLines.isEmpty
                ? document.lines.compactMap { line -> (IndexedLine, Double)? in
                    guard let score = Self.partialMatchScore(
                        query: normalizedQuery,
                        queryTokens: queryTokens,
                        candidate: line.normalizedText,
                        candidateTokens: line.tokens,
                        candidateContainsCJK: line.containsCJK,
                        cjkCandidate: line.containsCJK ? line.normalizedText : nil,
                        similarityCache: &similarityCache
                    ) else {
                        return nil
                    }
                    return (line, score)
                }
                : exactLines

            let bestLine = rankedLines.max { $0.1 < $1.1 }?.0 ?? document.lines[0]
            let matchingLineCount = max(
                1,
                rankedLines.filter { $0.1 >= Self.minimumAcceptedScore }.count
            )

            results.append(NoteSearchResult(
                dateKey: document.dateKey,
                snippet: bestLine.displayText,
                score: documentScore,
                matchingLineCount: matchingLineCount,
                source: bestLine.source,
                matchLocation: Self.matchLocation(for: trimmedQuery, in: bestLine)
            ))
        }
        return results.sorted {
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
        let noteLines = rawLines(in: document.text).compactMap { line -> IndexedLine? in
                let (rawLine, lineRange) = line
                let displayText = SearchTextNormalizer.displayText(from: rawLine)
                let normalizedText = SearchTextNormalizer.normalize(displayText)
                guard !normalizedText.isEmpty else {
                    return nil
                }
                let tokens = indexedTokens(in: normalizedText)

                return IndexedLine(
                    rawText: rawLine,
                    displayText: displayText,
                    normalizedText: normalizedText,
                    tokens: tokens,
                    containsCJK: tokens.contains(where: \.containsCJK),
                    source: .note,
                    location: .note(range: lineRange)
                )
            }

        let supplementalLines = document.supplementalLines.compactMap { line -> IndexedLine? in
            let displayText = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedText = SearchTextNormalizer.normalize(displayText)
            guard !normalizedText.isEmpty else {
                return nil
            }
            let tokens = indexedTokens(in: normalizedText)

            return IndexedLine(
                rawText: line.text,
                displayText: displayText,
                normalizedText: normalizedText,
                tokens: tokens,
                containsCJK: tokens.contains(where: \.containsCJK),
                source: line.source,
                location: line.location
            )
        }
        let lines = noteLines + supplementalLines

        guard !lines.isEmpty else {
            return nil
        }

        let normalizedText = lines.map(\.normalizedText).joined(separator: " ")
        let cjkCandidateText = lines
            .filter(\.containsCJK)
            .map(\.normalizedText)
            .joined(separator: " ")
        return IndexedDocument(
            dateKey: document.dateKey,
            updatedAt: document.updatedAt,
            normalizedText: normalizedText,
            tokens: uniqueTokens(in: lines),
            containsCJK: lines.contains(where: \.containsCJK),
            cjkCandidateText: cjkCandidateText.isEmpty ? nil : cjkCandidateText,
            lines: lines
        )
    }

    private static func indexedTokens(in normalizedText: String) -> [IndexedToken] {
        var seen = Set<String>()
        return SearchTextNormalizer.tokens(in: normalizedText).compactMap { token in
            guard seen.insert(token).inserted else {
                return nil
            }
            return IndexedToken(token)
        }
    }

    private static func uniqueTokens(in lines: [IndexedLine]) -> [IndexedToken] {
        var seen = Set<String>()
        return lines.flatMap(\.tokens).filter { token in
            seen.insert(token.text).inserted
        }
    }

    private static func rawLines(in text: String) -> [(String, NSRange)] {
        let source = text as NSString
        guard source.length > 0 else {
            return []
        }

        var lines: [(String, NSRange)] = []
        var location = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            var contentLength = lineRange.length
            while contentLength > 0 {
                let character = source.character(at: lineRange.location + contentLength - 1)
                guard character == 0x0A || character == 0x0D else {
                    break
                }
                contentLength -= 1
            }
            let contentRange = NSRange(location: lineRange.location, length: contentLength)
            lines.append((source.substring(with: contentRange), contentRange))
            location = NSMaxRange(lineRange)
        }
        return lines
    }

    private static func matchLocation(
        for query: String,
        in line: IndexedLine
    ) -> NoteSearchMatchLocation? {
        guard !query.isEmpty else {
            return line.location
        }

        let localRange = (line.rawText as NSString).range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        )
        guard localRange.location != NSNotFound else {
            return line.location
        }

        switch line.location {
        case let .note(range):
            return .note(
                range: NSRange(
                    location: range.location + localRange.location,
                    length: localRange.length
                )
            )
        case let .image(
            attachmentPath,
            markdownRange,
            observationIndex,
            _,
            normalizedBoundingBox
        ):
            return .image(
                attachmentPath: attachmentPath,
                markdownRange: markdownRange,
                observationIndex: observationIndex,
                characterRange: localRange,
                normalizedBoundingBox: normalizedBoundingBox
            )
        case nil:
            return nil
        }
    }

    private static func matchScore(
        query: String,
        queryTokens: [IndexedToken],
        candidate: String,
        candidateTokens: [IndexedToken],
        candidateContainsCJK: Bool,
        cjkCandidate: String?,
        similarityCache: inout [TokenPair: Double]
    ) -> Double? {
        if let exactRange = candidate.range(of: query) {
            let position = candidate.distance(from: candidate.startIndex, to: exactRange.lowerBound)
            let positionBonus = 0.08 / Double(position + 1)
            return min(1, 0.91 + positionBonus)
        }

        if SearchTextNormalizer.containsCJK(query), candidateContainsCJK,
           let cjkCandidate,
           let compactScore = compactWindowScore(query: query, candidate: cjkCandidate),
           compactScore >= 0.70 {
            return min(0.89, compactScore + 0.08)
        }

        var tokenScores: [Double] = []
        tokenScores.reserveCapacity(queryTokens.count)
        for queryToken in queryTokens {
            tokenScores.append(
                bestTokenScore(
                    query: queryToken,
                    candidates: candidateTokens,
                    cache: &similarityCache
                )
            )
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
        queryTokens: [IndexedToken],
        candidate: String,
        candidateTokens: [IndexedToken],
        candidateContainsCJK: Bool,
        cjkCandidate: String?,
        similarityCache: inout [TokenPair: Double]
    ) -> Double? {
        if let score = matchScore(
            query: query,
            queryTokens: queryTokens,
            candidate: candidate,
            candidateTokens: candidateTokens,
            candidateContainsCJK: candidateContainsCJK,
            cjkCandidate: cjkCandidate,
            similarityCache: &similarityCache
        ) {
            return score
        }

        var strongestToken = 0.0
        for queryToken in queryTokens {
            strongestToken = max(
                strongestToken,
                bestTokenScore(
                    query: queryToken,
                    candidates: candidateTokens,
                    cache: &similarityCache
                )
            )
        }
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

    private static func tokenSimilarity(query: IndexedToken, candidate: IndexedToken) -> Double {
        guard !query.text.isEmpty, !candidate.text.isEmpty else {
            return 0
        }
        if query.text == candidate.text {
            return 1
        }
        if candidate.text.hasPrefix(query.text) {
            return query.text.count >= 2 ? 0.93 : 0.74
        }
        if candidate.text.contains(query.text) {
            return query.text.count >= 2 ? 0.88 : 0.68
        }

        let queryCharacters = Array(query.text)
        let candidateCharacters = Array(candidate.text)
        let maximumDistance = allowedEditDistance(for: queryCharacters.count)
        guard maximumDistance > 0 else {
            return 0
        }

        guard candidateCharacters.count >= queryCharacters.count - maximumDistance else {
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

        return 1 - (
            Double(distance)
                / Double(max(queryCharacters.count, candidateCharacters.count))
        )
    }

    private static func cachedTokenSimilarity(
        query: IndexedToken,
        candidate: IndexedToken,
        cache: inout [TokenPair: Double]
    ) -> Double {
        let key = TokenPair(query: query.text, candidate: candidate.text)
        if let score = cache[key] {
            return score
        }
        let score = tokenSimilarity(query: query, candidate: candidate)
        cache[key] = score
        return score
    }

    private static func bestTokenScore(
        query: IndexedToken,
        candidates: [IndexedToken],
        cache: inout [TokenPair: Double]
    ) -> Double {
        var bestScore = 0.0
        for candidate in candidates {
            bestScore = max(
                bestScore,
                cachedTokenSimilarity(query: query, candidate: candidate, cache: &cache)
            )
            if bestScore == 1 {
                return bestScore
            }
        }
        return bestScore
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
        guard !query.isEmpty else {
            return 0
        }
        guard !candidate.isEmpty else {
            return query.count <= maximumDistance ? query.count : nil
        }

        // The zero first row makes candidate prefixes free. The final row's
        // minimum is therefore the distance to the best candidate substring.
        var previous = Array(repeating: 0, count: candidate.count + 1)
        var current = Array(repeating: 0, count: candidate.count + 1)

        for queryIndex in 1...query.count {
            current[0] = queryIndex
            for candidateIndex in 1...candidate.count {
                let substitutionCost = query[queryIndex - 1] == candidate[candidateIndex - 1] ? 0 : 1
                current[candidateIndex] = min(
                    min(previous[candidateIndex] + 1, current[candidateIndex - 1] + 1),
                    previous[candidateIndex - 1] + substitutionCost
                )
            }
            swap(&previous, &current)
        }

        guard let bestDistance = previous.min(), bestDistance <= maximumDistance else {
            return nil
        }
        return bestDistance
    }
}

enum SearchTextNormalizer {
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
        if let image = MarkdownImageReferenceParser.reference(in: text) {
            return image.altText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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

import Foundation
import NaturalLanguage

/// A page's text split into numbered sentences. The model points at a sentence and quotes a
/// phrase inside it, which keeps quote matching local and stops highlights landing in the wrong place.
public struct PageSentences: Sendable {
    public struct Sentence: Sendable {
        /// UTF-16 range in the page's original text.
        public var range: NSRange
        /// Whitespace-collapsed text shown to the model.
        public var text: String
    }

    public let text: String
    public let sentences: [Sentence]

    public init(_ text: String) {
        self.text = text
        var found: [Sentence] = []
        // PDF text breaks at every printed line, which the tokenizer would treat as sentence ends.
        // Split a copy where single line breaks are spaces; it has the same UTF-16 length, so ranges carry over.
        let flowing = text.replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"(?<!\n)\n(?!\n)"#, with: " ", options: .regularExpression)
        let original = text as NSString
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = flowing
        tokenizer.enumerateTokens(in: flowing.startIndex..<flowing.endIndex) { range, _ in
            let r = NSRange(range, in: flowing)
            let clean = Self.clean(original.substring(with: r))
            if clean.count >= 2 { found.append(Sentence(range: r, text: clean)) }
            return true
        }
        sentences = found
    }

    /// Joins words hyphenated across line breaks and collapses whitespace, the same way QuoteMatcher normalizes.
    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"[-­]\s*\n\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Numbered lines for the prompt, clipped to roughly `limit` characters.
    public func numbered(limit: Int) -> String {
        var out: [String] = []
        var used = 0
        for (i, s) in sentences.enumerated() {
            used += s.text.count + 6
            if used > limit { break }
            out.append("[\(i + 1)] \(s.text)")
        }
        return out.joined(separator: "\n")
    }

    func sentenceIndex(containing range: NSRange) -> Int? {
        sentences.firstIndex { NSLocationInRange(range.location, $0.range) }
    }

    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// A highlight resolved to an exact place on the page, ready to draw.
public struct PlannedHighlight: Equatable {
    public var range: NSRange
    public var category: String
    public var note: String
}

/// Turns the model's suggestions into the final set of highlights: finds each quote on the page,
/// then keeps the most important ones that fit the density budget, with no overlaps and at most
/// one highlight per sentence.
public enum HighlightPlanner {
    static let maxWords = 24
    static let minWords = 3

    public struct Plan {
        public var highlights: [PlannedHighlight] = []
        /// Quotes that couldn't be found in the page text.
        public var missed: [String] = []
        /// Found, but cut for overlap, length or the density budget.
        public var dropped = 0
    }

    public static func plan(_ raw: [RawHighlight], sentences: PageSentences, density: HighlightDensity,
                            maxPerPage: Int) -> Plan {
        var result = Plan()
        let text = sentences.text as NSString
        var candidates: [(range: NSRange, sentence: Int?, raw: RawHighlight, order: Int)] = []

        for (order, h) in raw.enumerated() {
            guard let range = locate(h, in: sentences) else {
                result.missed.append(h.quote)
                continue
            }
            let words = text.substring(with: range).split(whereSeparator: \.isWhitespace).count
            if words > maxWords || words < minWords {
                result.dropped += 1
                continue
            }
            candidates.append((range, sentences.sentenceIndex(containing: range), h, order))
        }

        // Most important first; the model's own order breaks ties.
        candidates.sort { ($0.raw.importance ?? 2, -$0.order) > ($1.raw.importance ?? 2, -$1.order) }

        let byLength = max(2, sentences.wordCount / density.wordsPerHighlight)
        let maxCount = max(1, min(maxPerPage, density.cap, byLength))
        let charBudget = max(140, Int(Double(text.length) * density.coverage))
        var usedChars = 0
        var usedSentences = Set<Int>()
        var accepted: [(range: NSRange, raw: RawHighlight)] = []

        for c in candidates {
            let overlaps = accepted.contains { NSIntersectionRange($0.range, c.range).length > 0 }
            let sameSentence = c.sentence.map { usedSentences.contains($0) } ?? false
            guard accepted.count < maxCount, !overlaps, !sameSentence,
                  usedChars + c.range.length <= charBudget else {
                result.dropped += 1
                continue
            }
            accepted.append((c.range, c.raw))
            usedChars += c.range.length
            if let s = c.sentence { usedSentences.insert(s) }
        }

        result.highlights = accepted
            .sorted { $0.range.location < $1.range.location }
            .map { PlannedHighlight(range: $0.range, category: $0.raw.category,
                                    note: ($0.raw.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) }
        return result
    }

    /// Looks inside the sentence the model named first (where a loose match is safe),
    /// then anywhere on the page.
    static func locate(_ h: RawHighlight, in sentences: PageSentences) -> NSRange? {
        if let n = h.sentence, n >= 1, n <= sentences.sentences.count {
            let s = sentences.sentences[n - 1]
            let local = (sentences.text as NSString).substring(with: s.range)
            if let r = QuoteMatcher.find(h.quote, in: local) {
                return NSRange(location: s.range.location + r.location, length: r.length)
            }
        }
        return QuoteMatcher.find(h.quote, in: sentences.text)
    }
}

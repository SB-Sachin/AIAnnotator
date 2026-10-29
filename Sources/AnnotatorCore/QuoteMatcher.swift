import Foundation

/// Finds a model-produced quote inside page text, tolerating differences in whitespace,
/// case, quotation marks, dashes, ligatures and hyphenated line breaks.
/// Returns an NSRange in UTF-16 units so it can be handed straight to `PDFPage.selection(for:)`.
public enum QuoteMatcher {
    struct Normalized {
        var chars: [Character] = []
        var starts: [Int] = []   // UTF-16 offset in the original where each normalized char begins
        var ends: [Int] = []     // UTF-16 offset in the original where it ends
    }

    static func normalize(_ text: String) -> Normalized {
        var out = Normalized()
        var offset = 0
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let len = c.utf16.count
            defer { offset += len; i += 1 }

            // "-" + line break is a hyphenated word split across lines: drop both.
            if c == "-" || c == "\u{00AD}", i + 1 < chars.count, chars[i + 1].isNewline {
                var j = i + 1
                var skip = 0
                while j < chars.count, chars[j].isWhitespace { skip += chars[j].utf16.count; j += 1 }
                offset += skip
                i = j - 1
                continue
            }
            if c == "\u{00AD}" { continue }
            if c.isWhitespace {
                if let last = out.chars.last, last != " " {
                    append(" ", start: offset, end: offset + len, to: &out)
                }
                continue
            }
            for m in mapped(c) { append(m, start: offset, end: offset + len, to: &out) }
        }
        if out.chars.last == " " { out.chars.removeLast(); out.starts.removeLast(); out.ends.removeLast() }
        return out
    }

    private static func append(_ c: Character, start: Int, end: Int, to out: inout Normalized) {
        out.chars.append(c)
        out.starts.append(start)
        out.ends.append(end)
    }

    private static func mapped(_ c: Character) -> [Character] {
        switch c {
        // Quotation marks and apostrophes are dropped on both sides: models often leave them out of quotes,
        // and OCR reads them inconsistently ('' vs ").
        case "'", "\"", "\u{2018}", "\u{2019}", "\u{201B}", "`", "\u{2032}",
             "\u{201C}", "\u{201D}", "\u{201F}", "\u{2033}", "\u{00AB}", "\u{00BB}": return []
        case "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}": return ["-"]
        case "\u{FB01}": return ["f", "i"]
        case "\u{FB02}": return ["f", "l"]
        case "\u{FB00}": return ["f", "f"]
        case "\u{FB03}": return ["f", "f", "i"]
        case "\u{FB04}": return ["f", "f", "l"]
        case "\u{2026}": return [".", ".", "."]
        default: return Array(String(c).lowercased())
        }
    }

    public static func find(_ quote: String, in text: String) -> NSRange? {
        let page = normalize(text)
        let q = normalize(quote).chars
        guard q.count >= 3, !page.chars.isEmpty else { return nil }

        if let i = indexOf(q, in: page.chars, from: 0) {
            return range(page, i, i + q.count - 1)
        }

        // Ellipsis inside the quote: match first fragment to last fragment.
        let qs = String(q)
        if qs.contains("...") {
            let parts = qs.components(separatedBy: "...").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 3 }
            if let first = parts.first, let last = parts.last, parts.count >= 2,
               let a = indexOf(Array(first), in: page.chars, from: 0),
               let b = indexOf(Array(last), in: page.chars, from: a + first.count) {
                return range(page, a, b + last.count - 1)
            }
        }

        // Fuzzy: anchor on the head and tail of the quote, and only accept a span of about the
        // quote's length. Of several candidates, take the one closest in length.
        let anchor = min(30, max(12, q.count / 3))
        guard q.count >= 24 else { return nil }
        let head = Array(q.prefix(anchor)), tail = Array(q.suffix(anchor))
        let minLen = Int(Double(q.count) * 0.85), maxLen = Int(Double(q.count) * 1.2) + 4
        var best: (start: Int, end: Int, diff: Int)?
        var searchFrom = 0
        while let a = indexOf(head, in: page.chars, from: searchFrom) {
            var tailFrom = a + anchor
            while let b = indexOf(tail, in: page.chars, from: tailFrom) {
                let len = b + tail.count - a
                if len > maxLen { break }
                if len >= minLen {
                    let diff = abs(len - q.count)
                    if best == nil || diff < best!.diff { best = (a, b + tail.count - 1, diff) }
                }
                tailFrom = b + 1
            }
            searchFrom = a + 1
        }
        return best.map { range(page, $0.start, $0.end) }
    }

    private static func range(_ n: Normalized, _ first: Int, _ last: Int) -> NSRange {
        NSRange(location: n.starts[first], length: n.ends[last] - n.starts[first])
    }

    private static func indexOf(_ needle: [Character], in hay: [Character], from start: Int) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count, start <= hay.count - needle.count else { return nil }
        let first = needle[0]
        var i = start
        while i <= hay.count - needle.count {
            if hay[i] == first {
                var k = 1
                while k < needle.count, hay[i + k] == needle[k] { k += 1 }
                if k == needle.count { return i }
            }
            i += 1
        }
        return nil
    }
}

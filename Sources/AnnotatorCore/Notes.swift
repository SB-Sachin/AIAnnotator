import Foundation

public struct CornellNotes: Codable, Hashable {
    public struct Row: Codable, Hashable {
        public var cue: String
        public var notes: [String]
    }
    public var title: String
    public var rows: [Row]
    public var summary: String
}

public struct SectionNotes: Codable, Hashable {
    public struct Item: Codable, Hashable {
        public var text: String
        public var level: Int?
    }
    public struct Section: Codable, Hashable {
        public var heading: String
        public var items: [Item]
    }
    public var title: String
    public var sections: [Section]
}

/// Markdown is the editable source of truth for notes. Cornell notes use a fixed shape the
/// PDF renderer understands: `### cue` rows followed by bullets, then a `## Summary` section.
public enum NotesFormatter {
    public static let cornellRowsHeading = "Cues & Notes"

    public static func markdown(_ n: CornellNotes) -> String {
        var out = "# \(n.title.trimmed)\n\n## \(cornellRowsHeading)\n"
        for row in n.rows {
            out += "\n### \(row.cue.trimmed)\n"
            var notes = row.notes.map(\.trimmed).filter { !$0.isEmpty }
            // Models sometimes restate the cue as a question in the first note; it belongs in the cue column only.
            if notes.count > 1, notes[0].hasSuffix("?") { notes.removeFirst() }
            for note in notes { out += "- \(note)\n" }
        }
        out += "\n## Summary\n\n\(n.summary.trimmed)\n"
        return out
    }

    public static func markdown(_ n: SectionNotes) -> String {
        var out = "# \(n.title.trimmed)\n"
        for section in n.sections {
            out += "\n## \(section.heading.trimmed)\n\n"
            let isParagraph = section.items.count == 1 && section.items[0].text.count > 160
            if isParagraph {
                out += section.items[0].text.trimmed + "\n"
                continue
            }
            for item in section.items where !item.text.trimmed.isEmpty {
                let level = min(max(item.level ?? 0, 0), 3)
                out += String(repeating: "  ", count: level) + "- " + item.text.trimmed + "\n"
            }
        }
        return out
    }
}

public enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(level: Int, text: String)
    case paragraph(String)
}

public enum MarkdownParser {
    public static func parse(_ md: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var para: [String] = []
        func flush() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: " "))); para = [] }
        }
        for raw in md.components(separatedBy: .newlines) {
            let line = raw.trimmed
            if line.isEmpty { flush(); continue }
            if let h = heading(line) { flush(); blocks.append(h); continue }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
            if let marker = ["- ", "* ", "+ ", "• "].first(where: { line.hasPrefix($0) }) {
                flush()
                blocks.append(.bullet(level: indent / 2, text: String(line.dropFirst(marker.count)).trimmed))
                continue
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
               line[line.index(after: dot)...].hasPrefix(" ") {
                flush()
                blocks.append(.bullet(level: indent / 2, text: line))
                continue
            }
            para.append(line)
        }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return .heading(level: hashes, text: String(line.dropFirst(hashes)).trimmed)
    }

    /// Splits `**bold**` runs; single `*` / `_` emphasis markers are dropped.
    public static func inlineRuns(_ text: String) -> [(text: String, bold: Bool)] {
        var runs: [(String, Bool)] = []
        let parts = text.components(separatedBy: "**")
        for (i, part) in parts.enumerated() where !part.isEmpty {
            let clean = part.replacingOccurrences(of: "__", with: "")
            runs.append((clean, i % 2 == 1))
        }
        return runs
    }
}

public struct CornellLayout: Equatable {
    public struct Row: Equatable {
        public var cue: String
        public var notes: [MarkdownBlock]
    }
    public var title: String
    public var rows: [Row]
    public var summary: [MarkdownBlock]

    /// Reads markdown in the shape `NotesFormatter.markdown(_: CornellNotes)` writes,
    /// tolerating user edits (extra headings are kept as notes).
    public init(markdown: String) {
        title = ""
        rows = []
        summary = []
        var inSummary = false
        for block in MarkdownParser.parse(markdown) {
            switch block {
            case .heading(1, let t) where title.isEmpty:
                title = t
            case .heading(2, let t) where t.lowercased().contains("summary"):
                inSummary = true
            case .heading(2, _):
                inSummary = false
            case .heading(let level, let t) where level >= 3 && !inSummary:
                rows.append(Row(cue: t, notes: []))
            default:
                if inSummary {
                    summary.append(block)
                } else if rows.isEmpty {
                    rows.append(Row(cue: "", notes: [block]))
                } else {
                    rows[rows.count - 1].notes.append(block)
                }
            }
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

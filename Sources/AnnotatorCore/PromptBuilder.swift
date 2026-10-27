import Foundation

public struct ModelRequest {
    public var system: String
    public var user: String
    public var schema: [String: Any]
    public var numCtx: Int
}

/// What the model returns for one page. Either half is absent depending on the run mode.
public struct PageResult: Decodable {
    public var highlights: [RawHighlight]?
    public var digest: PageDigest?
}

public struct RawHighlight: Decodable, Hashable {
    public var quote: String
    public var category: String
    public var note: String?
}

public struct PageDigest: Codable, Hashable {
    public struct Term: Codable, Hashable {
        public var term: String
        public var definition: String
    }
    public var summary: String
    public var key_points: [String]
    public var terms: [Term]
}

public enum PromptBuilder {
    static let pageTextLimit = 12_000

    public static func pageRequest(mode: RunMode, preset: HighlightPreset?, pageText: String,
                                   pageNumber: Int, pageCount: Int) -> ModelRequest {
        var tasks: [String] = []
        var props: [String: Any] = [:]
        var required: [String] = []
        if mode.wantsHighlights, let preset {
            tasks.append(highlightTask(preset))
            props["highlights"] = highlightSchema(preset)
            required.append("highlights")
        }
        if mode.wantsNotes {
            tasks.append(digestTask)
            props["digest"] = digestSchema
            required.append("digest")
        }
        let system = """
        You are a careful study assistant helping a student work through assigned reading. \
        You receive one page at a time as an image plus the text extracted from it.

        \(tasks.joined(separator: "\n\n"))

        Respond with JSON only.
        """
        let text = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = text.count > pageTextLimit ? String(text.prefix(pageTextLimit)) : text
        let user = """
        Page \(pageNumber) of \(pageCount).

        EXTRACTED PAGE TEXT (copy quotes from this exactly):
        <<<
        \(clipped.isEmpty ? "(no extractable text on this page)" : clipped)
        >>>
        """
        return ModelRequest(system: system, user: user,
                            schema: ["type": "object", "properties": props, "required": required],
                            numCtx: 8192)
    }

    static func highlightTask(_ preset: HighlightPreset) -> String {
        let cats = preset.categories.map { "- \($0.id): \($0.name) — \($0.description)" }.joined(separator: "\n")
        let noteRule = preset.marginStyle == .none
            ? "\"note\" must be an empty string."
            : "\"note\" is a short margin comment (at most 15 words) saying why the passage matters or what it connects to."
        return """
        TASK: HIGHLIGHT the page in the style "\(preset.name)".
        \(preset.instructions)

        Categories (put the id in "category"):
        \(cats)

        Rules:
        - "quote" must be copied character-for-character from the EXTRACTED PAGE TEXT: one contiguous span of 4 to 25 words. No ellipses, no paraphrasing, no added words.
        - Highlight the key phrase or clause, not whole paragraphs. Be selective: together, highlights should cover well under a third of the page's text.
        - Choose at most \(preset.maxPerPage) highlights. Prefer fewer, high-value highlights. Highlights must not overlap.
        - Skip running headers, page numbers, captions and citations unless they are essential.
        - \(noteRule)
        - If the page has no meaningful text, return an empty list.
        """
    }

    static func highlightSchema(_ preset: HighlightPreset) -> [String: Any] {
        [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "quote": ["type": "string"],
                    "category": ["type": "string", "enum": preset.categories.map(\.id)],
                    "note": ["type": "string"],
                ],
                "required": ["quote", "category", "note"],
            ] as [String: Any],
        ]
    }

    static let digestTask = """
    TASK: DIGEST what a student needs from this page for their notes.
    - "summary": 1–3 sentences on what this page covers.
    - "key_points": the important ideas, claims, facts, steps and examples, each a concise self-contained statement.
    - "terms": vocabulary or named concepts explained on the page, each with a short definition.
    Use information from figures and diagrams in the image as well. Use empty lists when the page has nothing relevant.
    """

    static let digestSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "key_points": ["type": "array", "items": ["type": "string"]],
            "terms": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": ["term": ["type": "string"], "definition": ["type": "string"]],
                    "required": ["term", "definition"],
                ] as [String: Any],
            ] as [String: Any],
        ] as [String: Any],
        "required": ["summary", "key_points", "terms"],
    ]

    public static func notesRequest(template: NoteTemplate, title: String,
                                    digests: [(page: Int, digest: PageDigest)]) -> ModelRequest {
        let layoutGuide: String
        let schema: [String: Any]
        switch template.layout {
        case .cornell:
            layoutGuide = """
            Fill "rows": each row has a "cue" (a short question a student can quiz themselves with, e.g. "What does ATP do?") \
            and "notes" (1–5 concise bullet points that answer it). Notes contain only answers: never repeat or rephrase the \
            cue, never write questions in notes, and don't number the bullets. Aim for 5–12 rows that cover the whole reading in order. \
            "summary" is a 3–5 sentence summary of the entire reading.
            """
            schema = cornellSchema
        case .sections:
            if template.sections.isEmpty {
                layoutGuide = """
                Choose section headings that mirror the structure of the reading. Each item has "text" and a nesting \
                "level" (0 = main bullet, 1 = sub-bullet, 2 = detail).
                """
            } else {
                let list = template.sections.map { "- \"\($0.title)\": \($0.guidance)" }.joined(separator: "\n")
                layoutGuide = """
                Use exactly these sections, with these headings, in this order:
                \(list)
                Each item has "text" and a nesting "level" (0 = main bullet, 1 = sub-bullet, 2 = detail).
                """
            }
            schema = sectionsSchema
        }

        let system = """
        You are an expert note-taker turning a student's reading into study notes with a specific template.

        TEMPLATE: \(template.name)
        \(template.instructions)
        \(layoutGuide)

        Base everything on the page digests provided; do not invent facts. Be concise and student-friendly. \
        Use **bold** for key terms. "title" is a short title for the reading. Respond with JSON only.
        """
        let body = digests.map { item -> String in
            var s = "--- Page \(item.page) ---\nSummary: \(item.digest.summary)"
            if !item.digest.key_points.isEmpty {
                s += "\nKey points:\n" + item.digest.key_points.map { "- \($0)" }.joined(separator: "\n")
            }
            if !item.digest.terms.isEmpty {
                s += "\nTerms:\n" + item.digest.terms.map { "- \($0.term): \($0.definition)" }.joined(separator: "\n")
            }
            return s
        }.joined(separator: "\n\n")
        let user = "Reading: \(title)\n\nPAGE DIGESTS:\n\(body)"
        return ModelRequest(system: system, user: user, schema: schema, numCtx: 16384)
    }

    static let cornellSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "rows": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "cue": ["type": "string"],
                        "notes": ["type": "array", "items": ["type": "string"]],
                    ] as [String: Any],
                    "required": ["cue", "notes"],
                ] as [String: Any],
            ] as [String: Any],
            "summary": ["type": "string"],
        ] as [String: Any],
        "required": ["title", "rows", "summary"],
    ]

    static let sectionsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "sections": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "heading": ["type": "string"],
                        "items": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": ["text": ["type": "string"], "level": ["type": "integer"]],
                                "required": ["text", "level"],
                            ] as [String: Any],
                        ] as [String: Any],
                    ] as [String: Any],
                    "required": ["heading", "items"],
                ] as [String: Any],
            ] as [String: Any],
        ] as [String: Any],
        "required": ["title", "sections"],
    ]
}

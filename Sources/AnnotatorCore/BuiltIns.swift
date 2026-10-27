import Foundation

public enum BuiltIns {
    public static let highlightPresets: [HighlightPreset] = [
        HighlightPreset(
            id: "color-coded-study",
            name: "Color-coded study",
            summary: "Main ideas, definitions, examples and names/dates in four colors.",
            instructions: """
            Highlight the passages a strong student would mark while studying this for a test. \
            Focus on the central ideas of the page, the definitions of terms, the examples or evidence \
            that support them, and important names, dates and numbers.
            """,
            categories: [
                HighlightCategory(id: "main", name: "Main idea", colorHex: "#FFE066",
                                  description: "Thesis statements, central claims, topic sentences, conclusions."),
                HighlightCategory(id: "definition", name: "Definition", colorHex: "#8CE99A",
                                  description: "A term being defined or explained."),
                HighlightCategory(id: "example", name: "Example / evidence", colorHex: "#74C0FC",
                                  description: "Examples, data, experiments, quotations or evidence supporting an idea."),
                HighlightCategory(id: "fact", name: "Name / date / number", colorHex: "#F783AC",
                                  description: "Key people, places, dates, statistics and formulas worth memorizing."),
            ],
            marginStyle: .popup,
            maxPerPage: 10,
            isBuiltIn: true
        ),
        HighlightPreset(
            id: "margin-commentary",
            name: "Margin commentary",
            summary: "Light highlights with short notes in the margin, like an annotated copy.",
            instructions: """
            Annotate like a thoughtful reader writing in the margins. Mark the claims that carry the argument, \
            the evidence behind them, and places that raise a question or connect to something earlier. \
            Every highlight must have a useful margin note: name what the passage is doing (e.g. "thesis", \
            "counterargument", "key evidence"), or ask the question it raises.
            """,
            categories: [
                HighlightCategory(id: "claim", name: "Claim", colorHex: "#FFD43B",
                                  description: "The argument or main point being made."),
                HighlightCategory(id: "evidence", name: "Evidence", colorHex: "#74C0FC",
                                  description: "Support for a claim: data, examples, sources."),
                HighlightCategory(id: "question", name: "Question / connection", colorHex: "#B197FC",
                                  description: "Something confusing, debatable, or linked to another part of the reading."),
            ],
            marginStyle: .margin,
            maxPerPage: 6,
            isBuiltIn: true
        ),
        HighlightPreset(
            id: "literary-analysis",
            name: "Literary analysis",
            summary: "Themes, symbols, literary devices and tone for English and history readings.",
            instructions: """
            Read this like an English or history student preparing for an analytical essay. Mark passages that \
            develop themes, use symbolism or imagery, employ literary or rhetorical devices, or reveal tone, \
            character or the author's purpose. Margin notes should name the theme/device and briefly say why it matters.
            """,
            categories: [
                HighlightCategory(id: "theme", name: "Theme", colorHex: "#B197FC",
                                  description: "Develops a central theme, message or idea of the work."),
                HighlightCategory(id: "symbol", name: "Symbol / imagery", colorHex: "#63E6BE",
                                  description: "Symbolism, motifs, vivid imagery."),
                HighlightCategory(id: "device", name: "Literary device", colorHex: "#F783AC",
                                  description: "Metaphor, irony, foreshadowing, allusion, rhetorical appeals, etc."),
                HighlightCategory(id: "tone", name: "Tone / character", colorHex: "#FFA94D",
                                  description: "Reveals tone, mood, voice, characterization or the author's purpose."),
            ],
            marginStyle: .margin,
            maxPerPage: 7,
            isBuiltIn: true
        ),
    ]

    public static let noteTemplates: [NoteTemplate] = [
        NoteTemplate(
            id: "cornell",
            name: "Cornell notes",
            summary: "Cue questions on the left, notes on the right, summary at the bottom.",
            instructions: """
            Write Cornell notes. Each cue should be a question or keyword a student can cover the notes with \
            and quiz themselves on. Notes answer the cue in short bullet points.
            """,
            layout: .cornell,
            sections: [],
            isBuiltIn: true
        ),
        NoteTemplate(
            id: "outline",
            name: "Outline",
            summary: "Hierarchical bullets that follow the structure of the reading.",
            instructions: """
            Write a hierarchical outline of the reading. Top-level bullets are major ideas; nested bullets \
            (level 1, 2) hold supporting details, examples and evidence. Keep bullets short.
            """,
            layout: .sections,
            sections: [],
            isBuiltIn: true
        ),
        NoteTemplate(
            id: "key-terms",
            name: "Key terms + summary",
            summary: "Vocabulary with definitions, a short summary and main takeaways.",
            instructions: "Focus on vocabulary and the big picture.",
            layout: .sections,
            sections: [
                NoteSectionSpec(title: "Key Terms",
                                guidance: "Each item is \"**Term** — definition in plain words\". Include every important term."),
                NoteSectionSpec(title: "Summary",
                                guidance: "One item: a 4–6 sentence paragraph summarizing the whole reading."),
                NoteSectionSpec(title: "Main Takeaways",
                                guidance: "3–6 items, the most important things to remember."),
            ],
            isBuiltIn: true
        ),
        NoteTemplate(
            id: "study-guide",
            name: "Study guide / Q&A",
            summary: "Likely test questions with answers, plus flashcards.",
            instructions: "Write a study guide a student could use the night before a test.",
            layout: .sections,
            sections: [
                NoteSectionSpec(title: "Practice Questions",
                                guidance: "6–12 items formatted \"**Q:** question **A:** answer\". Mix recall and understanding questions."),
                NoteSectionSpec(title: "Flashcards",
                                guidance: "Items formatted \"**Front** — back\" for terms, people, dates and concepts."),
                NoteSectionSpec(title: "Summary",
                                guidance: "One item: a short paragraph tying the reading together."),
            ],
            isBuiltIn: true
        ),
    ]
}

import Foundation
import PDFKit
import Testing
@testable import AnnotatorCore

struct NotesTests {
    let cornell = CornellNotes(
        title: "Cell Biology",
        rows: [
            .init(cue: "What does the mitochondria do?", notes: ["Produces **ATP**", "Site of respiration"]),
            .init(cue: "What is a ribosome?", notes: ["Builds proteins"]),
        ],
        summary: "Cells contain organelles with distinct jobs."
    )

    @Test func cornellMarkdownRoundTrips() {
        let md = NotesFormatter.markdown(cornell)
        let layout = CornellLayout(markdown: md)
        #expect(layout.title == "Cell Biology")
        #expect(layout.rows.map(\.cue) == ["What does the mitochondria do?", "What is a ribosome?"])
        #expect(layout.rows[0].notes == [.bullet(level: 0, text: "Produces **ATP**"), .bullet(level: 0, text: "Site of respiration")])
        #expect(layout.summary == [.paragraph("Cells contain organelles with distinct jobs.")])
    }

    @Test func sectionMarkdownNestsBullets() {
        let notes = SectionNotes(title: "Outline", sections: [
            .init(heading: "Causes", items: [.init(text: "Debt", level: 0), .init(text: "From wars", level: 1)]),
        ])
        let blocks = MarkdownParser.parse(NotesFormatter.markdown(notes))
        #expect(blocks == [
            .heading(level: 1, text: "Outline"),
            .heading(level: 2, text: "Causes"),
            .bullet(level: 0, text: "Debt"),
            .bullet(level: 1, text: "From wars"),
        ])
    }

    @Test func parserJoinsParagraphLinesAndKeepsNumberedItems() {
        let blocks = MarkdownParser.parse("First line\nsecond line\n\n1. Step one\n")
        #expect(blocks == [.paragraph("First line second line"), .bullet(level: 0, text: "1. Step one")])
    }

    @Test func inlineRunsSplitBold() {
        let runs = MarkdownParser.inlineRuns("**Term** — meaning")
        #expect(runs.map(\.text) == ["Term", " — meaning"])
        #expect(runs.map(\.bold) == [true, false])
    }

    @Test func notesPDFContainsText() throws {
        for layout in NoteLayout.allCases {
            let data = NotesPDFRenderer.render(markdown: NotesFormatter.markdown(cornell), layout: layout)
            let doc = try #require(PDFDocument(data: data))
            #expect(doc.pageCount >= 1)
            #expect(doc.string?.contains("mitochondria") == true)
        }
    }

    @Test func longNotesPaginate() throws {
        let rows = (1...60).map { CornellNotes.Row(cue: "Question \($0)?", notes: ["Answer line one", "Answer line two"]) }
        let md = NotesFormatter.markdown(CornellNotes(title: "Long", rows: rows, summary: "Done."))
        let doc = try #require(PDFDocument(data: NotesPDFRenderer.render(markdown: md, layout: .cornell)))
        #expect(doc.pageCount > 1)
    }
}

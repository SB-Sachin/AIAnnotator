import AppKit
import Foundation
import PDFKit
import Testing
@testable import AnnotatorCore

@MainActor
struct HighlightPlacementTests {
    let preset = BuiltIns.highlightPresets[1]   // margin commentary: exercises margin notes too

    @Test func placesHighlightsOnDigitalPDF() throws {
        let md = """
        # Chapter 3

        The mitochondria is the powerhouse of the cell because it produces most of the cell's ATP through respiration.

        Ribosomes build proteins by translating messenger RNA into chains of amino acids.
        """
        let doc = try #require(PDFDocument(data: NotesPDFRenderer.render(markdown: md, layout: .sections)))
        let page = try #require(doc.page(at: 0))
        let result = PDFHighlighter.place([
            RawHighlight(quote: "The mitochondria is the powerhouse of the cell", category: "claim", note: "Thesis of the section"),
            RawHighlight(quote: "translating messenger RNA into chains of amino acids", category: "evidence", note: ""),
            RawHighlight(quote: "this sentence is not on the page at all", category: "claim", note: ""),
        ], on: page, preset: preset)

        #expect(result.placed == 2)
        #expect(result.missed.count == 1)
        let highlights = page.annotations.filter(PDFHighlighter.isHighlight)
        #expect(highlights.count == 2)
        #expect(highlights.allSatisfy { ($0.quadrilateralPoints?.count ?? 0) >= 4 })
        // Reading a highlight back gives exactly the quoted words, which is what the annotation list shows.
        #expect(Set(highlights.map(PDFHighlighter.text(of:))) == [
            "The mitochondria is the powerhouse of the cell",
            "translating messenger RNA into chains of amino acids",
        ])
        #expect(page.annotations.contains { ($0.type ?? "").contains("FreeText") || ($0.type ?? "").contains("Text") })

        // Annotations survive a save/reload, so they show up in Preview too.
        let saved = try #require(doc.dataRepresentation())
        let reloaded = try #require(PDFDocument(data: saved))
        #expect(reloaded.page(at: 0)?.annotations.filter(PDFHighlighter.isHighlight).count == 2)
    }

    @Test func ocrsPhotoAndHighlightsIt() throws {
        let image = try #require(renderTextImage("""
        The Treaty of Versailles was signed in 1919.
        It required Germany to accept responsibility for the war.
        """))
        let doc = try #require(PDFDocument(data: try Ingest.ocrPage(image: image)))
        let page = try #require(doc.page(at: 0))
        let text = page.string ?? ""
        #expect(text.contains("Treaty of Versailles"))

        let result = PDFHighlighter.place([RawHighlight(quote: "Treaty of Versailles was signed in 1919", category: "claim", note: "")],
                                          on: page, preset: preset)
        #expect(result.placed == 1)
        #expect(Ingest.pageImage(page) != nil)
    }

    private func renderTextImage(_ text: String) -> CGImage? {
        let size = NSSize(width: 1600, height: 500)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            (text as NSString).draw(in: rect.insetBy(dx: 60, dy: 80),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
            return true
        }
        var r = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &r, context: nil, hints: nil)
    }
}

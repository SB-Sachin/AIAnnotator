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
        let reloadedHighlights = try #require(reloaded.page(at: 0)?.annotations.filter(PDFHighlighter.isHighlight))
        #expect(reloadedHighlights.count == 2)
        // The saved quote survives too, and so does reading it back from the page for highlights without one.
        #expect(reloadedHighlights.map { $0.value(forAnnotationKey: PDFHighlighter.quoteKey) as? String }.contains("The mitochondria is the powerhouse of the cell"))
        for ann in reloadedHighlights { ann.removeValue(forAnnotationKey: PDFHighlighter.quoteKey) }
        #expect(Set(reloadedHighlights.map(PDFHighlighter.text(of:))) == [
            "The mitochondria is the powerhouse of the cell",
            "translating messenger RNA into chains of amino acids",
        ])
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

    /// A tilted phone photo used to give one giant box per paragraph and glue lines together ("townsmade").
    @Test func tiltedPhotoGetsLineSizedHighlights() throws {
        let image = try #require(renderTextImage("""
        The founders of Massachusetts sought to eliminate extremes of rank from their society, yet they were \
        very far from being egalitarian. Most towns deliberately preserved inequalities of status and wealth \
        within a narrow range, and most communities attempted to preserve the system of social ranks which \
        had existed within the small villages of East Anglia.
        """, size: NSSize(width: 1700, height: 1100), degrees: 4))
        let doc = try #require(PDFDocument(data: try Ingest.ocrPage(image: image)))
        let page = try #require(doc.page(at: 0))
        let text = PageSentences.clean(page.string ?? "")
        // Words at line ends stay separate from the next line's first word.
        #expect(text.contains("Most towns deliberately preserved"))
        #expect(text.contains("status and wealth within a narrow range"))

        let result = PDFHighlighter.place([RawHighlight(quote: "deliberately preserved inequalities of status and wealth",
                                                        category: "claim", note: "", sentence: 2, importance: 3)],
                                          on: page, preset: preset)
        #expect(result.placed == 1)
        let ann = try #require(page.annotations.first(where: PDFHighlighter.isHighlight))
        let boxes = PDFHighlighter.lineRects(of: ann)
        let lineHeight = page.bounds(for: .mediaBox).width / 1700 * 46 * 1.25
        #expect(boxes.allSatisfy { $0.height < lineHeight * 1.6 }, "boxes: \(boxes), line ≈ \(lineHeight)")
        #expect(PDFHighlighter.text(of: ann) == "deliberately preserved inequalities of status and wealth")
    }

    private func renderTextImage(_ text: String, size: NSSize = NSSize(width: 1600, height: 500),
                                 degrees: CGFloat = 0) -> CGImage? {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            let t = NSAffineTransform()
            t.translateX(by: rect.midX, yBy: rect.midY)
            t.rotate(byDegrees: degrees)
            t.translateX(by: -rect.midX, yBy: -rect.midY)
            t.concat()
            (text as NSString).draw(in: rect.insetBy(dx: 90, dy: 110),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: degrees == 0 ? 48 : 46),
                                                     .foregroundColor: NSColor.black])
            return true
        }
        var r = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &r, context: nil, hints: nil)
    }
}

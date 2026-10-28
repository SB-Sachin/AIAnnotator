import AppKit
import Foundation
import PDFKit
import Testing
@testable import AnnotatorCore

@MainActor
struct RedoTests {
    let preset = BuiltIns.highlightPresets[1]   // margin commentary: adds margin notes too

    private func page() throws -> (PDFDocument, PDFPage) {
        let md = """
        # Chapter 3

        The mitochondria is the powerhouse of the cell because it produces most of the cell's ATP through respiration.

        Ribosomes build proteins by translating messenger RNA into chains of amino acids.
        """
        let doc = try #require(PDFDocument(data: NotesPDFRenderer.render(markdown: md, layout: .sections)))
        return (doc, try #require(doc.page(at: 0)))
    }

    @Test func redoClearsGeneratedButKeepsReadersHighlights() throws {
        let (_, page) = try page()
        PDFHighlighter.place([RawHighlight(quote: "The mitochondria is the powerhouse of the cell", category: "claim",
                                           note: "Thesis", sentence: nil, importance: 3)], on: page, preset: preset)
        let text = page.string ?? ""
        let mine = try #require(page.selection(for: (text as NSString).range(of: "Ribosomes build proteins")))
        PDFHighlighter.highlight(mine, on: page, color: .systemGreen, contents: "Claim", manual: true)
        // AI highlight, its margin note (plus the popup PDFKit gives a sticky note), and my highlight.
        #expect(page.annotations.filter(PDFHighlighter.isHighlight).count == 2)
        #expect(page.annotations.count >= 3)

        PDFHighlighter.removeGenerated(on: page)
        #expect(page.annotations.count == 1)
        #expect(PDFHighlighter.text(of: page.annotations[0]) == "Ribosomes build proteins")

        // A new AI pass never draws over the reader's highlight.
        let result = PDFHighlighter.place([RawHighlight(quote: "Ribosomes build proteins by translating messenger RNA",
                                                        category: "claim", note: "", sentence: nil, importance: 3)],
                                          on: page, preset: preset)
        #expect(result.placed == 0)
        #expect(result.dropped == 1)
        #expect(page.annotations.filter(PDFHighlighter.isHighlight).count == 1)
    }

    @Test func manualFlagSurvivesSaving() throws {
        let (doc, page) = try page()
        let mine = try #require(page.selection(for: ((page.string ?? "") as NSString).range(of: "Ribosomes build proteins")))
        PDFHighlighter.highlight(mine, on: page, color: .systemGreen, contents: "Claim", manual: true)
        let saved = try #require(doc.dataRepresentation())
        let reloaded = try #require(PDFDocument(data: saved))
        let ann = try #require(reloaded.page(at: 0)?.annotations.first(where: PDFHighlighter.isHighlight))
        #expect(PDFHighlighter.isManual(ann))
    }

    @Test func digestsRoundTripAndOldReadingsStillLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(root: dir)
        let id = UUID()
        // item.json written before photoPages/density existed.
        try FileManager.default.createDirectory(at: store.folder(for: id), withIntermediateDirectories: true)
        try Data("""
        {"createdAt":"2026-10-27T01:07:53Z","hasNotes":false,"id":"\(id.uuidString)","mode":"annotations",
         "model":"gemma3:12b","presetName":"Color-coded study","title":"Old reading"}
        """.utf8).write(to: store.folder(for: id).appendingPathComponent("item.json"))
        let old = try #require(store.list().first)
        #expect(old.photoPages == nil && old.density == nil)

        let digests = [PageDigestEntry(page: 1, digest: PageDigest(summary: "Cells", key_points: ["ATP"], terms: []))]
        try store.saveDigests(digests, for: id)
        #expect(store.loadDigests(for: id) == digests)
        try store.saveDigests([], for: id)
        #expect(store.loadDigests(for: id).isEmpty)
    }

    @Test func rereadsAPhotoPage() throws {
        let size = NSSize(width: 1600, height: 600)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("The Treaty of Versailles was signed in 1919." as NSString)
                .draw(in: rect.insetBy(dx: 80, dy: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 52)])
            return true
        }
        var r = CGRect(origin: .zero, size: size)
        let cg = try #require(image.cgImage(forProposedRect: &r, context: nil, hints: nil))
        let original = try Ingest.ocrPage(image: cg)
        let again = try #require(PDFDocument(data: try Ingest.rereadPhotoPage(original)))
        #expect(again.page(at: 0)?.string?.contains("Treaty of Versailles") == true)
    }
}

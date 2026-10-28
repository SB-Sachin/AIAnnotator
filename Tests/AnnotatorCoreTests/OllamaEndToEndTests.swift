import Foundation
import PDFKit
import Testing
@testable import AnnotatorCore

/// Runs the real pipeline against a local Ollama. Opt in with OLLAMA_E2E=1 (model via OLLAMA_MODEL).
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OLLAMA_E2E"] == "1"))
struct OllamaEndToEndTests {
    let client = OllamaClient()
    let model = ProcessInfo.processInfo.environment["OLLAMA_MODEL"] ?? "gemma3:12b"

    @Test(.timeLimit(.minutes(10))) func highlightsAndNotesFromAPage() async throws {
        let md = """
        # The Cell

        The cell is the basic structural and functional unit of all living organisms. Cell theory states that \
        all living things are made of cells, that the cell is the basic unit of life, and that new cells arise \
        only from existing cells.

        The mitochondria are organelles that produce most of the chemical energy needed to power the cell's \
        biochemical reactions. This energy is stored in a molecule called adenosine triphosphate (ATP).

        In 1665, Robert Hooke observed cork under a microscope and named the small compartments he saw "cells". \
        For example, a single human body contains roughly 37 trillion cells.
        """
        let doc = try #require(PDFDocument(data: NotesPDFRenderer.render(markdown: md, layout: .sections)))
        let page = try #require(doc.page(at: 0))
        let preset = BuiltIns.highlightPresets[0]

        #expect(await client.supportsVision(model: model))
        let req = PromptBuilder.pageRequest(mode: .both, preset: preset, sentences: PageSentences(page.string ?? ""), pageNumber: 1, pageCount: 1)
        let image = try #require(Ingest.pageImage(page))
        let result = try await client.chat(model: model, system: req.system, user: req.user, images: [image],
                                           schema: req.schema, numCtx: req.numCtx, as: PageResult.self)
        let highlights = try #require(result.highlights)
        let placement = PDFHighlighter.place(highlights, on: page, preset: preset, density: .balanced)
        print("Model suggested \(highlights.count) highlights; placed \(placement.placed); dropped \(placement.dropped); missed: \(placement.missed)")
        #expect(placement.placed >= 2)

        let digest = try #require(result.digest)
        let template = BuiltIns.noteTemplates[0]
        let notesReq = PromptBuilder.notesRequest(template: template, title: "The Cell", digests: [(1, digest)])
        let notes = try await client.chat(model: model, system: notesReq.system, user: notesReq.user,
                                          schema: notesReq.schema, numCtx: notesReq.numCtx, as: CornellNotes.self)
        let markdown = NotesFormatter.markdown(notes)
        print(markdown)
        #expect(!notes.rows.isEmpty)
        #expect(CornellLayout(markdown: markdown).rows.count == notes.rows.count)

        let out = FileManager.default.temporaryDirectory.appendingPathComponent("aiannotator-e2e")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        #expect(doc.write(to: out.appendingPathComponent("annotated.pdf")))
        try NotesPDFRenderer.render(markdown: markdown, layout: .cornell).write(to: out.appendingPathComponent("notes.pdf"))
        print("Wrote \(out.path)")
    }

    /// Highlights a real reading. OLLAMA_E2E_PDF is a PDF (with OLLAMA_E2E_PAGES, a 1-based list like "30,31")
    /// or a folder of page photos, which go through the same OCR as the app. OLLAMA_E2E_DENSITY=light|balanced|thorough,
    /// OLLAMA_E2E_PRESET=index of the built-in highlight style. Writes $TMPDIR/aiannotator-e2e/real.pdf.
    @Test(.timeLimit(.minutes(20)), .enabled(if: ProcessInfo.processInfo.environment["OLLAMA_E2E_PDF"] != nil))
    func highlightsRealPages() async throws {
        let env = ProcessInfo.processInfo.environment
        let input = URL(fileURLWithPath: env["OLLAMA_E2E_PDF"]!)
        let density = HighlightDensity(rawValue: env["OLLAMA_E2E_DENSITY"] ?? "") ?? .light
        let preset = BuiltIns.highlightPresets[Int(env["OLLAMA_E2E_PRESET"] ?? "") ?? 0]
        let doc: PDFDocument
        var numbers: [Int]
        if input.hasDirectoryPath {
            let photos = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
                .filter(Ingest.isSupported)
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            doc = try #require(PDFDocument(data: try Ingest.makePDFData(from: photos)))
            numbers = Array(1...doc.pageCount)
        } else {
            let source = try #require(PDFDocument(url: input))
            numbers = (env["OLLAMA_E2E_PAGES"] ?? "1").split(separator: ",").compactMap { Int($0) }
            doc = PDFDocument()
            for n in numbers {
                if let page = source.page(at: n - 1)?.copy() as? PDFPage { doc.insert(page, at: doc.pageCount) }
            }
        }
        for i in 0..<doc.pageCount {
            let page = try #require(doc.page(at: i))
            let sentences = PageSentences(page.string ?? "")
            let req = PromptBuilder.pageRequest(mode: .annotations, preset: preset, density: density, sentences: sentences,
                                                pageNumber: i + 1, pageCount: doc.pageCount)
            let images = Ingest.pageImage(page).map { [$0] } ?? []
            let result = try await client.chat(model: model, system: req.system, user: req.user, images: images,
                                               schema: req.schema, numCtx: req.numCtx, as: PageResult.self)
            let raw = result.highlights ?? []
            let placement = PDFHighlighter.place(raw, on: page, preset: preset, density: density, sentences: sentences)
            let words = sentences.wordCount
            let marked = page.annotations.filter(PDFHighlighter.isHighlight).map(PDFHighlighter.text(of:))
            let markedWords = marked.reduce(0) { $0 + $1.split(separator: " ").count }
            print("Page \(numbers[i]): \(words) words, \(sentences.sentences.count) sentences. Model suggested \(raw.count); placed \(placement.placed), dropped \(placement.dropped), missed \(placement.missed.count). Highlighted \(markedWords) words (\(words > 0 ? markedWords * 100 / words : 0)%).")
            print("   text: \(PageSentences.clean(page.string ?? "").prefix(220))…")
            for (m, ann) in zip(marked, page.annotations.filter(PDFHighlighter.isHighlight)) {
                let boxes = PDFHighlighter.lineRects(of: ann)
                print("   • [\(boxes.count) box\(boxes.count == 1 ? "" : "es"), tallest \(Int(boxes.map(\.height).max() ?? 0))pt] \(m)")
            }
            for m in placement.missed { print("   ✗ missed: \(m)") }
            #expect(placement.placed <= density.cap)
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("aiannotator-e2e")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        #expect(doc.write(to: out.appendingPathComponent("real.pdf")))
        print("Wrote \(out.appendingPathComponent("real.pdf").path)")
    }
}

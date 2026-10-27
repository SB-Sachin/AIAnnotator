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
        let req = PromptBuilder.pageRequest(mode: .both, preset: preset, pageText: page.string ?? "", pageNumber: 1, pageCount: 1)
        let image = try #require(Ingest.pageImage(page))
        let result = try await client.chat(model: model, system: req.system, user: req.user, images: [image],
                                           schema: req.schema, numCtx: req.numCtx, as: PageResult.self)
        let highlights = try #require(result.highlights)
        let placement = PDFHighlighter.place(highlights, on: page, preset: preset)
        print("Model suggested \(highlights.count) highlights; placed \(placement.placed); missed: \(placement.missed)")
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
}

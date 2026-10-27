import AnnotatorCore
import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// One open reading: the PDF with its annotations, the notes, and the AI run that fills them in.
@MainActor
final class Session: ObservableObject, Identifiable {
    let id: UUID
    let createdAt: Date
    let model: String
    let mode: RunMode

    @Published var title: String
    @Published var document: PDFDocument?
    @Published var notes: String = "" {
        didSet { if notes != oldValue { dirty = true } }
    }
    @Published var palette: HighlightPreset
    @Published var templateName: String?
    @Published var templateLayout: NoteLayout?

    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var status = ""
    @Published var errorMessage: String?
    @Published var missedHighlights = 0
    @Published var selectedAnnotation: PDFAnnotation?
    @Published var hasTextSelection = false
    @Published var dirty = false

    weak var pdfView: PDFView?
    var onSaved: (() -> Void)?
    private var task: Task<Void, Never>?
    private let store = LibraryStore()

    init(urls: [URL], options: RunOptions) {
        id = UUID()
        createdAt = Date()
        model = options.model
        mode = options.mode
        palette = options.preset
        let first = urls[0].deletingPathExtension().lastPathComponent
        title = urls.count > 1 && urls[0].pathExtension.lowercased() != "pdf" ? "\(first) (+\(urls.count - 1) pages)" : first
        if options.mode.wantsNotes {
            templateName = options.template.name
            templateLayout = options.template.layout
        }
    }

    init(item: ReadingItem, store: LibraryStore, preset: HighlightPreset) {
        id = item.id
        createdAt = item.createdAt
        model = item.model
        mode = item.mode
        title = item.title
        palette = preset
        templateName = item.templateName
        templateLayout = item.templateLayout
        document = PDFDocument(url: store.pdfURL(for: item.id))
        notes = store.loadNotes(for: item.id) ?? ""
    }

    var showsNotes: Bool { mode.wantsNotes || !notes.isEmpty }

    // MARK: Running

    func start(urls: [URL], options: RunOptions, client: OllamaClient) {
        isRunning = true
        status = "Preparing pages…"
        task = Task { [weak self] in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Ingest.makePDFData(from: urls)
                }.value
                guard let self else { return }
                guard let doc = PDFDocument(data: data) else { throw IngestError.unreadable(self.title) }
                self.document = doc
                try await self.process(doc, options: options, client: client)
                self.status = self.missedHighlights > 0
                    ? "Done. \(self.missedHighlights) suggested highlight(s) couldn't be matched to the page text and were skipped."
                    : "Done"
            } catch {
                guard let self else { return }
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.status = "Stopped. Pages finished so far are kept."
                } else {
                    self.errorMessage = error.localizedDescription
                    self.status = ""
                }
            }
            guard let self else { return }
            self.isRunning = false
            self.progress = 1
            if self.document != nil { self.save() }
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func process(_ doc: PDFDocument, options: RunOptions, client: OllamaClient) async throws {
        let count = doc.pageCount
        let steps = Double(count + (options.mode.wantsNotes ? 1 : 0))
        let vision = await client.supportsVision(model: options.model)
        var digests: [(page: Int, digest: PageDigest)] = []

        for i in 0..<count {
            try Task.checkCancellation()
            guard let page = doc.page(at: i) else { continue }
            status = "Reading page \(i + 1) of \(count)…"
            progress = Double(i) / steps
            let text = page.string ?? ""
            if !options.mode.wantsNotes && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

            let req = PromptBuilder.pageRequest(mode: options.mode, preset: options.preset, pageText: text,
                                                pageNumber: i + 1, pageCount: count)
            let images = vision ? Ingest.pageImage(page).map { [$0] } ?? [] : []
            let result = try await client.chat(model: options.model, system: req.system, user: req.user,
                                               images: images, schema: req.schema, numCtx: req.numCtx,
                                               as: PageResult.self)
            if options.mode.wantsHighlights, let highlights = result.highlights {
                let placement = PDFHighlighter.place(highlights, on: page, preset: options.preset)
                missedHighlights += placement.missed.count
                pdfView?.annotationsChanged(on: page)
            }
            if let digest = result.digest { digests.append((i + 1, digest)) }
        }

        guard options.mode.wantsNotes else { return }
        try Task.checkCancellation()
        status = "Writing \(options.template.name)…"
        progress = Double(count) / steps
        let req = PromptBuilder.notesRequest(template: options.template, title: title, digests: digests)
        switch options.template.layout {
        case .cornell:
            let n = try await client.chat(model: options.model, system: req.system, user: req.user,
                                          schema: req.schema, numCtx: req.numCtx, as: CornellNotes.self)
            notes = NotesFormatter.markdown(n)
        case .sections:
            let n = try await client.chat(model: options.model, system: req.system, user: req.user,
                                          schema: req.schema, numCtx: req.numCtx, as: SectionNotes.self)
            notes = NotesFormatter.markdown(n)
        }
    }

    // MARK: Saving

    func save() {
        guard let document else { return }
        let item = ReadingItem(id: id, title: title, createdAt: createdAt, mode: mode, model: model,
                               presetName: palette.name, templateName: templateName,
                               templateLayout: templateLayout, hasNotes: !notes.isEmpty)
        do {
            try store.save(item, pdfData: document.dataRepresentation(), notes: notes.isEmpty ? nil : notes)
            dirty = false
            onSaved?()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    // MARK: Editing highlights

    func highlightSelection(as category: HighlightCategory) {
        guard let selection = pdfView?.currentSelection else { return }
        for page in selection.pages {
            PDFHighlighter.highlight(selection, on: page, color: category.color, contents: category.name)
            pdfView?.annotationsChanged(on: page)
        }
        pdfView?.clearSelection()
        hasTextSelection = false
        dirty = true
    }

    func recolorSelected(_ category: HighlightCategory) {
        guard let ann = selectedAnnotation else { return }
        let type = (ann.type ?? "").replacingOccurrences(of: "/", with: "")
        let alpha: CGFloat = type == "Highlight" ? PDFHighlighter.highlightAlpha : type == "FreeText" ? 0.22 : 1
        ann.color = category.color.withAlphaComponent(alpha)
        if type == "Highlight" {
            let note = ann.contents?.split(separator: ":", maxSplits: 1).dropFirst().first
            ann.contents = note.map { "\(category.name):\($0)" } ?? category.name
        }
        refresh(ann)
    }

    func setSelectedNote(_ text: String) {
        guard let ann = selectedAnnotation, ann.contents != text else { return }
        ann.contents = text
        refresh(ann)
    }

    func deleteSelected() {
        guard let ann = selectedAnnotation, let page = ann.page else { return }
        page.removeAnnotation(ann)
        selectedAnnotation = nil
        pdfView?.annotationsChanged(on: page)
        dirty = true
    }

    private func refresh(_ ann: PDFAnnotation) {
        if let page = ann.page { pdfView?.annotationsChanged(on: page) }
        objectWillChange.send()
        dirty = true
    }

    // MARK: Export

    func exportAnnotatedPDF() {
        guard let document else { return }
        guard let url = savePanel(name: "\(title) (annotated).pdf", type: .pdf) else { return }
        if !document.write(to: url) { errorMessage = "Couldn't write \(url.lastPathComponent)." }
    }

    func exportNotesMarkdown() {
        let type = UTType(filenameExtension: "md") ?? .plainText
        guard let url = savePanel(name: "\(title) notes.md", type: type) else { return }
        do { try notes.write(to: url, atomically: true, encoding: .utf8) } catch { errorMessage = error.localizedDescription }
    }

    func exportNotesPDF() {
        guard let url = savePanel(name: "\(title) notes.pdf", type: .pdf) else { return }
        let data = NotesPDFRenderer.render(markdown: notes, layout: templateLayout ?? .sections)
        do { try data.write(to: url) } catch { errorMessage = error.localizedDescription }
    }

    private func savePanel(name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

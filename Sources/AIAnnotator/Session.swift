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
    @Published private(set) var entries: [AnnotationEntry] = []
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
        dirty = false
        annotationsChanged(markDirty: false)
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
                let count = self.entries.count
                self.status = options.mode.wantsHighlights
                    ? "Done · \(count) highlight\(count == 1 ? "" : "s") on \(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s")"
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

            let sentences = PageSentences(text)
            let req = PromptBuilder.pageRequest(mode: options.mode, preset: options.preset, density: options.density,
                                                sentences: sentences, pageNumber: i + 1, pageCount: count)
            let images = vision ? Ingest.pageImage(page).map { [$0] } ?? [] : []
            let result = try await client.chat(model: options.model, system: req.system, user: req.user,
                                               images: images, schema: req.schema, numCtx: req.numCtx,
                                               as: PageResult.self)
            if options.mode.wantsHighlights, let highlights = result.highlights {
                let placement = PDFHighlighter.place(highlights, on: page, preset: options.preset,
                                                     density: options.density, sentences: sentences)
                missedHighlights += placement.missed.count
                pdfView?.annotationsChanged(on: page)
                annotationsChanged(markDirty: false)
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

    func annotationsChanged(markDirty: Bool = true) {
        if let document { entries = AnnotationIndex.entries(in: document, palette: palette) }
        if markDirty { dirty = true }
    }

    func highlightSelection(as category: HighlightCategory) {
        guard let selection = pdfView?.currentSelection else { return }
        var added: PDFAnnotation?
        for page in selection.pages {
            added = PDFHighlighter.highlight(selection, on: page, color: category.color, contents: category.name) ?? added
            pdfView?.annotationsChanged(on: page)
        }
        pdfView?.clearSelection()
        hasTextSelection = false
        annotationsChanged()
        selectedAnnotation = added
    }

    /// Selects a highlight; `reveal` scrolls the page to it and briefly outlines it.
    func select(_ ann: PDFAnnotation?, reveal: Bool = false) {
        selectedAnnotation = ann
        guard reveal, let ann, let page = ann.page, let view = pdfView else { return }
        view.go(to: ann.bounds.insetBy(dx: -60, dy: -120), on: page)
        let flash = PDFAnnotation(bounds: ann.bounds.insetBy(dx: -3, dy: -3), forType: .square, withProperties: nil)
        flash.color = NSColor(hex: 0x5B4BD6)
        let border = PDFBorder()
        border.lineWidth = 2
        flash.border = border
        page.addAnnotation(flash)
        Task { @MainActor [weak view] in
            try? await Task.sleep(for: .milliseconds(1100))
            page.removeAnnotation(flash)
            view?.annotationsChanged(on: page)
        }
    }

    func recolor(_ ann: PDFAnnotation, as category: HighlightCategory) {
        let type = (ann.type ?? "").replacingOccurrences(of: "/", with: "")
        let alpha: CGFloat = type == "Highlight" ? PDFHighlighter.highlightAlpha : type == "FreeText" ? 0.22 : 1
        let note = AnnotationIndex.split(ann.contents).note
        ann.color = category.color.withAlphaComponent(alpha)
        if type == "Highlight" {
            ann.contents = note.isEmpty ? category.name : "\(category.name): \(note)"
            for margin in marginNotes(of: ann, note: note) { margin.color = category.color.withAlphaComponent(0.22) }
        }
        refresh(ann)
    }

    /// Changes a highlight's note, keeping its visible margin note in step.
    func setNote(_ text: String, for ann: PDFAnnotation) {
        let (label, old) = AnnotationIndex.split(ann.contents)
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note != old else { return }
        for margin in marginNotes(of: ann, note: old) {
            if note.isEmpty { margin.page?.removeAnnotation(margin) } else { margin.contents = note }
        }
        ann.contents = note.isEmpty ? label : "\(label): \(note)"
        refresh(ann)
    }

    func delete(_ ann: PDFAnnotation) {
        guard let page = ann.page else { return }
        PDFHighlighter.remove(ann)
        if selectedAnnotation === ann { selectedAnnotation = nil }
        pdfView?.annotationsChanged(on: page)
        annotationsChanged()
    }

    private func marginNotes(of ann: PDFAnnotation, note: String) -> [PDFAnnotation] {
        guard !note.isEmpty, let page = ann.page else { return [] }
        return page.annotations.filter { !PDFHighlighter.isHighlight($0) && $0.userName == PDFHighlighter.author && $0.contents == note }
    }

    private func refresh(_ ann: PDFAnnotation) {
        if let page = ann.page { pdfView?.annotationsChanged(on: page) }
        annotationsChanged()
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

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
    @Published private(set) var model: String
    @Published private(set) var mode: RunMode

    @Published var title: String
    @Published var document: PDFDocument?
    @Published var notes: String = "" {
        didSet { if notes != oldValue { dirty = true } }
    }
    @Published var palette: HighlightPreset
    @Published var templateName: String?
    @Published var templateLayout: NoteLayout?
    @Published private(set) var density: HighlightDensity
    /// 0-based photo pages; nil for readings saved before this was recorded.
    private(set) var photoPages: [Int]?
    private var digests: [PageDigestEntry] = []
    /// The state before the last redo, so it can be undone.
    @Published private(set) var beforeRedo: Snapshot?

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

    struct Snapshot {
        var pdf: Data
        var notes: String
        var mode: RunMode
        var model: String
        var palette: HighlightPreset
        var density: HighlightDensity
        var templateName: String?
        var templateLayout: NoteLayout?
        var digests: [PageDigestEntry]
    }

    /// One pass over the reading: highlights, notes, or both.
    struct Job {
        var highlights: Bool
        var notes: Bool
        var options: RunOptions
        /// Run photo pages through OCR again first (fixes readings imported before the photo fix).
        var rereadPhotos = false
    }

    init(urls: [URL], options: RunOptions) {
        id = UUID()
        createdAt = Date()
        model = options.model
        mode = options.mode
        palette = options.preset
        density = options.density
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
        density = item.density ?? .balanced
        photoPages = item.photoPages
        templateName = item.templateName
        templateLayout = item.templateLayout
        document = PDFDocument(url: store.pdfURL(for: item.id))
        notes = store.loadNotes(for: item.id) ?? ""
        digests = store.loadDigests(for: item.id)
        dirty = false
        annotationsChanged(markDirty: false)
    }

    var showsNotes: Bool { mode.wantsNotes || !notes.isEmpty }
    /// Notes can be rewritten from saved page digests without reading every page again.
    var hasSavedDigests: Bool { !digests.isEmpty && digests.count == document?.pageCount }

    // MARK: Running

    func start(urls: [URL], options: RunOptions, client: OllamaClient) {
        run("Preparing pages…") { [weak self] in
            let (data, photos) = try await Task.detached(priority: .userInitiated) {
                try Ingest.makePDF(from: urls)
            }.value
            guard let self else { return }
            guard let doc = PDFDocument(data: data) else { throw IngestError.unreadable(self.title) }
            self.document = doc
            self.photoPages = photos
            try await self.perform(Job(highlights: options.mode.wantsHighlights, notes: options.mode.wantsNotes,
                                       options: options), client: client)
        }
    }

    /// Redoes the highlights or the notes with new options. The previous version can be restored with `undoRedo()`.
    func redo(_ job: Job, client: OllamaClient) {
        guard let document, let pdf = document.dataRepresentation() else { return }
        beforeRedo = Snapshot(pdf: pdf, notes: notes, mode: mode, model: model, palette: palette, density: density,
                              templateName: templateName, templateLayout: templateLayout, digests: digests)
        selectedAnnotation = nil
        run(job.highlights ? "Redoing highlights…" : "Redoing notes…") { [weak self] in
            try await self?.perform(job, client: client)
        }
    }

    func undoRedo() {
        guard let s = beforeRedo, !isRunning else { return }
        document = PDFDocument(data: s.pdf)
        notes = s.notes
        mode = s.mode
        model = s.model
        palette = s.palette
        density = s.density
        templateName = s.templateName
        templateLayout = s.templateLayout
        digests = s.digests
        beforeRedo = nil
        selectedAnnotation = nil
        status = "Restored the previous version"
        annotationsChanged()
        save()
    }

    private func run(_ startStatus: String, _ body: @escaping @MainActor () async throws -> Void) {
        isRunning = true
        errorMessage = nil
        progress = 0
        missedHighlights = 0
        status = startStatus
        task = Task { [weak self] in
            do {
                try await body()
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

    private func perform(_ job: Job, client: OllamaClient) async throws {
        guard let doc = document else { return }
        let options = job.options
        model = options.model
        if job.highlights {
            palette = options.preset
            density = options.density
            mode = mode.wantsNotes || job.notes ? .both : .annotations
        }
        if job.notes {
            templateName = options.template.name
            templateLayout = options.template.layout
            mode = mode.wantsHighlights || job.highlights ? .both : .notes
        }

        let count = doc.pageCount
        // Notes are written from page digests; reuse saved ones unless every page is being read anyway.
        let needsDigests = job.notes && (job.highlights || digests.count != count)
        if needsDigests { digests = [] }
        let readsPages = job.highlights || needsDigests
        let steps = Double((readsPages ? count : 0) + (job.notes ? 1 : 0))
        let vision = readsPages ? await client.supportsVision(model: options.model) : false

        if readsPages {
            for i in 0..<count {
                try Task.checkCancellation()
                guard var page = doc.page(at: i) else { continue }
                status = "Reading page \(i + 1) of \(count)…"
                progress = Double(i) / steps

                if job.rereadPhotos, photoPages?.contains(i) ?? true, let fresh = try await reread(page) {
                    doc.removePage(at: i)
                    doc.insert(fresh, at: i)
                    page = fresh
                    pdfView?.layoutDocumentView()
                }
                if job.highlights {
                    PDFHighlighter.removeGenerated(on: page)
                    pdfView?.annotationsChanged(on: page)
                }

                let text = page.string ?? ""
                if !needsDigests && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let sentences = PageSentences(text)
                let pageMode: RunMode = job.highlights && needsDigests ? .both : job.highlights ? .annotations : .notes
                let req = PromptBuilder.pageRequest(mode: pageMode, preset: options.preset, density: options.density,
                                                    sentences: sentences, pageNumber: i + 1, pageCount: count)
                let images = vision ? Ingest.pageImage(page).map { [$0] } ?? [] : []
                let result = try await client.chat(model: options.model, system: req.system, user: req.user,
                                                   images: images, schema: req.schema, numCtx: req.numCtx,
                                                   as: PageResult.self)
                if job.highlights, let highlights = result.highlights {
                    let placement = PDFHighlighter.place(highlights, on: page, preset: options.preset,
                                                         density: options.density, sentences: sentences)
                    missedHighlights += placement.missed.count
                    pdfView?.annotationsChanged(on: page)
                }
                if let digest = result.digest { digests.append(PageDigestEntry(page: i + 1, digest: digest)) }
                annotationsChanged(markDirty: false)
            }
        }

        if job.notes {
            try Task.checkCancellation()
            status = "Writing \(options.template.name)…"
            progress = readsPages ? Double(count) / steps : 0.5
            let req = PromptBuilder.notesRequest(template: options.template, title: title,
                                                 digests: digests.map { ($0.page, $0.digest) })
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

        annotationsChanged(markDirty: false)
        let highlightCount = entries.count
        status = job.highlights
            ? "Done · \(highlightCount) highlight\(highlightCount == 1 ? "" : "s") on \(count) page\(count == 1 ? "" : "s")"
            : "Notes ready"
    }

    /// OCRs a photo page again off the main thread.
    private func reread(_ page: PDFPage) async throws -> PDFPage? {
        let single = PDFDocument()
        guard let copy = page.copy() as? PDFPage else { return nil }
        single.insert(copy, at: 0)
        guard let data = single.dataRepresentation() else { return nil }
        let fresh = try await Task.detached(priority: .userInitiated) { try Ingest.rereadPhotoPage(data) }.value
        return PDFDocument(data: fresh)?.page(at: 0)
    }

    // MARK: Saving

    func save() {
        guard let document else { return }
        let item = ReadingItem(id: id, title: title, createdAt: createdAt, mode: mode, model: model,
                               presetName: palette.name, templateName: templateName,
                               templateLayout: templateLayout, hasNotes: !notes.isEmpty,
                               photoPages: photoPages, density: density)
        do {
            try store.save(item, pdfData: document.dataRepresentation(), notes: notes.isEmpty ? nil : notes)
            try store.saveDigests(digests, for: id)
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
            added = PDFHighlighter.highlight(selection, on: page, color: category.color, contents: category.name,
                                             manual: true) ?? added
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

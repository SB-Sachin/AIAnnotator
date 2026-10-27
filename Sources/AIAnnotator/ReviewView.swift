import AnnotatorCore
import PDFKit
import SwiftUI

struct ReviewView: View {
    @ObservedObject var session: Session

    var body: some View {
        VStack(spacing: 0) {
            if session.isRunning || !session.status.isEmpty || session.errorMessage != nil {
                ProgressStrip(session: session)
                Divider()
            }
            HSplitView {
                VStack(spacing: 0) {
                    HighlightBar(session: session)
                    Divider()
                    if session.document != nil {
                        PDFKitView(session: session)
                    } else {
                        ProgressView("Preparing pages…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 440, maxWidth: .infinity)

                if session.showsNotes {
                    NotesPane(session: session)
                        .frame(minWidth: 320, idealWidth: 420, maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(session.title)
        .toolbar {
            ToolbarItemGroup {
                Button { session.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .disabled(session.isRunning || !session.dirty)
                    .help("Save changes to the library (⌘S)")
                Menu {
                    Button("Annotated PDF…") { session.exportAnnotatedPDF() }.disabled(session.document == nil)
                    Button("Notes as Markdown…") { session.exportNotesMarkdown() }.disabled(session.notes.isEmpty)
                    Button("Notes as PDF…") { session.exportNotesPDF() }.disabled(session.notes.isEmpty)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(session.isRunning)
            }
        }
    }
}

struct ProgressStrip: View {
    @ObservedObject var session: Session

    var body: some View {
        HStack(spacing: 12) {
            if let error = session.errorMessage {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text(error).textSelection(.enabled)
                Spacer()
                Button("Dismiss") { session.errorMessage = nil }
            } else if session.isRunning {
                ProgressView(value: session.progress).frame(width: 180)
                Text(session.status).foregroundStyle(.secondary)
                Spacer()
                Button("Stop") { session.cancel() }
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(session.status).foregroundStyle(.secondary)
                Spacer()
                Button("Dismiss") { session.status = "" }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// Legend / manual highlight / selected-highlight editor above the PDF.
struct HighlightBar: View {
    @ObservedObject var session: Session
    @ViewState private var noteDraft = ""

    var body: some View {
        HStack(spacing: 10) {
            if let ann = session.selectedAnnotation {
                Text("Selected").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Legend(categories: session.palette.categories) { session.recolorSelected($0) }
                TextField("Note", text: $noteDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { session.setSelectedNote(noteDraft) }
                    .onChange(of: noteDraft) { _, v in session.setSelectedNote(v) }
                Button(role: .destructive) { session.deleteSelected() } label: { Image(systemName: "trash") }
                    .help("Delete this highlight")
                Button { session.selectedAnnotation = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .onAppear { noteDraft = ann.contents ?? "" }
                    .onChange(of: session.selectedAnnotation) { _, a in noteDraft = a?.contents ?? "" }
            } else if session.hasTextSelection {
                Text("Highlight as").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Legend(categories: session.palette.categories) { session.highlightSelection(as: $0) }
                Spacer()
            } else {
                Legend(categories: session.palette.categories)
                Spacer()
                Text("Select text to highlight · click a highlight to edit")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(minHeight: 38)
    }
}

final class AnnotatingPDFView: PDFView {
    var onSelectAnnotation: ((PDFAnnotation?) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let page = page(for: point, nearest: false) {
            let pagePoint = convert(point, to: page)
            if let ann = page.annotations.last(where: { PDFHighlighter.isEditable($0) && $0.bounds.contains(pagePoint) }) {
                onSelectAnnotation?(ann)
                return
            }
        }
        onSelectAnnotation?(nil)
        super.mouseDown(with: event)
    }
}

struct PDFKitView: NSViewRepresentable {
    @ObservedObject var session: Session

    func makeNSView(context: Context) -> AnnotatingPDFView {
        let view = AnnotatingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .underPageBackgroundColor
        view.document = session.document
        session.pdfView = view
        view.onSelectAnnotation = { [weak session] ann in session?.selectedAnnotation = ann }
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .PDFViewSelectionChanged, object: view, queue: .main
        ) { [weak session, weak view] _ in
            MainActor.assumeIsolated {
                let text = view?.currentSelection?.string ?? ""
                session?.hasTextSelection = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        return view
    }

    func updateNSView(_ view: AnnotatingPDFView, context: Context) {
        if view.document !== session.document { view.document = session.document }
    }

    static func dismantleNSView(_ view: AnnotatingPDFView, coordinator: Coordinator) {
        if let o = coordinator.observer { NotificationCenter.default.removeObserver(o) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var observer: NSObjectProtocol?
    }
}

struct NotesPane: View {
    @ObservedObject var session: Session
    @ViewState private var editing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.templateName ?? "Notes").font(.headline)
                Spacer()
                Picker("", selection: $editing) {
                    Text("Preview").tag(false)
                    Text("Edit").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(session.notes.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(minHeight: 38)
            Divider()
            if session.notes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "note.text").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(session.isRunning ? "Notes are written after every page has been read." : "No notes for this reading.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if editing {
                TextEditor(text: $session.notes)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            } else {
                ScrollView {
                    NotesPreview(markdown: session.notes, cornell: session.templateLayout == .cornell)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct NotesPreview: View {
    let markdown: String
    let cornell: Bool

    var body: some View {
        if cornell {
            cornellView(CornellLayout(markdown: markdown))
        } else {
            blocks(MarkdownParser.parse(markdown))
        }
    }

    private func cornellView(_ c: CornellLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(c.title).font(.title2.weight(.bold)).padding(.bottom, 10)
            ForEach(Array(c.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    inline(row.cue).font(.callout.weight(.semibold))
                        .frame(width: 130, alignment: .leading)
                    Divider()
                    blocks(row.notes)
                }
                .padding(.vertical, 8)
                Divider()
            }
            if !c.summary.isEmpty {
                Text("Summary").font(.headline).foregroundStyle(Color.accentColor).padding(.top, 14).padding(.bottom, 4)
                blocks(c.summary)
            }
        }
    }

    private func blocks(_ list: [MarkdownBlock]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    inline(text)
                        .font(level == 1 ? .title2.weight(.bold) : level == 2 ? .title3.weight(.semibold) : .headline)
                        .padding(.top, level == 1 ? 0 : 8)
                case .bullet(let level, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if text.first?.isNumber != true { Text(level == 0 ? "•" : "◦").foregroundStyle(.secondary) }
                        inline(text)
                    }
                    .padding(.leading, CGFloat(level) * 16)
                case .paragraph(let text):
                    inline(text)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ text: String) -> Text {
        let attributed = (try? AttributedString(markdown: text)) ?? AttributedString(text)
        return Text(attributed)
    }
}

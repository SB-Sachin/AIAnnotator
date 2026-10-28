import AnnotatorCore
import PDFKit
import SwiftUI

struct ReviewView: View {
    @ObservedObject var session: Session

    private var showsHighlights: Bool { session.mode.wantsHighlights || !session.entries.isEmpty }
    private var showsInspector: Bool { showsHighlights || session.showsNotes }

    var body: some View {
        VStack(spacing: 0) {
            ReviewHeader(session: session)
            Divider().opacity(0.6)
            HSplitView {
                ZStack {
                    if session.document != nil {
                        PDFKitView(session: session)
                    } else {
                        VStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Preparing pages…").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: Theme.pdfBackground))
                    }
                    VStack {
                        StatusPill(session: session).padding(.top, 14)
                        Spacer()
                        if session.hasTextSelection {
                            SelectionBar(session: session)
                                .padding(.bottom, 18)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(duration: 0.3), value: session.hasTextSelection)
                }
                .frame(minWidth: 460, maxWidth: .infinity)

                if showsInspector {
                    Inspector(session: session, showsHighlights: showsHighlights)
                        .frame(minWidth: 330, idealWidth: 390, maxWidth: 560)
                }
            }
        }
    }
}

struct ReviewHeader: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var session: Session

    private var subtitle: String {
        var parts = [session.mode.label]
        if session.mode.wantsHighlights { parts.append(session.palette.name) }
        if let t = session.templateName { parts.append(t) }
        parts.append(session.createdAt.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(Theme.display(17)).lineLimit(1)
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if session.dirty && !session.isRunning {
                Text("Unsaved").font(.caption).foregroundStyle(.tertiary)
            }
            Menu {
                Button(session.entries.isEmpty ? "Add Highlights…" : "Redo Highlights…") { app.requestRedo(highlights: true) }
                Button(session.notes.isEmpty ? "Add Notes…" : "Redo Notes…") { app.requestRedo(highlights: false) }
                if session.beforeRedo != nil {
                    Divider()
                    Button("Undo Last Redo") { session.undoRedo() }
                }
            } label: {
                Label("Redo", systemImage: "arrow.clockwise")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.primary.opacity(0.05), in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(session.isRunning || session.document == nil)
            .help("Redo the highlights or notes with different options")
            Button { session.save() } label: { Label("Save", systemImage: "checkmark") }
                .buttonStyle(SoftButtonStyle())
                .disabled(session.isRunning || !session.dirty)
                .help("Save changes to the library (⌘S)")
            Menu {
                Button("Annotated PDF…") { session.exportAnnotatedPDF() }.disabled(session.document == nil)
                Button("Notes as Markdown…") { session.exportNotesMarkdown() }.disabled(session.notes.isEmpty)
                Button("Notes as PDF…") { session.exportNotesPDF() }.disabled(session.notes.isEmpty)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.brandGradient, in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(session.isRunning)
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(Theme.canvas)
    }
}

/// Floating progress / result capsule over the page.
struct StatusPill: View {
    @ObservedObject var session: Session

    var body: some View {
        Group {
            if let error = session.errorMessage {
                pill {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    Text(error).textSelection(.enabled).lineLimit(2)
                    Button("Dismiss") { session.errorMessage = nil }.buttonStyle(SoftButtonStyle())
                }
            } else if session.isRunning {
                pill {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.brand)
                        .symbolEffect(.pulse, options: .repeating)
                    Text(session.status).monospacedDigit()
                    ProgressView(value: session.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 110)
                    Button("Stop") { session.cancel() }.buttonStyle(SoftButtonStyle())
                }
            } else if !session.status.isEmpty {
                pill {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(session.status)
                    if session.beforeRedo != nil {
                        Button("Undo") { session.undoRedo() }.buttonStyle(SoftButtonStyle())
                    }
                    Button { session.status = "" } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .task(id: session.status) {
                    try? await Task.sleep(for: .seconds(8))
                    if !session.isRunning { session.status = "" }
                }
            }
        }
        .animation(.spring(duration: 0.35), value: session.isRunning)
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
            .frame(minHeight: 36)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Appears while text is selected in the PDF.
struct SelectionBar: View {
    @ObservedObject var session: Session

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "highlighter").foregroundStyle(.secondary)
            Text("Highlight as").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            Legend(categories: session.palette.categories) { session.highlightSelection(as: $0) }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
    }
}

struct Inspector: View {
    enum Tab: Hashable { case highlights, notes }

    @ObservedObject var session: Session
    let showsHighlights: Bool
    @ViewState private var tab: Tab = .highlights

    private var current: Tab { !showsHighlights ? .notes : !session.showsNotes ? .highlights : tab }

    var body: some View {
        VStack(spacing: 0) {
            if showsHighlights && session.showsNotes {
                PillPicker(options: [(Tab.highlights, "Highlights · \(session.entries.count)"), (Tab.notes, "Notes")],
                           selection: $tab)
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            }
            switch current {
            case .highlights: HighlightsList(session: session)
            case .notes: NotesPane(session: session)
            }
        }
        .background(Theme.canvas)
        .onChange(of: session.selectedAnnotation) { _, ann in
            if ann != nil { tab = .highlights }
        }
        .onChange(of: session.templateName) { _, name in
            // Rewriting the notes (a redo or an undo) shows them.
            if name != nil { tab = .notes }
        }
    }
}

/// Every highlight at a glance, grouped by page, with filters and inline editing.
struct HighlightsList: View {
    @ObservedObject var session: Session
    @ViewState private var hidden: Set<String> = []

    private var visible: [AnnotationEntry] { session.entries.filter { !hidden.contains($0.label) } }

    var body: some View {
        let entries = session.entries
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(entries.count) highlight\(entries.count == 1 ? "" : "s")").font(Theme.display(15))
                        Text("on \(Set(entries.map(\.pageIndex)).count) of \(session.document?.pageCount ?? 0) pages")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    filters
                }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                            ForEach(groups, id: \.page) { group in
                                Section {
                                    ForEach(group.items) { entry in
                                        AnnotationCard(entry: entry, palette: session.palette,
                                                       selected: session.selectedAnnotation === entry.annotation,
                                                       session: session)
                                            .id(entry.id)
                                    }
                                } header: {
                                    Text("Page \(group.page + 1)")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Theme.canvas)
                                }
                            }
                        }
                        .padding(.horizontal, 14).padding(.bottom, 16)
                    }
                    .onChange(of: session.selectedAnnotation) { _, ann in
                        guard let ann else { return }
                        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(ObjectIdentifier(ann), anchor: .center) }
                    }
                }
            }
        }
    }

    private var groups: [(page: Int, items: [AnnotationEntry])] {
        Dictionary(grouping: visible, by: \.pageIndex).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private var filters: some View {
        let counts = Dictionary(grouping: session.entries, by: \.label).mapValues(\.count)
        let labels = session.palette.categories.map(\.name).filter { counts[$0] != nil }
            + counts.keys.filter { k in !session.palette.categories.contains { $0.name == k } }.sorted()
        return FlowLayout(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    let on = !hidden.contains(label)
                    let color = session.entries.first { $0.label == label }?.color ?? .systemYellow
                    Button {
                        if on { hidden.insert(label) } else { hidden.remove(label) }
                    } label: {
                        HStack(spacing: 5) {
                            CategoryDot(color: color)
                            Text(label.isEmpty ? "Other" : label)
                            Text("\(counts[label] ?? 0)").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(on ? Color(nsColor: color).opacity(0.2) : Color.primary.opacity(0.04), in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Color(nsColor: color).opacity(0.55) : Theme.hairline))
                        .opacity(on ? 1 : 0.55)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(on ? "Hide \(label)" : "Show \(label)")
                }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "highlighter").font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(session.isRunning ? "Highlights appear here as each page is read." : "No highlights yet")
                .font(.system(size: 13, weight: .medium, design: .rounded))
            Text("Select text on the page to add your own.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AnnotationCard: View {
    let entry: AnnotationEntry
    let palette: HighlightPreset
    let selected: Bool
    @ObservedObject var session: Session
    @ViewState private var draft = ""
    @ViewState private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: entry.color)).frame(width: 4)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(entry.label.isEmpty ? "Highlight" : entry.label)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .tracking(0.3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if hover || selected {
                        Button { session.delete(entry.annotation) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete highlight")
                    }
                }
                Text(entry.quote.isEmpty ? "—" : "\u{201C}\(entry.quote)\u{201D}")
                    .font(.system(size: 13))
                    .lineLimit(selected ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                if selected {
                    editor
                } else if !entry.note.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "text.bubble").font(.system(size: 10.5)).padding(.top, 2)
                        Text(entry.note).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 10)
        }
        .padding(12)
        .card(12, shadow: selected || hover)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.brand, lineWidth: selected ? 1.5 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { session.select(entry.annotation, reveal: true) }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Add a note", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(1...4)
                .padding(8)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onAppear { draft = entry.note }
                .onSubmit { session.setNote(draft, for: entry.annotation) }
                .onChange(of: draft) { _, v in session.setNote(v, for: entry.annotation) }
            HStack(spacing: 6) {
                ForEach(palette.categories) { c in
                    Button { session.recolor(entry.annotation, as: c) } label: {
                        Circle().fill(Color(nsColor: c.color)).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.primary.opacity(c.name == entry.label ? 0.7 : 0.1),
                                                           lineWidth: c.name == entry.label ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .help(c.name)
                }
                Spacer()
                Text("Page \(entry.pageIndex + 1)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

final class AnnotatingPDFView: PDFView {
    var onSelectAnnotation: ((PDFAnnotation?) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let page = page(for: point, nearest: false) {
            let pagePoint = convert(point, to: page)
            let highlights = page.annotations.filter(PDFHighlighter.isHighlight)
            if let ann = highlights.last(where: { PDFHighlighter.lineRects(of: $0).contains { $0.contains(pagePoint) } }) {
                onSelectAnnotation?(ann)
                return
            }
            if let margin = page.annotations.last(where: { !PDFHighlighter.isHighlight($0) && PDFHighlighter.isEditable($0) && $0.bounds.contains(pagePoint) }),
               let ann = highlights.first(where: { AnnotationIndex.split($0.contents).note == margin.contents }) {
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
        view.backgroundColor = Theme.pdfBackground
        view.document = session.document
        session.pdfView = view
        view.onSelectAnnotation = { [weak session] ann in session?.select(ann) }
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
                Text(session.templateName ?? "Notes").font(Theme.display(15))
                Spacer()
                PillPicker(options: [(false, "Preview"), (true, "Edit")], selection: $editing)
                    .frame(width: 150)
                    .disabled(session.notes.isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if session.notes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "note.text").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text(session.isRunning ? "Notes are written after every page has been read." : "No notes for this reading.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if editing {
                TextEditor(text: $session.notes)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .card(12, shadow: false)
                    .padding([.horizontal, .bottom], 14)
            } else {
                ScrollView {
                    NotesPreview(markdown: session.notes, cornell: session.templateLayout == .cornell)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(14)
                        .padding([.horizontal, .bottom], 14)
                }
            }
        }
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
            Text(c.title).font(Theme.display(20, .bold)).padding(.bottom, 10)
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
                Text("Summary").font(Theme.display(14)).foregroundStyle(Theme.brand).padding(.top, 14).padding(.bottom, 4)
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

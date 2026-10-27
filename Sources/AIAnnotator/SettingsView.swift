import AnnotatorCore
import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            HighlightPresetEditor().tabItem { Label("Highlight Styles", systemImage: "highlighter") }
            NoteTemplateEditor().tabItem { Label("Note Templates", systemImage: "list.bullet.rectangle") }
        }
        .frame(width: 780, height: 540)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Form {
            Picker("Default model", selection: $app.defaultModel) {
                ForEach(app.models.isEmpty ? [app.defaultModel] : app.models, id: \.self) { Text($0).tag($0) }
            }
            LabeledContent("Ollama") {
                HStack {
                    switch app.status {
                    case .ok: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .checking: Text("Checking…")
                    case .notRunning: Label("Not running", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                    case .modelMissing(let m): Label("\(m) not installed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Button("Refresh") { Task { await app.refreshOllama() } }
                }
            }
            Text("Vision models such as gemma3 also look at the page image, so they can use diagrams and figures. Text-only models work from the extracted text.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Library") {
                Button("Show in Finder") {
                    try? FileManager.default.createDirectory(at: AppPaths.root, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(AppPaths.root)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
    Binding(get: { Color(nsColor: NSColor(hex: hex.wrappedValue)) },
            set: { hex.wrappedValue = NSColor($0).hexString })
}

struct HighlightPresetEditor: View {
    @EnvironmentObject private var app: AppModel
    @ViewState private var selectedID: String?
    @ViewState private var draft: HighlightPreset?
    @ViewState private var error: String?

    var body: some View {
        HStack(spacing: 0) {
            List(app.highlightPresets, selection: $selectedID) { p in
                Label(p.name, systemImage: p.isBuiltIn ? "lock" : "paintbrush").tag(p.id)
            }
            .frame(width: 210)
            Divider()
            if let binding = Binding($draft) {
                editor(binding)
            } else {
                Text("Select a style").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedID) { _, id in draft = app.highlightPresets.first { $0.id == id } }
        .onAppear { if selectedID == nil { selectedID = app.highlightPresets.first?.id } }
    }

    private func editor(_ p: Binding<HighlightPreset>) -> some View {
        let locked = p.wrappedValue.isBuiltIn
        return VStack(spacing: 0) {
            Form {
                if locked {
                    Text("Built-in styles can't be changed. Duplicate this one to make your own.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("Name", text: p.name)
                TextField("Description", text: p.summary)
                Picker("Comments", selection: p.marginStyle) {
                    ForEach(MarginStyle.allCases) { Text($0.label).tag($0) }
                }
                Stepper("At most \(p.wrappedValue.maxPerPage) highlights per page", value: p.maxPerPage, in: 1...25)
                Section("Instructions for the model") {
                    TextEditor(text: p.instructions).frame(height: 90).font(.callout)
                }
                Section("Colors") {
                    ForEach(p.categories) { $c in
                        HStack {
                            ColorPicker("", selection: colorBinding($c.colorHex), supportsOpacity: false).labelsHidden()
                            TextField("Name", text: $c.name).frame(width: 140)
                            TextField("What to highlight in this color", text: $c.description)
                            Button { p.wrappedValue.categories.removeAll { $0.id == c.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .disabled(p.wrappedValue.categories.count <= 1)
                        }
                    }
                    Button("Add Color") {
                        p.wrappedValue.categories.append(HighlightCategory(
                            id: "new-\(UUID().uuidString.prefix(6))", name: "New", colorHex: "#FFE066", description: ""))
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(locked)
            footer(locked: locked)
        }
    }

    private func footer(locked: Bool) -> some View {
        HStack {
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Spacer()
            Button("Duplicate") {
                guard let d = draft?.duplicated() else { return }
                persist(d)
            }
            if !locked {
                Button("Delete", role: .destructive) {
                    guard let id = draft?.id else { return }
                    app.deletePreset(id)
                    selectedID = app.highlightPresets.first?.id
                }
                Button("Save") { if let d = draft { persist(d) } }.buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    private func persist(_ preset: HighlightPreset) {
        do {
            try app.save(preset)
            error = nil
            selectedID = preset.id
            draft = app.highlightPresets.first { $0.id == preset.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct NoteTemplateEditor: View {
    @EnvironmentObject private var app: AppModel
    @ViewState private var selectedID: String?
    @ViewState private var draft: NoteTemplate?
    @ViewState private var error: String?

    var body: some View {
        HStack(spacing: 0) {
            List(app.noteTemplates, selection: $selectedID) { t in
                Label(t.name, systemImage: t.isBuiltIn ? "lock" : "doc.text").tag(t.id)
            }
            .frame(width: 210)
            Divider()
            if let binding = Binding($draft) {
                editor(binding)
            } else {
                Text("Select a template").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedID) { _, id in draft = app.noteTemplates.first { $0.id == id } }
        .onAppear { if selectedID == nil { selectedID = app.noteTemplates.first?.id } }
    }

    private func editor(_ t: Binding<NoteTemplate>) -> some View {
        let locked = t.wrappedValue.isBuiltIn
        return VStack(spacing: 0) {
            Form {
                if locked {
                    Text("Built-in templates can't be changed. Duplicate this one to make your own.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("Name", text: t.name)
                TextField("Description", text: t.summary)
                Picker("Layout", selection: t.layout) {
                    ForEach(NoteLayout.allCases) { Text($0.label).tag($0) }
                }
                Section("Instructions for the model") {
                    TextEditor(text: t.instructions).frame(height: 80).font(.callout)
                }
                if t.wrappedValue.layout == .sections {
                    Section {
                        ForEach(t.sections) { $s in
                            HStack(alignment: .top) {
                                TextField("Heading", text: $s.title).frame(width: 150)
                                TextField("What goes in this section", text: $s.guidance, axis: .vertical)
                                Button { t.wrappedValue.sections.removeAll { $0.id == s.id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                            }
                        }
                        Button("Add Section") { t.wrappedValue.sections.append(NoteSectionSpec(title: "", guidance: "")) }
                    } header: {
                        Text("Sections")
                    } footer: {
                        Text("Leave empty to let the model follow the reading's own structure.").font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(locked)
            HStack {
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                Spacer()
                Button("Duplicate") { if let d = draft?.duplicated() { persist(d) } }
                if !locked {
                    Button("Delete", role: .destructive) {
                        guard let id = draft?.id else { return }
                        app.deleteTemplate(id)
                        selectedID = app.noteTemplates.first?.id
                    }
                    Button("Save") { if let d = draft { persist(d) } }.buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
        }
    }

    private func persist(_ template: NoteTemplate) {
        do {
            try app.save(template)
            error = nil
            selectedID = template.id
            draft = template
        } catch {
            self.error = error.localizedDescription
        }
    }
}

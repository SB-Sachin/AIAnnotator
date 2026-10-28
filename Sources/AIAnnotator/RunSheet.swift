import AnnotatorCore
import SwiftUI

struct RunSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let run: PendingRun

    @ViewState private var mode: RunMode = .both
    @ViewState private var presetID = ""
    @ViewState private var templateID = ""
    @ViewState private var density: HighlightDensity = .light
    @ViewState private var model = ""

    private var preset: HighlightPreset? { app.highlightPresets.first { $0.id == presetID } }
    private var template: NoteTemplate? { app.noteTemplates.first { $0.id == templateID } }
    private var modelChoices: [String] { app.models.isEmpty ? [model] : app.models }
    private var canStart: Bool { preset != nil && template != nil && app.hasModel(model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(24)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    OptionSection("What should it make?") {
                        HStack(spacing: 10) {
                            ForEach(RunMode.allCases) { m in
                                ChoiceCard(selected: mode == m, action: { mode = m }) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Image(systemName: m.symbol)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(mode == m ? Theme.brand : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.label).font(.system(size: 13, weight: .semibold, design: .rounded))
                                            Text(m.blurb).font(.system(size: 11)).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if mode.wantsHighlights {
                        OptionSection("Highlight style") { PresetGrid(presets: app.highlightPresets, selection: $presetID) }
                        OptionSection("How much to highlight") { DensityPicker(selection: $density) }
                    }

                    if mode.wantsNotes {
                        OptionSection("Note template") { TemplateGrid(templates: app.noteTemplates, selection: $templateID) }
                    }

                    if app.status == .notRunning {
                        Label("Ollama isn't running. Open it, then try again.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }
                .padding(24)
            }
            Divider().opacity(0.5)
            footer.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 640, height: 640)
        .background(Theme.canvas)
        .onAppear {
            mode = app.lastMode
            presetID = app.highlightPresets.contains { $0.id == app.lastPresetID } ? app.lastPresetID : (app.highlightPresets.first?.id ?? "")
            templateID = app.noteTemplates.contains { $0.id == app.lastTemplateID } ? app.lastTemplateID : (app.noteTemplates.first?.id ?? "")
            density = app.lastDensity
            model = app.defaultModel
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("New reading").font(Theme.display(20))
                Text(run.urls.count == 1 ? run.urls[0].lastPathComponent
                     : "\(run.urls.count) files · \(run.urls.map(\.lastPathComponent).joined(separator: ", "))")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            ModelPicker(choices: modelChoices, selection: $model)
            Text("About 20–60 seconds a page").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(SoftButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button {
                guard let preset, let template else { return }
                app.start(run, options: RunOptions(mode: mode, preset: preset, template: template,
                                                   density: density, model: model))
            } label: {
                Label("Start", systemImage: "sparkles")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!canStart)
        }
    }
}

struct OptionSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title)
            content
        }
    }
}

struct PresetGrid: View {
    let presets: [HighlightPreset]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
            ForEach(presets) { p in
                ChoiceCard(selected: selection == p.id, action: { selection = p.id }) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 4) {
                            ForEach(p.categories) { CategoryDot(color: $0.color, size: 10) }
                        }
                        Text(p.name).font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(p.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct DensityPicker: View {
    @Binding var selection: HighlightDensity

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PillPicker(options: HighlightDensity.allCases.map { ($0, $0.label) }, selection: $selection)
            Text(selection.summary).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TemplateGrid: View {
    let templates: [NoteTemplate]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(templates) { t in
                ChoiceCard(selected: selection == t.id, action: { selection = t.id }) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.name).font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(t.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct ModelPicker: View {
    let choices: [String]
    @Binding var selection: String

    var body: some View {
        Picker(selection: $selection) {
            ForEach(choices, id: \.self) { Text($0).tag($0) }
        } label: {
            Image(systemName: "cpu")
        }
        .fixedSize()
        .help("Ollama model")
    }
}

struct Legend: View {
    let categories: [HighlightCategory]
    var action: ((HighlightCategory) -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(categories) { c in
                if let action {
                    Button { action(c) } label: { chip(c) }.buttonStyle(.plain).help("Highlight as \(c.name)")
                } else {
                    chip(c)
                }
            }
        }
    }

    private func chip(_ c: HighlightCategory) -> some View {
        HStack(spacing: 5) {
            CategoryDot(color: c.color)
            Text(c.name).font(.system(size: 11.5, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color(nsColor: c.color).opacity(0.22), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(nsColor: c.color).opacity(0.5)))
        .contentShape(Capsule())
    }
}

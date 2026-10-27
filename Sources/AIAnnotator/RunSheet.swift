import AnnotatorCore
import SwiftUI

struct RunSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let run: PendingRun

    @ViewState private var mode: RunMode = .both
    @ViewState private var presetID = ""
    @ViewState private var templateID = ""
    @ViewState private var model = ""

    private var preset: HighlightPreset? { app.highlightPresets.first { $0.id == presetID } }
    private var template: NoteTemplate? { app.noteTemplates.first { $0.id == templateID } }
    private var modelChoices: [String] { app.models.isEmpty ? [model] : app.models }
    private var canStart: Bool { preset != nil && template != nil && app.hasModel(model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New reading").font(.title2.weight(.semibold))
                Text(run.urls.map(\.lastPathComponent).joined(separator: ", "))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }

            Picker("Create", selection: $mode) {
                ForEach(RunMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if mode.wantsHighlights {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Highlight style", selection: $presetID) {
                        ForEach(app.highlightPresets) { Text($0.name).tag($0.id) }
                    }
                    if let preset {
                        Text(preset.summary).font(.caption).foregroundStyle(.secondary)
                        Legend(categories: preset.categories)
                    }
                }
            }

            if mode.wantsNotes {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Note template", selection: $templateID) {
                        ForEach(app.noteTemplates) { Text($0.name).tag($0.id) }
                    }
                    if let template {
                        Text(template.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Picker("Model", selection: $model) {
                ForEach(modelChoices, id: \.self) { Text($0).tag($0) }
            }

            if app.status == .notRunning {
                Label("Ollama isn't running. Open it, then try again.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("Takes about 20–60 seconds per page.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start") {
                    guard let preset, let template else { return }
                    app.start(run, options: RunOptions(mode: mode, preset: preset, template: template, model: model))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            mode = app.lastMode
            presetID = app.highlightPresets.contains { $0.id == app.lastPresetID } ? app.lastPresetID : (app.highlightPresets.first?.id ?? "")
            templateID = app.noteTemplates.contains { $0.id == app.lastTemplateID } ? app.lastTemplateID : (app.noteTemplates.first?.id ?? "")
            model = app.defaultModel
        }
    }
}

struct Legend: View {
    let categories: [HighlightCategory]
    var action: ((HighlightCategory) -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(categories) { c in
                if let action {
                    Button { action(c) } label: { chip(c) }.buttonStyle(.plain).help("Highlight selection as \(c.name)")
                } else {
                    chip(c)
                }
            }
        }
    }

    private func chip(_ c: HighlightCategory) -> some View {
        Text(c.name)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(nsColor: c.color).opacity(0.55), in: Capsule())
            .foregroundStyle(.primary)
    }
}

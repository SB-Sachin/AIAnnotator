import AnnotatorCore
import SwiftUI

struct RedoRequest: Identifiable {
    let id = UUID()
    var highlights: Bool
}

/// Redo the current reading's highlights or notes, optionally with a different style, amount or template.
struct RedoSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: Session
    let request: RedoRequest

    @ViewState private var highlights = true
    @ViewState private var presetID = ""
    @ViewState private var templateID = ""
    @ViewState private var density: HighlightDensity = .light
    @ViewState private var model = ""
    @ViewState private var rereadPhotos = false

    private var preset: HighlightPreset? { app.highlightPresets.first { $0.id == presetID } }
    private var template: NoteTemplate? { app.noteTemplates.first { $0.id == templateID } }
    private var modelChoices: [String] { app.models.isEmpty ? [model] : app.models }
    private var canStart: Bool { preset != nil && template != nil && app.hasModel(model) }
    private var hasHighlights: Bool { !session.entries.isEmpty }
    private var hasNotes: Bool { !session.notes.isEmpty }
    /// Readings saved before photo pages were recorded may have the old, broken photo text.
    private var mayNeedReread: Bool { session.photoPages == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Redo").font(Theme.display(20))
                    Text(session.title).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(24)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PillPicker(options: [(true, hasHighlights ? "Redo highlights" : "Add highlights"),
                                         (false, hasNotes ? "Redo notes" : "Add notes")],
                               selection: $highlights)

                    if highlights {
                        OptionSection("Highlight style") { PresetGrid(presets: app.highlightPresets, selection: $presetID) }
                        OptionSection("How much to highlight") { DensityPicker(selection: $density) }
                        if mayNeedReread {
                            Toggle(isOn: $rereadPhotos) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Re-read photographed pages").font(.system(size: 13, weight: .medium))
                                    Text("Turn on if this reading came from photos and its highlights look like large blocks. "
                                         + "Reads the page text again; all highlights on those pages are replaced.")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(12)
                            .card(12, shadow: false)
                        }
                        note(hasHighlights
                             ? "Replaces the current AI highlights on every page. Highlights you added yourself are kept."
                             : "Reads every page and adds highlights.")
                    } else {
                        OptionSection("Note template") { TemplateGrid(templates: app.noteTemplates, selection: $templateID) }
                        note((hasNotes ? "Replaces the current notes. " : "")
                             + (session.hasSavedDigests ? "Uses the pages already read, so it takes under a minute."
                                                        : "Reads every page first, about 20–60 seconds a page."))
                    }
                }
                .padding(24)
            }

            Divider().opacity(0.5)
            HStack(spacing: 10) {
                ModelPicker(choices: modelChoices, selection: $model)
                if session.beforeRedo != nil {
                    Text("You can undo this from the Redo menu.").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(SoftButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    guard let preset, let template else { return }
                    app.performRedo(on: session, highlights: highlights, rereadPhotos: highlights && rereadPhotos,
                                    options: RunOptions(mode: highlights ? .annotations : .notes, preset: preset,
                                                        template: template, density: density, model: model))
                } label: {
                    Label(highlights ? (hasHighlights ? "Redo highlights" : "Add highlights")
                                     : (hasNotes ? "Redo notes" : "Add notes"),
                          systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!canStart)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 640, height: highlights ? 640 : 520)
        .background(Theme.canvas)
        .onAppear {
            highlights = request.highlights
            presetID = app.highlightPresets.contains { $0.id == session.palette.id } ? session.palette.id
                : (app.highlightPresets.first?.id ?? "")
            templateID = app.noteTemplates.first { $0.name == session.templateName }?.id
                ?? (app.noteTemplates.contains { $0.id == app.lastTemplateID } ? app.lastTemplateID : (app.noteTemplates.first?.id ?? ""))
            density = session.density
            model = app.hasModel(session.model) ? session.model : app.defaultModel
        }
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

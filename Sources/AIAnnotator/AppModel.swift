import AnnotatorCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PendingRun: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct RunOptions {
    var mode: RunMode
    var preset: HighlightPreset
    var template: NoteTemplate
    var model: String
}

@MainActor
final class AppModel: ObservableObject {
    enum OllamaStatus: Equatable {
        case checking, ok, notRunning, modelMissing(String)
    }

    @Published var models: [String] = []
    @Published var status: OllamaStatus = .checking
    @Published var defaultModel: String {
        didSet { UserDefaults.standard.set(defaultModel, forKey: "defaultModel"); Task { await refreshOllama() } }
    }
    @Published var highlightPresets: [HighlightPreset] = []
    @Published var noteTemplates: [NoteTemplate] = []
    @Published var library: [ReadingItem] = []
    @Published var session: Session?
    @Published var pending: PendingRun?
    @Published var selection: UUID?

    let client = OllamaClient()
    let presetStore = PresetStore()
    let libraryStore = LibraryStore()

    init() {
        defaultModel = UserDefaults.standard.string(forKey: "defaultModel") ?? "gemma3:12b"
        reloadPresets()
        reloadLibrary()
        Task { await refreshOllama() }
    }

    // MARK: Ollama

    func refreshOllama() async {
        do {
            models = try await client.listModels()
            status = hasModel(defaultModel) ? .ok : .modelMissing(defaultModel)
        } catch {
            models = []
            status = .notRunning
        }
    }

    func hasModel(_ name: String) -> Bool {
        models.contains(name) || models.contains(name + ":latest")
    }

    // MARK: Last-used run options

    var lastMode: RunMode {
        get { RunMode(rawValue: UserDefaults.standard.string(forKey: "lastMode") ?? "") ?? .both }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lastMode") }
    }
    var lastPresetID: String {
        get { UserDefaults.standard.string(forKey: "lastPreset") ?? BuiltIns.highlightPresets[0].id }
        set { UserDefaults.standard.set(newValue, forKey: "lastPreset") }
    }
    var lastTemplateID: String {
        get { UserDefaults.standard.string(forKey: "lastTemplate") ?? BuiltIns.noteTemplates[0].id }
        set { UserDefaults.standard.set(newValue, forKey: "lastTemplate") }
    }

    // MARK: Readings

    func open(_ urls: [URL]) {
        let supported = urls.filter(Ingest.isSupported)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !supported.isEmpty else { return }
        pending = PendingRun(urls: supported)
        Task { await refreshOllama() }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .image]
        panel.message = "Choose a PDF, or photos of pages (they'll be combined in name order)."
        if panel.runModal() == .OK { open(panel.urls) }
    }

    func start(_ run: PendingRun, options: RunOptions) {
        saveCurrentIfDirty()
        lastMode = options.mode
        lastPresetID = options.preset.id
        lastTemplateID = options.template.id
        let s = Session(urls: run.urls, options: options)
        s.onSaved = { [weak self] in self?.reloadLibrary() }
        session = s
        selection = s.id
        pending = nil
        s.start(urls: run.urls, options: options, client: client)
    }

    func openItem(_ id: UUID?) {
        guard let id, session?.id != id, let item = library.first(where: { $0.id == id }) else { return }
        saveCurrentIfDirty()
        let palette = highlightPresets.first { $0.name == item.presetName } ?? BuiltIns.highlightPresets[0]
        let s = Session(item: item, store: libraryStore, preset: palette)
        s.onSaved = { [weak self] in self?.reloadLibrary() }
        session = s
    }

    func newReading() {
        saveCurrentIfDirty()
        session = nil
        selection = nil
    }

    func delete(_ item: ReadingItem) {
        if session?.id == item.id {
            session?.cancel()
            session = nil
        }
        libraryStore.delete(id: item.id)
        reloadLibrary()
    }

    func reloadLibrary() {
        library = libraryStore.list()
    }

    private func saveCurrentIfDirty() {
        if let s = session, s.dirty, !s.isRunning { s.save() }
    }

    // MARK: Presets

    func reloadPresets() {
        highlightPresets = presetStore.highlightPresets()
        noteTemplates = presetStore.noteTemplates()
    }

    func save(_ preset: HighlightPreset) throws {
        var p = preset
        var seen = Set<String>()
        for i in p.categories.indices {
            var id = slug(p.categories[i].name)
            if id.isEmpty { id = "category" }
            var unique = id
            var n = 2
            while seen.contains(unique) { unique = "\(id)-\(n)"; n += 1 }
            seen.insert(unique)
            p.categories[i].id = unique
        }
        try presetStore.save(p)
        reloadPresets()
    }

    func save(_ template: NoteTemplate) throws {
        try presetStore.save(template)
        reloadPresets()
    }

    func deletePreset(_ id: String) {
        presetStore.deleteHighlightPreset(id: id)
        reloadPresets()
    }

    func deleteTemplate(_ id: String) {
        presetStore.deleteTemplate(id: id)
        reloadPresets()
    }

    private func slug(_ s: String) -> String {
        s.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
    }
}

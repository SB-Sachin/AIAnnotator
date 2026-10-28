import Foundation

public enum AppPaths {
    public static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AIAnnotator", isDirectory: true)
    }
    public static var presets: URL { root.appendingPathComponent("Presets", isDirectory: true) }
    public static var library: URL { root.appendingPathComponent("Library", isDirectory: true) }
}

private let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return e
}()

private let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

/// Built-in presets live in code; custom ones are JSON files under Application Support.
public struct PresetStore: Sendable {
    public let root: URL

    public init(root: URL = AppPaths.presets) {
        self.root = root
    }

    private var highlightDir: URL { root.appendingPathComponent("highlights", isDirectory: true) }
    private var templateDir: URL { root.appendingPathComponent("templates", isDirectory: true) }

    public func highlightPresets() -> [HighlightPreset] {
        BuiltIns.highlightPresets + loadAll(HighlightPreset.self, in: highlightDir).sorted { $0.name < $1.name }
    }

    public func noteTemplates() -> [NoteTemplate] {
        BuiltIns.noteTemplates + loadAll(NoteTemplate.self, in: templateDir).sorted { $0.name < $1.name }
    }

    public func save(_ preset: HighlightPreset) throws {
        try write(preset, to: highlightDir.appendingPathComponent(preset.id + ".json"))
    }

    public func save(_ template: NoteTemplate) throws {
        try write(template, to: templateDir.appendingPathComponent(template.id + ".json"))
    }

    public func deleteHighlightPreset(id: String) {
        try? FileManager.default.removeItem(at: highlightDir.appendingPathComponent(id + ".json"))
    }

    public func deleteTemplate(id: String) {
        try? FileManager.default.removeItem(at: templateDir.appendingPathComponent(id + ".json"))
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func loadAll<T: Decodable>(_ type: T.Type, in dir: URL) -> [T] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }
}

/// One page's digest, kept with a reading so its notes can be rewritten without re-reading every page.
public struct PageDigestEntry: Codable, Hashable, Sendable {
    public var page: Int
    public var digest: PageDigest

    public init(page: Int, digest: PageDigest) {
        self.page = page
        self.digest = digest
    }
}

/// Each reading is a folder: item.json, document.pdf (with annotations), notes.md, digests.json.
public struct LibraryStore: Sendable {
    public let root: URL

    public init(root: URL = AppPaths.library) {
        self.root = root
    }

    public func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func pdfURL(for id: UUID) -> URL { folder(for: id).appendingPathComponent("document.pdf") }
    public func notesURL(for id: UUID) -> URL { folder(for: id).appendingPathComponent("notes.md") }

    public func list() -> [ReadingItem] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("item.json")) else { return nil }
            return try? decoder.decode(ReadingItem.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func save(_ item: ReadingItem, pdfData: Data?, notes: String?) throws {
        let dir = folder(for: item.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoder.encode(item).write(to: dir.appendingPathComponent("item.json"), options: .atomic)
        if let pdfData { try pdfData.write(to: pdfURL(for: item.id), options: .atomic) }
        if let notes { try notes.write(to: notesURL(for: item.id), atomically: true, encoding: .utf8) }
    }

    public func saveDigests(_ digests: [PageDigestEntry], for id: UUID) throws {
        let url = folder(for: id).appendingPathComponent("digests.json")
        if digests.isEmpty { try? FileManager.default.removeItem(at: url); return }
        try encoder.encode(digests).write(to: url, options: .atomic)
    }

    public func loadDigests(for id: UUID) -> [PageDigestEntry] {
        guard let data = try? Data(contentsOf: folder(for: id).appendingPathComponent("digests.json")) else { return [] }
        return (try? decoder.decode([PageDigestEntry].self, from: data)) ?? []
    }

    public func loadNotes(for id: UUID) -> String? {
        try? String(contentsOf: notesURL(for: id), encoding: .utf8)
    }

    public func delete(id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }
}

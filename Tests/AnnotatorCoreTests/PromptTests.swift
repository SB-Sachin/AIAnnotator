import Foundation
import Testing
@testable import AnnotatorCore

struct PromptTests {
    let preset = BuiltIns.highlightPresets[0]

    @Test func schemaMatchesMode() {
        let both = PromptBuilder.pageRequest(mode: .both, preset: preset, pageText: "x", pageNumber: 1, pageCount: 1)
        #expect(both.schema["required"] as? [String] == ["highlights", "digest"])
        let notes = PromptBuilder.pageRequest(mode: .notes, preset: preset, pageText: "x", pageNumber: 1, pageCount: 1)
        #expect(notes.schema["required"] as? [String] == ["digest"])
        let hl = PromptBuilder.pageRequest(mode: .annotations, preset: preset, pageText: "x", pageNumber: 1, pageCount: 1)
        #expect(hl.schema["required"] as? [String] == ["highlights"])
        #expect(!hl.system.contains("DIGEST"))
    }

    @Test func highlightSchemaRestrictsCategories() throws {
        let schema = PromptBuilder.highlightSchema(preset)
        let items = try #require(schema["items"] as? [String: Any])
        let props = try #require(items["properties"] as? [String: Any])
        let category = try #require(props["category"] as? [String: Any])
        #expect(category["enum"] as? [String] == ["main", "definition", "example", "fact"])
        #expect(JSONSerialization.isValidJSONObject(schema))
    }

    @Test func notesRequestListsTemplateSections() {
        let template = BuiltIns.noteTemplates.first { $0.id == "key-terms" }!
        let digest = PageDigest(summary: "About cells", key_points: ["Cells divide"], terms: [.init(term: "Mitosis", definition: "Cell division")])
        let req = PromptBuilder.notesRequest(template: template, title: "Bio", digests: [(1, digest)])
        #expect(req.system.contains("\"Key Terms\""))
        #expect(req.user.contains("Mitosis: Cell division"))
        #expect(JSONSerialization.isValidJSONObject(req.schema))
    }

    @Test func decodesPageResult() throws {
        let json = #"{"highlights":[{"quote":"a b c d","category":"main","note":""}],"digest":{"summary":"s","key_points":[],"terms":[]}}"#
        let r = try JSONDecoder().decode(PageResult.self, from: Data(json.utf8))
        #expect(r.highlights?.first?.category == "main")
        #expect(r.digest?.summary == "s")
    }

    @Test func presetStoreRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PresetStore(root: dir)
        let custom = preset.duplicated()
        try store.save(custom)
        #expect(store.highlightPresets().contains { $0.id == custom.id && !$0.isBuiltIn })
        store.deleteHighlightPreset(id: custom.id)
        #expect(store.highlightPresets().count == BuiltIns.highlightPresets.count)
    }
}

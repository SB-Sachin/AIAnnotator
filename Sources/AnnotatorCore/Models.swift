import AppKit
import Foundation

public enum RunMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case notes, annotations, both

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .notes: return "Notes"
        case .annotations: return "Highlights"
        case .both: return "Both"
        }
    }
    public var wantsNotes: Bool { self != .annotations }
    public var wantsHighlights: Bool { self != .notes }
}

public struct HighlightCategory: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var colorHex: String
    public var description: String

    public init(id: String, name: String, colorHex: String, description: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.description = description
    }

    public var color: NSColor { NSColor(hex: colorHex) }
}

/// How the model's per-highlight comment is shown on the page.
public enum MarginStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, popup, margin

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: return "No comments"
        case .popup: return "Comment on hover"
        case .margin: return "Visible margin notes"
        }
    }
}

public struct HighlightPreset: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var instructions: String
    public var categories: [HighlightCategory]
    public var marginStyle: MarginStyle
    public var maxPerPage: Int
    public var isBuiltIn: Bool

    public init(id: String, name: String, summary: String, instructions: String, categories: [HighlightCategory],
                marginStyle: MarginStyle, maxPerPage: Int, isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.summary = summary
        self.instructions = instructions
        self.categories = categories
        self.marginStyle = marginStyle
        self.maxPerPage = maxPerPage
        self.isBuiltIn = isBuiltIn
    }

    public func category(_ id: String) -> HighlightCategory? {
        categories.first { $0.id == id } ?? categories.first { $0.name.lowercased() == id.lowercased() }
    }

    public func duplicated() -> HighlightPreset {
        var copy = self
        copy.id = "custom-" + UUID().uuidString.lowercased()
        copy.name = name + " (Copy)"
        copy.isBuiltIn = false
        return copy
    }
}

public enum NoteLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case cornell, sections

    public var id: String { rawValue }
    public var label: String { self == .cornell ? "Cornell (cues + notes + summary)" : "Sections" }
}

public struct NoteSectionSpec: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var guidance: String

    public init(id: UUID = UUID(), title: String, guidance: String) {
        self.id = id
        self.title = title
        self.guidance = guidance
    }
}

public struct NoteTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var instructions: String
    public var layout: NoteLayout
    /// Empty for `.sections` means the model picks headings that mirror the reading.
    public var sections: [NoteSectionSpec]
    public var isBuiltIn: Bool

    public init(id: String, name: String, summary: String, instructions: String, layout: NoteLayout,
                sections: [NoteSectionSpec], isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.summary = summary
        self.instructions = instructions
        self.layout = layout
        self.sections = sections
        self.isBuiltIn = isBuiltIn
    }

    public func duplicated() -> NoteTemplate {
        var copy = self
        copy.id = "custom-" + UUID().uuidString.lowercased()
        copy.name = name + " (Copy)"
        copy.isBuiltIn = false
        return copy
    }
}

public struct ReadingItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var mode: RunMode
    public var model: String
    public var presetName: String?
    public var templateName: String?
    public var templateLayout: NoteLayout?
    public var hasNotes: Bool

    public init(id: UUID, title: String, createdAt: Date, mode: RunMode, model: String, presetName: String?,
                templateName: String?, templateLayout: NoteLayout?, hasNotes: Bool) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.mode = mode
        self.model = model
        self.presetName = presetName
        self.templateName = templateName
        self.templateLayout = templateLayout
        self.hasNotes = hasNotes
    }
}

extension NSColor {
    public convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0xFFE066
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    public var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#FFE066" }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

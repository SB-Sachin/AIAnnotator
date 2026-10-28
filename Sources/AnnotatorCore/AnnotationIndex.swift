import AppKit
import Foundation
import PDFKit

/// One highlight in a document, described for the at-a-glance list.
public struct AnnotationEntry: Identifiable {
    public let annotation: PDFAnnotation
    public let pageIndex: Int
    public let quote: String
    public let category: HighlightCategory?
    public let label: String
    public let note: String
    public let color: NSColor

    public var id: ObjectIdentifier { ObjectIdentifier(annotation) }
}

public enum AnnotationIndex {
    /// Every highlight in reading order: by page, then top to bottom, left to right.
    @MainActor
    public static func entries(in document: PDFDocument, palette: HighlightPreset) -> [AnnotationEntry] {
        var out: [AnnotationEntry] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let highlights = page.annotations.filter(PDFHighlighter.isHighlight)
                .sorted { a, b in
                    let ra = PDFHighlighter.lineRects(of: a).first ?? a.bounds
                    let rb = PDFHighlighter.lineRects(of: b).first ?? b.bounds
                    return abs(ra.maxY - rb.maxY) > 2 ? ra.maxY > rb.maxY : ra.minX < rb.minX
                }
            for ann in highlights {
                let (label, note) = split(ann.contents)
                let category = palette.categories.first { $0.name == label } ?? nearest(ann.color, in: palette)
                out.append(AnnotationEntry(annotation: ann, pageIndex: i, quote: PDFHighlighter.text(of: ann),
                                           category: category, label: category?.name ?? label,
                                           note: note, color: ann.color.withAlphaComponent(1)))
            }
        }
        return out
    }

    /// Highlight contents are stored as "Category: note" (or just "Category").
    public static func split(_ contents: String?) -> (label: String, note: String) {
        let text = (contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = text.range(of: ":") else { return (text, "") }
        let label = String(text[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
        let note = String(text[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (label, note)
    }

    static func nearest(_ color: NSColor, in palette: HighlightPreset) -> HighlightCategory? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        return palette.categories.min { a, b in distance(c, a.color) < distance(c, b.color) }
            .flatMap { distance(c, $0.color) < 0.12 ? $0 : nil }
    }

    private static func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        guard let b = b.usingColorSpace(.sRGB) else { return .greatestFiniteMagnitude }
        return pow(a.redComponent - b.redComponent, 2) + pow(a.greenComponent - b.greenComponent, 2)
            + pow(a.blueComponent - b.blueComponent, 2)
    }
}

import AppKit
import Foundation
import PDFKit

/// Places highlights and margin notes as standard PDF annotations so they also show up in Preview.
@MainActor
public enum PDFHighlighter {
    public static let author = "AIAnnotator"
    public static let highlightAlpha: CGFloat = 0.45

    public struct Placement {
        public var placed: Int = 0
        public var missed: [String] = []
    }

    public static func place(_ highlights: [RawHighlight], on page: PDFPage, preset: HighlightPreset) -> Placement {
        var result = Placement()
        let text = page.string ?? ""
        var used: [NSRange] = []
        var notesPlaced: [CGRect] = []
        for h in highlights {
            guard let range = QuoteMatcher.find(h.quote, in: text),
                  !used.contains(where: { NSIntersectionRange($0, range).length > 0 }),
                  let selection = page.selection(for: range) else {
                result.missed.append(h.quote)
                continue
            }
            let category = preset.category(h.category) ?? preset.categories.first
            let color = category?.color ?? NSColor(hex: "#FFE066")
            let note = (h.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let label = category?.name ?? ""
            let contents = note.isEmpty || preset.marginStyle == .none ? label : "\(label): \(note)"
            guard let ann = highlight(selection, on: page, color: color, contents: contents) else {
                result.missed.append(h.quote)
                continue
            }
            used.append(range)
            result.placed += 1
            if preset.marginStyle == .margin, !note.isEmpty {
                addMarginNote(note, beside: ann.bounds, on: page, color: color, occupied: &notesPlaced)
            }
        }
        return result
    }

    @discardableResult
    public static func highlight(_ selection: PDFSelection, on page: PDFPage, color: NSColor,
                                 contents: String?) -> PDFAnnotation? {
        let lines = selection.selectionsByLine()
            .filter { $0.pages.contains(page) }
            .map { $0.bounds(for: page) }
            .filter { $0.width > 0.5 && $0.height > 0.5 }
        guard let first = lines.first else { return nil }
        let union = lines.dropFirst().reduce(first) { $0.union($1) }
        let ann = PDFAnnotation(bounds: union, forType: .highlight, withProperties: nil)
        ann.color = color.withAlphaComponent(highlightAlpha)
        ann.quadrilateralPoints = lines.flatMap { r -> [NSValue] in
            let o = union.origin
            return [NSValue(point: NSPoint(x: r.minX - o.x, y: r.maxY - o.y)),
                    NSValue(point: NSPoint(x: r.maxX - o.x, y: r.maxY - o.y)),
                    NSValue(point: NSPoint(x: r.minX - o.x, y: r.minY - o.y)),
                    NSValue(point: NSPoint(x: r.maxX - o.x, y: r.minY - o.y))]
        }
        ann.contents = contents
        ann.userName = author
        page.addAnnotation(ann)
        return ann
    }

    /// Puts a small visible note in whichever side margin has room; falls back to a sticky-note icon.
    static func addMarginNote(_ note: String, beside rect: CGRect, on page: PDFPage, color: NSColor,
                              occupied: inout [CGRect]) {
        let pageBox = page.bounds(for: .cropBox)
        let textLength = (page.string ?? "").utf16.count
        let textBox = textLength > 0 ? page.selection(for: NSRange(location: 0, length: textLength))?.bounds(for: page) : nil
        let column = textBox ?? pageBox.insetBy(dx: 72, dy: 72)
        let right = pageBox.maxX - column.maxX
        let left = column.minX - pageBox.minX
        let space = max(right, left)

        guard space >= 64 else {
            let icon = PDFAnnotation(bounds: CGRect(x: pageBox.maxX - 26, y: rect.maxY - 18, width: 18, height: 18),
                                     forType: .text, withProperties: nil)
            icon.contents = note
            icon.color = color
            icon.iconType = .comment
            icon.userName = author
            page.addAnnotation(icon)
            return
        }

        let font = NSFont.systemFont(ofSize: 7.5)
        let width = min(space - 14, 150)
        let measured = (note as NSString).boundingRect(with: CGSize(width: width - 6, height: 400),
                                                       options: [.usesLineFragmentOrigin],
                                                       attributes: [.font: font]).height
        let height = ceil(measured) + 6
        let x = right >= left ? column.maxX + 8 : pageBox.minX + (left - width) / 2
        var box = CGRect(x: x, y: rect.maxY - height, width: width, height: height)
        while occupied.contains(where: { $0.intersects(box) }), box.minY > pageBox.minY + height {
            box.origin.y -= 4
        }
        occupied.append(box)

        let ann = PDFAnnotation(bounds: box, forType: .freeText, withProperties: nil)
        ann.contents = note
        ann.font = font
        ann.fontColor = NSColor(white: 0.15, alpha: 1)
        ann.color = color.withAlphaComponent(0.22)
        let border = PDFBorder()
        border.lineWidth = 0
        ann.border = border
        ann.userName = author
        page.addAnnotation(ann)
    }

    public static func isEditable(_ ann: PDFAnnotation) -> Bool {
        let type = (ann.type ?? "").replacingOccurrences(of: "/", with: "")
        return ["Highlight", "FreeText", "Text"].contains(type)
    }

    public static func isHighlight(_ ann: PDFAnnotation) -> Bool {
        (ann.type ?? "").replacingOccurrences(of: "/", with: "") == "Highlight"
    }
}

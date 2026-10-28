import AppKit
import Foundation
import PDFKit

/// Places highlights and margin notes as standard PDF annotations so they also show up in Preview.
@MainActor
public enum PDFHighlighter {
    public static let author = "AIAnnotator"
    public static let highlightAlpha: CGFloat = 0.45
    /// Custom annotation key holding the highlighted text, so the list can show it exactly.
    static let quoteKey = PDFAnnotationKey(rawValue: "/AIQuote")

    public struct Placement {
        public var placed: Int = 0
        /// Quotes that couldn't be found in the page text.
        public var missed: [String] = []
        /// Suggestions cut for overlap, length or the density budget.
        public var dropped = 0
    }

    public static func place(_ highlights: [RawHighlight], on page: PDFPage, preset: HighlightPreset,
                             density: HighlightDensity = .balanced, sentences: PageSentences? = nil) -> Placement {
        let sentences = sentences ?? PageSentences(page.string ?? "")
        let plan = HighlightPlanner.plan(highlights, sentences: sentences, density: density, maxPerPage: preset.maxPerPage)
        var result = Placement(placed: 0, missed: plan.missed, dropped: plan.dropped)
        var notesPlaced: [CGRect] = []
        for h in plan.highlights {
            guard let selection = page.selection(for: h.range) else {
                result.missed.append((sentences.text as NSString).substring(with: h.range))
                continue
            }
            let category = preset.category(h.category) ?? preset.categories.first
            let color = category?.color ?? NSColor(hex: "#FFE066")
            let label = category?.name ?? ""
            let contents = h.note.isEmpty || preset.marginStyle == .none ? label : "\(label): \(h.note)"
            guard let ann = highlight(selection, on: page, color: color, contents: contents) else {
                result.missed.append(selection.string ?? "")
                continue
            }
            result.placed += 1
            if preset.marginStyle == .margin, !h.note.isEmpty {
                addMarginNote(h.note, beside: ann.bounds, on: page, color: color, occupied: &notesPlaced)
            }
        }
        return result
    }

    /// Adds a highlight over `selection`. Any existing highlight it covers is replaced, and its
    /// line boxes are trimmed so they never stack on neighbouring lines or other highlights.
    @discardableResult
    public static func highlight(_ selection: PDFSelection, on page: PDFPage, color: NSColor,
                                 contents: String?) -> PDFAnnotation? {
        var lines = selection.selectionsByLine()
            .filter { $0.pages.contains(page) }
            .map { $0.bounds(for: page) }
            .filter { $0.width > 0.5 && $0.height > 0.5 }
            .map { $0.insetBy(dx: 0, dy: $0.height * 0.06) }
        guard !lines.isEmpty else { return nil }

        for old in page.annotations where isHighlight(old) {
            let oldRects = lineRects(of: old)
            let covered = oldRects.contains { o in lines.contains { sameLine($0, o) && $0.intersection(o).width > 0.5 * min($0.width, o.width) } }
            if covered { remove(old) }
        }
        let others = page.annotations.filter(isHighlight).flatMap(lineRects(of:))
        lines = separated(lines, from: others)

        let union = lines.dropFirst().reduce(lines[0]) { $0.union($1) }
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
        let quote = PageSentences.clean(selection.string ?? "")
        if !quote.isEmpty { ann.setValue(quote, forAnnotationKey: quoteKey) }
        page.addAnnotation(ann)
        return ann
    }

    /// Two boxes on the same text line overlap mostly vertically; boxes on adjacent lines only slightly.
    static func sameLine(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > 0.6 * min(a.height, b.height)
    }

    /// Splits vertical overlaps between boxes on different lines at the midpoint, so translucent
    /// highlights don't leave darker bands where they stack.
    static func separated(_ rects: [CGRect], from fixed: [CGRect]) -> [CGRect] {
        var out = rects
        func trim(_ i: Int, against other: CGRect, movesOther: Bool) -> CGRect? {
            let a = out[i]
            guard a.minX < other.maxX, other.minX < a.maxX, a.intersects(other), !sameLine(a, other) else { return nil }
            var o = other
            if a.midY > other.midY {
                let mid = (a.minY + other.maxY) / 2
                out[i] = CGRect(x: a.minX, y: mid, width: a.width, height: a.maxY - mid)
                if movesOther { o = CGRect(x: o.minX, y: o.minY, width: o.width, height: mid - o.minY) }
            } else {
                let mid = (other.minY + a.maxY) / 2
                out[i] = CGRect(x: a.minX, y: a.minY, width: a.width, height: mid - a.minY)
                if movesOther { o = CGRect(x: o.minX, y: mid, width: o.width, height: o.maxY - mid) }
            }
            return o
        }
        for i in out.indices {
            for j in out.indices where j > i {
                if let moved = trim(i, against: out[j], movesOther: true) { out[j] = moved }
            }
            for f in fixed { _ = trim(i, against: f, movesOther: false) }
        }
        return out.filter { $0.height > 1 }
    }

    /// Page-space boxes for each line of a highlight annotation.
    public static func lineRects(of ann: PDFAnnotation) -> [CGRect] {
        guard let quads = ann.quadrilateralPoints, quads.count >= 4 else { return [ann.bounds] }
        let o = ann.bounds.origin
        return stride(from: 0, to: quads.count - 3, by: 4).map { i in
            let pts = quads[i..<i + 4].map(\.pointValue)
            let xs = pts.map(\.x), ys = pts.map(\.y)
            return CGRect(x: xs.min()! + o.x, y: ys.min()! + o.y, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
    }

    /// The highlighted text: saved with the highlight when this app made it, otherwise read from the page
    /// as one selection from its first line to its last.
    public static func text(of ann: PDFAnnotation) -> String {
        if let saved = ann.value(forAnnotationKey: quoteKey) as? String, !saved.isEmpty { return saved }
        guard let page = ann.page else { return "" }
        let lines = lineRects(of: ann).sorted { abs($0.midY - $1.midY) > 2 ? $0.midY > $1.midY : $0.minX < $1.minX }
        guard let first = lines.first, let last = lines.last,
              let selection = page.selection(from: CGPoint(x: first.minX + 1, y: first.midY),
                                             to: CGPoint(x: last.maxX - 1, y: last.midY)) else { return "" }
        return PageSentences.clean(selection.string ?? "")
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
        // PDFKit pads free-text boxes, so measure narrower and add room, or the last line gets cut off.
        let measured = (note as NSString).boundingRect(with: CGSize(width: width - 14, height: 400),
                                                       options: [.usesLineFragmentOrigin],
                                                       attributes: [.font: font]).height
        let height = ceil(measured) + 12
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

    /// Removes a highlight together with the margin note that belongs to it.
    public static func remove(_ ann: PDFAnnotation) {
        guard let page = ann.page else { return }
        let note = AnnotationIndex.split(ann.contents).note
        if isHighlight(ann), !note.isEmpty {
            for other in page.annotations where other !== ann && other.userName == author && !isHighlight(other)
                && other.contents == note {
                page.removeAnnotation(other)
            }
        }
        page.removeAnnotation(ann)
    }

    public static func isEditable(_ ann: PDFAnnotation) -> Bool {
        let type = (ann.type ?? "").replacingOccurrences(of: "/", with: "")
        return ["Highlight", "FreeText", "Text"].contains(type)
    }

    public static func isHighlight(_ ann: PDFAnnotation) -> Bool {
        (ann.type ?? "").replacingOccurrences(of: "/", with: "") == "Highlight"
    }
}

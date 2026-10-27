import AppKit
import Foundation

/// Renders notes markdown to a printable US Letter PDF. Cornell notes get a real two-column layout.
public enum NotesPDFRenderer {
    public static func render(markdown: String, layout: NoteLayout) -> Data {
        let pager = Pager()
        switch layout {
        case .cornell: renderCornell(CornellLayout(markdown: markdown), pager)
        case .sections: renderFlow(MarkdownParser.parse(markdown), pager)
        }
        return pager.finish()
    }

    // MARK: Styles

    static let ink = NSColor(white: 0.12, alpha: 1)
    static let rule = NSColor(white: 0.75, alpha: 1)
    static let accent = NSColor(srgbRed: 0.18, green: 0.36, blue: 0.62, alpha: 1)

    static func text(_ s: String, size: CGFloat, bold: Bool = false, color: NSColor = ink,
                     indent: CGFloat = 0, bulletIndent: CGFloat? = nil) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = size * 0.18
        para.firstLineHeadIndent = indent
        para.headIndent = bulletIndent ?? indent
        let out = NSMutableAttributedString()
        for run in MarkdownParser.inlineRuns(s) {
            let font = (bold || run.bold) ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
            out.append(NSAttributedString(string: run.text, attributes: [.font: font, .foregroundColor: color]))
        }
        out.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: out.length))
        return out
    }

    static func attributed(_ block: MarkdownBlock) -> (NSAttributedString, spaceBefore: CGFloat) {
        switch block {
        case .heading(let level, let t):
            let size: CGFloat = level == 1 ? 20 : level == 2 ? 14.5 : 12
            return (text(t, size: size, bold: true, color: level == 2 ? accent : ink), level == 1 ? 0 : 12)
        case .bullet(let level, let t):
            let indent = CGFloat(level) * 14
            let marker = level == 0 ? "•" : level == 1 ? "◦" : "▪"
            let isNumbered = t.first?.isNumber == true
            let body = isNumbered ? t : "\(marker)\t\(t)"
            let s = NSMutableAttributedString(attributedString: text(body, size: 10.5, indent: indent, bulletIndent: indent + 12))
            let para = (s.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
            para.tabStops = [NSTextTab(textAlignment: .left, location: indent + 12)]
            s.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: s.length))
            return (s, 3)
        case .paragraph(let t):
            return (text(t, size: 10.5), 6)
        }
    }

    // MARK: Layouts

    static func renderFlow(_ blocks: [MarkdownBlock], _ pager: Pager) {
        for block in blocks {
            let (s, space) = attributed(block)
            let h = pager.measure(s, width: pager.contentWidth)
            pager.ensure(h + space)
            pager.y += space
            pager.draw(s, x: pager.margin, width: pager.contentWidth)
            pager.y += h
            if case .heading(1, _) = block { pager.y += 6; pager.line(y: pager.y); pager.y += 4 }
        }
    }

    static func renderCornell(_ c: CornellLayout, _ pager: Pager) {
        if !c.title.isEmpty {
            let t = text(c.title, size: 20, bold: true)
            let h = pager.measure(t, width: pager.contentWidth)
            pager.draw(t, x: pager.margin, width: pager.contentWidth)
            pager.y += h + 10
        }
        let gap: CGFloat = 14
        let cueW = (pager.contentWidth - gap) * 0.3
        let notesX = pager.margin + cueW + gap
        let notesW = pager.contentWidth - cueW - gap

        let header = { (pager: Pager) in
            let a = text("CUES", size: 8.5, bold: true, color: accent)
            let b = text("NOTES", size: 8.5, bold: true, color: accent)
            pager.draw(a, x: pager.margin, width: cueW)
            pager.draw(b, x: notesX, width: notesW)
            pager.y += 14
            pager.line(y: pager.y, color: accent, width: 1)
        }
        header(pager)
        pager.onNewPage = header

        for row in c.rows {
            let cue = text(row.cue, size: 10.5, bold: true)
            let notes = NSMutableAttributedString()
            for (i, block) in row.notes.enumerated() {
                if i > 0 { notes.append(NSAttributedString(string: "\n")) }
                notes.append(attributed(block).0)
            }
            let h = max(pager.measure(cue, width: cueW), pager.measure(notes, width: notesW)) + 16
            pager.ensure(h)
            let top = pager.y
            pager.draw(cue, x: pager.margin, width: cueW, y: top + 8)
            pager.draw(notes, x: notesX, width: notesW, y: top + 8)
            pager.vline(x: pager.margin + cueW + gap / 2, from: top, to: top + h)
            pager.y = top + h
            pager.line(y: pager.y)
        }
        pager.onNewPage = nil

        if !c.summary.isEmpty {
            let heading = text("Summary", size: 13, bold: true, color: accent)
            let body = NSMutableAttributedString()
            for (i, block) in c.summary.enumerated() {
                if i > 0 { body.append(NSAttributedString(string: "\n")) }
                body.append(attributed(block).0)
            }
            let h = pager.measure(heading, width: pager.contentWidth) + 6 + pager.measure(body, width: pager.contentWidth)
            pager.ensure(h + 20)
            pager.y += 8
            pager.line(y: pager.y, color: accent, width: 1)
            pager.y += 8
            pager.draw(heading, x: pager.margin, width: pager.contentWidth)
            pager.y += pager.measure(heading, width: pager.contentWidth) + 6
            pager.draw(body, x: pager.margin, width: pager.contentWidth)
            pager.y += pager.measure(body, width: pager.contentWidth)
        }
    }

    // MARK: Pager

    final class Pager {
        let size = CGSize(width: 612, height: 792)
        let margin: CGFloat = 54
        var contentWidth: CGFloat { size.width - margin * 2 }
        var y: CGFloat = 0
        var onNewPage: ((Pager) -> Void)?
        private let data = NSMutableData()
        private let ctx: CGContext
        private var pageOpen = false

        init() {
            var box = CGRect(origin: .zero, size: size)
            ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
            beginPage()
        }

        private func beginPage() {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            pageOpen = true
            y = margin
        }

        private func endPage() {
            guard pageOpen else { return }
            NSGraphicsContext.current = nil
            ctx.restoreGState()
            ctx.endPDFPage()
            pageOpen = false
        }

        func ensure(_ height: CGFloat) {
            if y + height > size.height - margin && y > margin + 30 {
                endPage()
                beginPage()
                onNewPage?(self)
            }
        }

        func measure(_ s: NSAttributedString, width: CGFloat) -> CGFloat {
            guard s.length > 0 else { return 0 }
            return ceil(s.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        }

        func draw(_ s: NSAttributedString, x: CGFloat, width: CGFloat, y: CGFloat? = nil) {
            let top = y ?? self.y
            s.draw(with: CGRect(x: x, y: top, width: width, height: measure(s, width: width) + 2),
                   options: [.usesLineFragmentOrigin, .usesFontLeading])
        }

        func line(y: CGFloat, color: NSColor = NotesPDFRenderer.rule, width: CGFloat = 0.5) {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(width)
            ctx.move(to: CGPoint(x: margin, y: y))
            ctx.addLine(to: CGPoint(x: size.width - margin, y: y))
            ctx.strokePath()
        }

        func vline(x: CGFloat, from: CGFloat, to: CGFloat) {
            ctx.setStrokeColor(NotesPDFRenderer.rule.cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: x, y: from))
            ctx.addLine(to: CGPoint(x: x, y: to))
            ctx.strokePath()
        }

        func finish() -> Data {
            endPage()
            ctx.closePDF()
            return data as Data
        }
    }
}

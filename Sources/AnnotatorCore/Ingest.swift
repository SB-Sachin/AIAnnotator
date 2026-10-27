import AppKit
import CoreText
import Foundation
import ImageIO
import PDFKit
import Vision

public enum IngestError: LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Couldn't open \(name)."
        case .unsupported(let name): return "\(name) isn't a PDF or an image."
        case .empty: return "Nothing to process."
        }
    }
}

public enum Ingest {
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "gif", "bmp"]

    public static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "pdf" || imageExtensions.contains(ext)
    }

    /// Combines PDFs and photos (in the given order) into one PDF. Photos become pages with an
    /// invisible OCR text layer so they can be highlighted like a digital PDF.
    public static func makePDFData(from urls: [URL]) throws -> Data {
        guard !urls.isEmpty else { throw IngestError.empty }
        if urls.count == 1, urls[0].pathExtension.lowercased() == "pdf" {
            guard let data = try? Data(contentsOf: urls[0]), PDFDocument(data: data) != nil else {
                throw IngestError.unreadable(urls[0].lastPathComponent)
            }
            return data
        }
        let combined = PDFDocument()
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let source: PDFDocument?
            if ext == "pdf" {
                source = PDFDocument(url: url)
            } else if imageExtensions.contains(ext) {
                source = PDFDocument(data: try ocrPage(imageURL: url))
            } else {
                throw IngestError.unsupported(url.lastPathComponent)
            }
            guard let source else { throw IngestError.unreadable(url.lastPathComponent) }
            for i in 0..<source.pageCount {
                if let page = source.page(at: i)?.copy() as? PDFPage {
                    combined.insert(page, at: combined.pageCount)
                }
            }
        }
        guard combined.pageCount > 0, let data = combined.dataRepresentation() else { throw IngestError.empty }
        return data
    }

    public static func ocrPage(imageURL: URL) throws -> Data {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respects the photo's EXIF rotation
            kCGImageSourceThumbnailMaxPixelSize: 3000,
        ] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options) else {
            throw IngestError.unreadable(imageURL.lastPathComponent)
        }
        return try ocrPage(image: image)
    }

    public static func ocrPage(image: CGImage) throws -> Data {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let observations = request.results ?? []

        let width: CGFloat = 612
        let pageRect = CGRect(x: 0, y: 0, width: width, height: width * CGFloat(image.height) / CGFloat(image.width))
        let data = NSMutableData()
        var box = pageRect
        guard let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil) else {
            throw IngestError.empty
        }
        ctx.beginPDFPage(nil)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: pageRect)

        // Vision returns observations top-to-bottom; keep that order so page text reads naturally.
        for obs in observations {
            guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { continue }
            let bb = obs.boundingBox
            let r = CGRect(x: bb.minX * pageRect.width, y: bb.minY * pageRect.height,
                           width: bb.width * pageRect.width, height: bb.height * pageRect.height)
            let font = CTFontCreateWithName("Helvetica" as CFString, max(r.height * 0.8, 1), nil)
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.saveGState()
            ctx.setTextDrawingMode(.invisible)
            ctx.textMatrix = .identity
            ctx.translateBy(x: r.minX, y: r.minY + r.height * 0.2)
            if lineWidth > 0 { ctx.scaleBy(x: r.width / CGFloat(lineWidth), y: 1) }
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    /// JPEG of the page for the vision model, longest side `maxDimension` px.
    public static func pageImage(_ page: PDFPage, maxDimension: CGFloat = 1200) -> Data? {
        let b = page.bounds(for: .mediaBox)
        guard b.width > 0, b.height > 0 else { return nil }
        let scale = maxDimension / max(b.width, b.height)
        let size = NSSize(width: (b.width * scale).rounded(), height: (b.height * scale).rounded())
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}

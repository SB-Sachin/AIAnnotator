import AppKit
import CoreImage
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

    /// Turns a photo of a page into a PDF page: the straightened photo, with an invisible text layer laid
    /// out word by word at each word's position, so text can be searched, selected and highlighted.
    public static func ocrPage(image: CGImage) throws -> Data {
        let image = straightened(image)
        let observations = try recognizeText(in: image)

        let width: CGFloat = 612
        let pageRect = CGRect(x: 0, y: 0, width: width, height: width * CGFloat(image.height) / CGFloat(image.width))
        let data = NSMutableData()
        var box = pageRect
        guard let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil) else {
            throw IngestError.empty
        }
        ctx.beginPDFPage(nil)
        ctx.setFillColor(.white)
        ctx.fill(pageRect)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: pageRect)
        ctx.setTextDrawingMode(.invisible)
        func toPage(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * pageRect.width, y: r.minY * pageRect.height,
                   width: r.width * pageRect.width, height: r.height * pageRect.height)
        }

        // Vision returns lines roughly top to bottom; keep that order so page text reads naturally.
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string
            let words = wordRanges(in: text)
            guard !words.isEmpty else { continue }
            let lineBox = toPage(obs.boundingBox)

            // Each word's own box. Vision sometimes answers with the whole line; then share it out by length.
            var boxes: [CGRect] = words.map { range in
                guard words.count > 1, let b = try? candidate.boundingBox(for: range)?.boundingBox else { return .null }
                let r = toPage(b)
                return r.width < lineBox.width * 0.9 ? r : .null
            }
            if boxes.contains(where: \.isNull) {
                let total = CGFloat(text.count)
                boxes = words.map { range in
                    let start = CGFloat(text.distance(from: text.startIndex, to: range.lowerBound)) / total
                    let length = CGFloat(text.distance(from: range.lowerBound, to: range.upperBound)) / total
                    return CGRect(x: lineBox.minX + start * lineBox.width, y: lineBox.minY,
                                  width: length * lineBox.width, height: lineBox.height)
                }
            }
            // Size the font from the typical word height, not the line box, which a tilted or curved line inflates.
            let heights = boxes.map(\.height).sorted()
            let size = max(heights[heights.count / 2] / 1.15, 1)
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let descent = CTFontGetDescent(font)

            for (range, wordBox) in zip(words, boxes) {
                let word = String(text[range])
                let measured = CTLineGetTypographicBounds(line(word, font), nil, nil, nil)
                guard measured > 0, wordBox.width > 0 else { continue }
                // A trailing space keeps words, and the last word of one line and the first of the next, apart.
                let drawn = line(word + " ", font)
                ctx.saveGState()
                ctx.textMatrix = .identity
                ctx.translateBy(x: wordBox.minX, y: wordBox.midY - size * 0.5 + descent * 0.5)
                ctx.scaleBy(x: wordBox.width / CGFloat(measured), y: 1)
                ctx.textPosition = .zero
                CTLineDraw(drawn, ctx)
                ctx.restoreGState()
            }
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    private static func line(_ text: String, _ font: CTFont) -> CTLine {
        CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    }

    static func wordRanges(in text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        for i in text.indices {
            if text[i].isWhitespace {
                if let s = start { out.append(s..<i); start = nil }
            } else if start == nil {
                start = i
            }
        }
        if let s = start { out.append(s..<text.endIndex) }
        return out
    }

    static func recognizeText(in image: CGImage) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return request.results ?? []
    }

    /// Crops a photo to the page and flattens its perspective, like a document scanner, then rotates away
    /// any remaining tilt so text lines are level. Returns the photo unchanged when neither step applies.
    public static func straightened(_ image: CGImage) -> CGImage {
        var result = flattenedDocument(image) ?? image
        if let angle = textAngle(in: result), abs(angle) > 0.003, let level = rotated(result, by: -angle) {
            result = level
        }
        return result
    }

    static func flattenedDocument(_ image: CGImage) -> CGImage? {
        let request = VNDetectDocumentSegmentationRequest()
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil,
              let doc = request.results?.first, doc.confidence > 0.8 else { return nil }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: p.y * h) }
        let corners = [doc.topLeft, doc.topRight, doc.bottomRight, doc.bottomLeft].map(px)
        // Shoelace area: skip when the "document" is a small part of the photo (likely a misdetection).
        let area = abs(zip(corners, corners.dropFirst() + [corners[0]]).reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }) / 2
        guard area > 0.35 * w * h,
              let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: px(doc.topLeft)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: px(doc.topRight)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: px(doc.bottomRight)), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: px(doc.bottomLeft)), forKey: "inputBottomLeft")
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    /// Median slope of the longer text lines, in radians (positive = rising to the right).
    static func textAngle(in image: CGImage) -> CGFloat? {
        guard let observations = try? recognizeText(in: image) else { return nil }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let angles = observations.filter { $0.boundingBox.width > 0.25 }.map { obs in
            atan2((obs.topRight.y - obs.topLeft.y) * h, (obs.topRight.x - obs.topLeft.x) * w)
        }.sorted()
        guard angles.count >= 3 else { return nil }
        return angles[angles.count / 2]
    }

    static func rotated(_ image: CGImage, by angle: CGFloat) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let c = CGPoint(x: ci.extent.midX, y: ci.extent.midY)
        let turn = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).translatedBy(x: -c.x, y: -c.y)
        let white = CIImage(color: .white).cropped(to: ci.extent)
        let output = ci.transformed(by: turn).composited(over: white).cropped(to: ci.extent)
        return CIContext().createCGImage(output, from: ci.extent)
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

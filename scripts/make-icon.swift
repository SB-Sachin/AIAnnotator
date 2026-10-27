// Draws the app icon and writes Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func sparkle(center c: CGPoint, radius r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k = r * 0.16
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y + k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - k, y: c.y + k))
    p.closeSubpath()
    return p
}

// Tile: macOS icon grid (824pt body inside a 1024 canvas) with a soft drop shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, 0.35))
ctx.addPath(rounded(tile, 185))
ctx.setFillColor(color(0x3A2E9C))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(rounded(tile, 185))
ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [color(0x7B6CF0), color(0x3A2E9C)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// Page, tilted slightly.
ctx.saveGState()
ctx.translateBy(x: 500, y: 505)
ctx.rotate(by: 6 * .pi / 180)
let page = CGRect(x: -240, y: -300, width: 480, height: 600)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x140F40, 0.45))
ctx.addPath(rounded(page, 34))
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// Text lines, three of them highlighted in the study preset's colors.
let lines: [(width: CGFloat, highlight: UInt32?)] = [
    (330, nil), (380, 0xFFE066), (300, nil), (360, nil), (250, 0x8CE99A), (370, nil), (290, 0x74C0FC),
]
for (i, line) in lines.enumerated() {
    let y = page.maxY - 92 - CGFloat(i) * 70
    let x = page.minX + 52
    if let hl = line.highlight {
        ctx.addPath(rounded(CGRect(x: x - 14, y: y - 16, width: line.width + 28, height: 54), 12))
        ctx.setFillColor(color(hl))
        ctx.fillPath()
    }
    ctx.addPath(rounded(CGRect(x: x, y: y, width: line.width, height: 22), 11))
    ctx.setFillColor(line.highlight == nil ? color(0xD3D6DF) : color(0x5C6070))
    ctx.fillPath()
}
ctx.restoreGState()

// AI sparkle over the page's corner.
let big = sparkle(center: CGPoint(x: 742, y: 300), radius: 128)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x140F40, 0.4))
ctx.addPath(big)
ctx.setLineWidth(26)
ctx.setLineJoin(.round)
ctx.setStrokeColor(color(0xFFFFFF))
ctx.strokePath()
ctx.restoreGState()
ctx.addPath(big)
ctx.saveGState()
ctx.clip()
let gold = CGGradient(colorsSpace: cs, colors: [color(0xFFE066), color(0xFF9F43)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gold, start: CGPoint(x: 742, y: 428), end: CGPoint(x: 742, y: 172), options: [])
ctx.restoreGState()
ctx.addPath(sparkle(center: CGPoint(x: 838, y: 438), radius: 46))
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// Write a 1024 PNG, then every iconset size, then the .icns.
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = NSBitmapImageRep(cgImage: ctx.makeImage()!)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        master.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
try master.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Resources/AppIcon.png"))
print("Wrote \(out.path)")

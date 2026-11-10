#!/usr/bin/env swift
// Draws the OptionTap app icon in code and writes Resources/AppIcon.iconset.
// Usage: swift Scripts/make_icon.swift   (from the package folder)
//
// The design: a deep blue tile with a floating panel (search bar, list rows, preview) and
// an ⌥ keycap in the corner, the key that opens it.

import AppKit

func drawIcon(_ px: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = px / 1024   // design in 1024 units

    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        // y is measured from the top in the design
        NSRect(x: x * s, y: (1024 - y - h) * s, width: w * s, height: h * s)
    }
    func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius * s, yRadius: radius * s)
    }

    // Tile (macOS icon grid: 824 pt body centred in 1024, radius ~185)
    let tile = rounded(r(100, 100, 824, 824), 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor.black.setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(colors: [NSColor(red: 0.23, green: 0.36, blue: 1.0, alpha: 1),
                        NSColor(red: 0.08, green: 0.12, blue: 0.42, alpha: 1)])!
        .draw(in: tile.bounds, angle: -70)
    // Soft light in the top-left corner
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: rounded(r(40, 40, 620, 620), 310), relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()

    // Panel
    let panelRect = r(190, 250, 644, 470)
    NSGraphicsContext.saveGraphicsState()
    let panelShadow = NSShadow()
    panelShadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
    panelShadow.shadowBlurRadius = 40 * s
    panelShadow.shadowOffset = NSSize(width: 0, height: -18 * s)
    panelShadow.set()
    NSColor(red: 0.07, green: 0.09, blue: 0.18, alpha: 0.92).setFill()
    rounded(panelRect, 56).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.16).setStroke()
    let border = rounded(panelRect.insetBy(dx: 2 * s, dy: 2 * s), 54)
    border.lineWidth = 4 * s
    border.stroke()

    // Search bar
    NSColor.white.withAlphaComponent(0.10).setFill()
    rounded(r(226, 286, 572, 64), 32).fill()
    let lens = NSBezierPath(ovalIn: r(254, 302, 28, 28))
    lens.lineWidth = 6 * s
    NSColor.white.withAlphaComponent(0.75).setStroke()
    lens.stroke()
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: 278 * s, y: (1024 - 326) * s))
    handle.line(to: NSPoint(x: 292 * s, y: (1024 - 340) * s))
    handle.lineWidth = 7 * s
    handle.lineCapStyle = .round
    handle.stroke()
    NSColor.white.withAlphaComponent(0.35).setFill()
    rounded(r(310, 309, 190, 18), 9).fill()

    // List rows (the selected one in blue)
    for i in 0..<4 {
        let y = 380 + CGFloat(i) * 78
        if i == 0 {
            NSColor(red: 0.17, green: 0.30, blue: 1.0, alpha: 1).setFill()
            rounded(r(222, y - 8, 300, 66), 20).fill()
        }
        let swatch: NSColor = [NSColor(red: 1, green: 0.85, blue: 0.30, alpha: 1),
                               NSColor(red: 0.13, green: 0.70, blue: 0.37, alpha: 1),
                               NSColor.white.withAlphaComponent(0.5),
                               NSColor.white.withAlphaComponent(0.5)][i]
        swatch.setFill()
        rounded(r(240, y + 4, 42, 42), 12).fill()
        NSColor.white.withAlphaComponent(i == 0 ? 0.95 : 0.55).setFill()
        rounded(r(298, y + 10, i % 2 == 0 ? 180 : 140, 14), 7).fill()
        NSColor.white.withAlphaComponent(i == 0 ? 0.6 : 0.28).setFill()
        rounded(r(298, y + 32, 100, 10), 5).fill()
    }

    // Preview pane
    NSColor.white.withAlphaComponent(0.08).setFill()
    rounded(r(546, 372, 252, 312), 26).fill()
    NSColor(red: 1, green: 0.85, blue: 0.30, alpha: 1).setFill()
    rounded(r(572, 398, 200, 140), 18).fill()
    NSColor.white.withAlphaComponent(0.4).setFill()
    for (i, w) in [CGFloat(190), 150, 170].enumerated() {
        rounded(r(574, 566 + CGFloat(i) * 34, w, 14), 7).fill()
    }

    // ⌥ keycap
    let key = r(650, 650, 210, 190)
    NSGraphicsContext.saveGraphicsState()
    let keyShadow = NSShadow()
    keyShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    keyShadow.shadowBlurRadius = 26 * s
    keyShadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    keyShadow.set()
    NSColor(white: 0.96, alpha: 1).setFill()
    rounded(key, 44).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 0.84, alpha: 1).setFill()
    rounded(r(650, 812, 210, 28), 14).fill()
    NSColor(white: 0.96, alpha: 1).setFill()
    rounded(r(650, 650, 210, 172), 44).fill()
    let option = NSAttributedString(string: "⌥", attributes: [
        .font: NSFont.systemFont(ofSize: 120 * s, weight: .semibold),
        .foregroundColor: NSColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1),
    ])
    let size = option.size()
    option.draw(at: NSPoint(x: key.midX - size.width / 2, y: key.minY + (key.height + 18 * s) / 2 - size.height / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: "Resources/AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: out.appendingPathComponent(name))
    }
}
print("Wrote \(out.path)")

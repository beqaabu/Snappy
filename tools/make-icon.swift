import Cocoa

// Draws the app icon and writes an iconset (plus a 1024px PNG for previews).
// Run through tools/make-icon.sh, which calls iconutil.

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

/// The icon: a colourful squircle with a dashed selection, its handles, and a camera badge.
func drawIcon(size S: CGFloat) {
    let ctx = NSGraphicsContext.current!.cgContext
    let unit = S / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit) }

    // macOS icons leave a margin inside their canvas.
    let plate = r(100, 100, 824, 824)
    let squircle = NSBezierPath(roundedRect: plate, xRadius: 185 * unit, yRadius: 185 * unit)

    ctx.saveGState()
    squircle.addClip()
    NSGradient(colors: [NSColor(red: 0.26, green: 0.42, blue: 0.86, alpha: 1),
                        NSColor(red: 0.55, green: 0.33, blue: 0.80, alpha: 1),
                        NSColor(red: 0.95, green: 0.50, blue: 0.52, alpha: 1)])?
        .draw(in: plate, angle: -45)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])?
        .draw(in: NSRect(x: plate.minX, y: plate.midY, width: plate.width, height: plate.height / 2), angle: -90)
    ctx.restoreGState()

    NSColor.black.withAlphaComponent(0.2).setStroke()
    squircle.lineWidth = 2 * unit
    squircle.stroke()

    // The selection: a lighter area with a dashed white outline and corner handles.
    let selection = r(238, 318, 548, 412)
    NSColor.white.withAlphaComponent(0.2).setFill()
    NSBezierPath(rect: selection).fill()
    let outline = NSBezierPath(rect: selection)
    outline.lineWidth = 20 * unit
    outline.setLineDash([62 * unit, 30 * unit], count: 2, phase: 0)
    NSColor.white.setStroke()
    outline.stroke()

    let handle: CGFloat = 46
    for x in [selection.minX, selection.maxX] {
        for y in [selection.minY, selection.maxY] {
            let dot = NSBezierPath(ovalIn: NSRect(x: x - handle / 2 * unit, y: y - handle / 2 * unit, width: handle * unit, height: handle * unit))
            NSColor.white.setFill()
            dot.fill()
            NSColor(red: 0.22, green: 0.45, blue: 0.95, alpha: 1).setStroke()
            dot.lineWidth = 10 * unit
            dot.stroke()
        }
    }

    // Camera badge over the bottom-right corner, lifted off the plate by a shadow and a light ring.
    let center = NSPoint(x: 716 * unit, y: 306 * unit)
    let radius = 142 * unit
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius - 14 * unit, y: center.y - radius - 14 * unit,
                                           width: (radius + 14 * unit) * 2, height: (radius + 14 * unit) * 2))
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 30 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.set()
    NSColor.white.withAlphaComponent(0.9).setFill()
    ring.fill()
    NSGraphicsContext.restoreGraphicsState()

    let badge = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    NSGradient(colors: [NSColor(red: 0.36, green: 0.62, blue: 1.0, alpha: 1),
                        NSColor(red: 0.16, green: 0.40, blue: 0.95, alpha: 1)])?
        .draw(in: NSBezierPath(ovalIn: badge), angle: -90)

    // Camera glyph: body, viewfinder bump, lens.
    NSColor.white.setFill()
    let body = NSRect(x: center.x - 92 * unit, y: center.y - 62 * unit, width: 184 * unit, height: 122 * unit)
    NSBezierPath(roundedRect: body, xRadius: 26 * unit, yRadius: 26 * unit).fill()
    NSBezierPath(roundedRect: NSRect(x: center.x - 40 * unit, y: body.maxY - 16 * unit, width: 80 * unit, height: 42 * unit),
                 xRadius: 12 * unit, yRadius: 12 * unit).fill()
    let lensCenter = NSPoint(x: center.x, y: body.midY - 2 * unit)
    NSColor(red: 0.20, green: 0.44, blue: 0.96, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: lensCenter.x - 42 * unit, y: lensCenter.y - 42 * unit, width: 84 * unit, height: 84 * unit)).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: lensCenter.x - 24 * unit, y: lensCenter.y - 24 * unit, width: 48 * unit, height: 48 * unit)).fill()
}

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: size)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// iconset layout expected by iconutil
let iconset = "\(outputDirectory)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    write(render(size: CGFloat(base)), to: "\(iconset)/icon_\(base)x\(base).png")
    write(render(size: CGFloat(base * 2)), to: "\(iconset)/icon_\(base)x\(base)@2x.png")
}
write(render(size: 1024), to: "\(outputDirectory)/icon-preview.png")
print("wrote \(iconset)")

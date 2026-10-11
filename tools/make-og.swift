import Cocoa

// Draws site/og.png (1200×630), the link preview for the website, from docs/icon.png and docs/preview.png.
// Run through tools/make-og.sh.

let W: CGFloat = 1200, H: CGFloat = 630
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSGradient(colors: [NSColor(red: 0.08, green: 0.07, blue: 0.13, alpha: 1), NSColor(red: 0.16, green: 0.10, blue: 0.24, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -30)

// Screenshot on the right, bleeding off the edge.
let preview = NSImage(contentsOfFile: "docs/preview.png")!
let shotH: CGFloat = 470, shotW = shotH * preview.size.width / preview.size.height
let shot = NSRect(x: 560, y: (H - shotH) / 2, width: shotW, height: shotH)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSColor.black.setFill()
NSBezierPath(roundedRect: shot, xRadius: 18, yRadius: 18).fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: shot, xRadius: 18, yRadius: 18).addClip()
preview.draw(in: shot)
NSGraphicsContext.restoreGraphicsState()

// Icon, name and tagline on the left.
NSImage(contentsOfFile: "docs/icon.png")!.draw(in: NSRect(x: 64, y: 372, width: 150, height: 150))
func text(_ s: String, _ p: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    (s as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: -size * 0.02])
}
text("Snappy", NSPoint(x: 80, y: 262), size: 84, weight: .bold, color: .white)
text("Screenshots in one shortcut.", NSPoint(x: 82, y: 214), size: 30, weight: .semibold, color: NSColor(red: 0.78, green: 0.66, blue: 1, alpha: 1))
text("Drag, mark up, click. For macOS.", NSPoint(x: 82, y: 172), size: 26, weight: .regular, color: NSColor.white.withAlphaComponent(0.7))
text("Free · open source", NSPoint(x: 82, y: 92), size: 22, weight: .medium, color: NSColor.white.withAlphaComponent(0.5))

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("Wrote \(CommandLine.arguments[1])")

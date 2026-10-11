import AppKit
import Carbon.HIToolbox

// Renders docs/preview.png: Snappy's real overlay (selection, markup, toolbars) on top of a
// mock desktop drawn here, so the README image never shows real apps or private content.
// Run via tools/render-preview.sh.

let W: CGFloat = 1280, H: CGFloat = 800, scale: CGFloat = 2

// MARK: Mock desktop

func roundedWindow(_ frame: CGRect, title: String, body: (CGRect) -> Void) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = CGSize(width: 0, height: -8)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12).fill()
    NSGraphicsContext.restoreGraphicsState()

    let bar = CGRect(x: frame.minX, y: frame.maxY - 40, width: frame.width, height: 40)
    NSColor(white: 0.96, alpha: 1).setFill()
    let barPath = NSBezierPath(roundedRect: bar, xRadius: 12, yRadius: 12)
    barPath.append(NSBezierPath(rect: CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: 12)))
    barPath.fill()
    for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: CGRect(x: frame.minX + 16 + CGFloat(i) * 20, y: bar.midY - 6, width: 12, height: 12)).fill()
    }
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor(white: 0.25, alpha: 1)]
    let size = (title as NSString).size(withAttributes: attrs)
    (title as NSString).draw(at: CGPoint(x: frame.midX - size.width / 2, y: bar.midY - size.height / 2), withAttributes: attrs)
    body(CGRect(x: frame.minX + 24, y: frame.minY + 20, width: frame.width - 48, height: frame.height - 80))
}

func text(_ s: String, _ p: CGPoint, size: CGFloat = 15, weight: NSFont.Weight = .regular, color: NSColor = NSColor(white: 0.2, alpha: 1), mono: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
}

func drawDesktop() {
    NSGradient(colors: [NSColor(red: 0.26, green: 0.42, blue: 0.86, alpha: 1),
                        NSColor(red: 0.55, green: 0.33, blue: 0.80, alpha: 1),
                        NSColor(red: 0.93, green: 0.52, blue: 0.56, alpha: 1)])!
        .draw(in: CGRect(x: 0, y: 0, width: W, height: H), angle: -35)

    NSColor.white.withAlphaComponent(0.25).setFill()
    NSBezierPath(rect: CGRect(x: 0, y: H - 28, width: W, height: 28)).fill()
    var x: CGFloat = 20
    for (i, item) in ["Notes", "File", "Edit", "Format", "View", "Window", "Help"].enumerated() {
        text(item, CGPoint(x: x, y: H - 22), size: 13, weight: i == 0 ? .bold : .medium, color: .white)
        x += (item as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold)]).width + 20
    }
    text("Sat Oct 10  9:41", CGPoint(x: W - 130, y: H - 22), size: 13, weight: .medium, color: .white)

    // Chart window (behind).
    roundedWindow(CGRect(x: 700, y: 170, width: 480, height: 400), title: "Weekly signups") { r in
        let values: [CGFloat] = [0.35, 0.5, 0.42, 0.68, 0.6, 0.82, 0.95]
        let barW = (r.width - 20) / CGFloat(values.count) - 14
        for (i, v) in values.enumerated() {
            NSColor.systemBlue.withAlphaComponent(0.25 + 0.75 * v).setFill()
            let bx = r.minX + 10 + CGFloat(i) * (barW + 14)
            NSBezierPath(roundedRect: CGRect(x: bx, y: r.minY + 30, width: barW, height: (r.height - 60) * v), xRadius: 5, yRadius: 5).fill()
            text(["M", "T", "W", "T", "F", "S", "S"][i], CGPoint(x: bx + barW / 2 - 4, y: r.minY + 6), size: 12, color: .gray)
        }
    }

    // Notes window (front): the one being captured.
    roundedWindow(CGRect(x: 150, y: 120, width: 600, height: 520), title: "Launch checklist") { r in
        text("Snappy 1.0 launch", CGPoint(x: r.minX, y: r.maxY - 34), size: 26, weight: .bold, color: .black)
        let items: [(String, Bool)] = [("Write the README", true), ("Record the demo", true),
                                       ("Publish the release", true), ("Submit the Homebrew cask", false),
                                       ("Tell everyone", false)]
        for (i, (item, done)) in items.enumerated() {
            let y = r.maxY - 90 - CGFloat(i) * 38
            let box = CGRect(x: r.minX, y: y, width: 18, height: 18)
            (done ? NSColor.systemGreen : NSColor(white: 0.75, alpha: 1)).setFill()
            NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
            if done { text("✓", CGPoint(x: box.minX + 3, y: box.minY), size: 13, weight: .bold, color: .white) }
            text(item, CGPoint(x: r.minX + 30, y: y - 1), size: 17, color: done ? .gray : NSColor(white: 0.15, alpha: 1))
        }
        text("Deploy token", CGPoint(x: r.minX, y: r.minY + 92), size: 13, weight: .semibold, color: .gray)
        NSColor(white: 0.95, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: r.minX, y: r.minY + 44, width: r.width, height: 40), xRadius: 8, yRadius: 8).fill()
        text("snp_live_9f3a7c2e41b8d06f5e2a", CGPoint(x: r.minX + 14, y: r.minY + 54), size: 16, mono: true)
    }
}

let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: scale, y: scale)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
drawDesktop()
let desktop = ctx.makeImage()!

// MARK: Drive the real overlay

_ = NSApplication.shared
let view = OverlayView(frame: CGRect(x: 0, y: 0, width: W, height: H), image: desktop, windows: [],
                       selection: CGRect(x: 130, y: 140, width: 640, height: 520))
let window = OverlayWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
window.contentView = view
window.makeFirstResponder(view)

func mouse(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}
func key(_ code: Int, _ chars: String) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                     context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))!
}
func drag(_ a: CGPoint, _ b: CGPoint) {
    view.mouseDown(with: mouse(.leftMouseDown, a))
    view.mouseDragged(with: mouse(.leftMouseDragged, b))
    view.mouseUp(with: mouse(.leftMouseUp, b))
}
func click(_ p: CGPoint) {
    view.mouseDown(with: mouse(.leftMouseDown, p))
    view.mouseUp(with: mouse(.leftMouseUp, p))
}

view.keyDown(with: key(kVK_ANSI_B, "b"))
drag(CGPoint(x: 176, y: 186), CGPoint(x: 720, y: 222))           // blur the token
view.keyDown(with: key(kVK_ANSI_R, "r"))
drag(CGPoint(x: 164, y: 368), CGPoint(x: 422, y: 404))           // box the next unfinished item
view.keyDown(with: key(kVK_ANSI_A, "a"))
drag(CGPoint(x: 585, y: 440), CGPoint(x: 430, y: 390))           // arrow to it
view.keyDown(with: key(kVK_ANSI_T, "t"))
click(CGPoint(x: 545, y: 462))
(window.firstResponder as? NSTextView)?.insertText("Next up!", replacementRange: NSRange(location: NSNotFound, length: 0))
window.makeFirstResponder(view)                                    // commit the text, keeping the Text tool selected

let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
view.cacheDisplay(in: view.bounds, to: rep)
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/preview.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")

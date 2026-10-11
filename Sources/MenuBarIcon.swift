import AppKit

/// Menu bar icon: a dashed selection with corner handles and a camera on its corner, like the
/// app icon. Drawn as a template image so macOS tints it for light, dark and colored menu bars.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let body = NSRect(x: 8.5, y: 1, width: 9, height: 6.5)
            selection(NSRect(x: 2, y: 5.5, width: 12, height: 10), clearOf: NSPoint(x: body.minX - 1.3, y: body.maxY + 1.3 + 1.3))
            camera(body)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Snappy"
        return image
    }

    /// Handles on three corners, evenly spaced dashes between them. The right and bottom sides stop
    /// short of the camera (`clearOf` is the camera's top-left corner, gap included).
    private static func selection(_ r: NSRect, clearOf camera: NSPoint) {
        let handle: CGFloat = 1.6
        let tl = NSPoint(x: r.minX, y: r.maxY), tr = NSPoint(x: r.maxX, y: r.maxY), bl = NSPoint(x: r.minX, y: r.minY)
        dashes(from: tl, to: tr, trimStart: handle, trimEnd: handle)
        dashes(from: tl, to: bl, trimStart: handle, trimEnd: handle)
        dashes(from: tr, to: NSPoint(x: r.maxX, y: camera.y), trimStart: handle, trimEnd: 0)
        dashes(from: bl, to: NSPoint(x: camera.x, y: r.minY), trimStart: handle, trimEnd: 0)
        for p in [tl, tr, bl] {
            NSBezierPath(ovalIn: NSRect(x: p.x - handle, y: p.y - handle, width: 2 * handle, height: 2 * handle)).fill()
        }
    }

    private static func dashes(from a: NSPoint, to b: NSPoint, trimStart: CGFloat, trimEnd: CGFloat) {
        let length = hypot(b.x - a.x, b.y - a.y)
        let ux = (b.x - a.x) / length, uy = (b.y - a.y) / length
        let start = trimStart + 0.9, span = length - start - trimEnd - (trimEnd > 0 ? 0.9 : 0)
        guard span > 1 else { return }
        let dash: CGFloat = 1.5
        let count = max(1, Int((span + 1.2) / 2.7))
        let gap = count > 1 ? (span - CGFloat(count) * dash) / CGFloat(count - 1) : 0
        let offset = count > 1 ? 0 : (span - dash) / 2
        let path = NSBezierPath()
        for i in 0..<count {
            let d0 = start + offset + CGFloat(i) * (dash + gap)
            path.move(to: NSPoint(x: a.x + ux * d0, y: a.y + uy * d0))
            path.line(to: NSPoint(x: a.x + ux * (d0 + dash), y: a.y + uy * (d0 + dash)))
        }
        path.lineWidth = 1.3
        path.stroke()
    }

    /// A solid camera with a knocked-out lens, separated from the selection by a transparent gap.
    private static func camera(_ body: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bump = NSRect(x: body.midX - 1.7, y: body.maxY - 0.5, width: 3.4, height: 1.8)
        let gap: CGFloat = 1.3
        ctx.setBlendMode(.clear)
        NSBezierPath(roundedRect: body.insetBy(dx: -gap, dy: -gap), xRadius: 1.6 + gap, yRadius: 1.6 + gap).fill()
        NSBezierPath(roundedRect: bump.insetBy(dx: -gap, dy: -gap), xRadius: 0.6 + gap, yRadius: 0.6 + gap).fill()
        ctx.setBlendMode(.normal)
        NSBezierPath(roundedRect: body, xRadius: 1.6, yRadius: 1.6).fill()
        NSBezierPath(roundedRect: bump, xRadius: 0.6, yRadius: 0.6).fill()
        let lens = NSPoint(x: body.midX, y: body.midY - 0.1)
        ctx.setBlendMode(.clear)
        NSBezierPath(ovalIn: NSRect(x: lens.x - 2.1, y: lens.y - 2.1, width: 4.2, height: 4.2)).fill()
        ctx.setBlendMode(.normal)
        NSBezierPath(ovalIn: NSRect(x: lens.x - 1, y: lens.y - 1, width: 2, height: 2)).fill()
    }
}

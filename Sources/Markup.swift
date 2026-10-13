import AppKit
import Carbon.HIToolbox
import CoreImage

// MARK: - Quick markup: arrows, boxes, pen, highlighter, text, numbered steps and blur on a selection

enum MarkupTool: CaseIterable {
    case arrow, box, pen, highlight, text, step, blur

    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .box: "rectangle"
        case .pen: "scribble"
        case .highlight: "highlighter"
        case .text: "textformat"
        case .step: "1.circle"
        case .blur: "drop.halffull"
        }
    }

    init?(keyCode: Int) {
        switch keyCode {
        case kVK_ANSI_A: self = .arrow
        case kVK_ANSI_R: self = .box
        case kVK_ANSI_P: self = .pen
        case kVK_ANSI_H: self = .highlight
        case kVK_ANSI_T: self = .text
        case kVK_ANSI_N: self = .step
        case kVK_ANSI_B: self = .blur
        default: return nil
        }
    }
}

/// Stroke width, text size and step badge size, all scaled together.
enum MarkupSize: Int, CaseIterable {
    case small, medium, large
    var scale: CGFloat { [0.6, 1, 1.6][rawValue] }
    var next: MarkupSize { MarkupSize(rawValue: (rawValue + 1) % MarkupSize.allCases.count)! }
}

enum Markup {
    static let colors: [NSColor] = [.systemRed, .systemYellow, .systemBlue, .black, .white]

    static func font(_ size: MarkupSize) -> NSFont { .systemFont(ofSize: 22 * size.scale, weight: .bold) }

    static func textAttributes(_ color: NSColor, _ size: MarkupSize) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = (isLight(color) ? NSColor.black : NSColor.white).withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 3
        return [.font: font(size), .foregroundColor: color, .shadow: shadow]
    }

    static func isLight(_ color: NSColor) -> Bool {
        guard let c = color.usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.6
    }

    /// A blocky copy of the whole screenshot; blur annotations show it through their rect.
    static func pixelated(_ image: CGImage, pointScale: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input
            .clampedToExtent()
            .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: 12 * pointScale, kCIInputCenterKey: CIVector(x: 0, y: 0)])
            .cropped(to: input.extent)
        return CIContext().createCGImage(output, from: input.extent)
    }
}

struct Annotation {
    enum Kind {
        case arrow(from: CGPoint, to: CGPoint)
        case box(CGRect)
        case pen([CGPoint])
        case highlight(CGRect)
        case text(String, at: CGPoint)
        case step(Int, at: CGPoint) // centre of the badge
        case blur(CGRect)
    }

    var kind: Kind
    var color: NSColor
    var size: MarkupSize

    private var lineWidth: CGFloat { 4 * size.scale }
    private var stepRadius: CGFloat { 15 * size.scale }

    /// Blur has no colour; everything else can be recoloured after it's drawn.
    var hasColor: Bool { if case .blur = kind { false } else { true } }

    var stepNumber: Int? { if case .step(let n, _) = kind { n } else { nil } }

    var text: String? { if case .text(let s, _) = kind { s } else { nil } }

    /// The area the mark covers, used for the selection outline.
    var bounds: CGRect {
        switch kind {
        case let .arrow(from, to):
            return CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
                .insetBy(dx: -lineWidth * 3, dy: -lineWidth * 3)
        case let .box(r), let .highlight(r), let .blur(r):
            return r.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case let .pen(points):
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
                .insetBy(dx: -lineWidth, dy: -lineWidth)
        case let .text(s, origin):
            return CGRect(origin: origin, size: (s as NSString).size(withAttributes: Markup.textAttributes(color, size)))
        case let .step(_, c):
            return CGRect(x: c.x - stepRadius, y: c.y - stepRadius, width: stepRadius * 2, height: stepRadius * 2)
        }
    }

    /// Whether a click at `p` lands on this mark. With `outlineOnly`, filled areas (highlight, blur) only
    /// count near their edge, so you can still draw on top of them.
    func hit(_ p: CGPoint, outlineOnly: Bool) -> Bool {
        let tolerance = max(6, lineWidth)
        func nearSegment(_ a: CGPoint, _ b: CGPoint) -> Bool {
            let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)) <= tolerance
        }
        func nearEdge(_ r: CGRect) -> Bool {
            r.insetBy(dx: -tolerance, dy: -tolerance).contains(p) && !r.insetBy(dx: tolerance, dy: tolerance).contains(p)
        }
        switch kind {
        case let .arrow(from, to): return nearSegment(from, to)
        case let .box(r): return nearEdge(r)
        case let .pen(points): return zip(points, points.dropFirst()).contains { nearSegment($0, $1) }
        case let .highlight(r), let .blur(r): return outlineOnly ? nearEdge(r) : r.contains(p)
        case .text, .step: return bounds.insetBy(dx: -3, dy: -3).contains(p)
        }
    }

    mutating func move(by dx: CGFloat, _ dy: CGFloat) {
        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }
        switch kind {
        case let .arrow(from, to): kind = .arrow(from: m(from), to: m(to))
        case let .box(r): kind = .box(r.offsetBy(dx: dx, dy: dy))
        case let .pen(points): kind = .pen(points.map(m))
        case let .highlight(r): kind = .highlight(r.offsetBy(dx: dx, dy: dy))
        case let .text(s, origin): kind = .text(s, at: m(origin))
        case let .step(n, c): kind = .step(n, at: m(c))
        case let .blur(r): kind = .blur(r.offsetBy(dx: dx, dy: dy))
        }
    }

    /// Draws into the current graphics context, in overlay view coordinates.
    func draw(pixelated: CGImage?, viewBounds: CGRect) {
        switch kind {
        case let .arrow(from, to):
            let dx = to.x - from.x, dy = to.y - from.y
            let length = hypot(dx, dy)
            guard length > 1 else { return }
            let head = min(22 * size.scale, length * 0.6)
            let ux = dx / length, uy = dy / length
            let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
            let half = head * 0.55
            color.set()
            let shaft = NSBezierPath()
            shaft.move(to: from)
            shaft.line(to: base)
            shaft.lineWidth = lineWidth
            shaft.lineCapStyle = .round
            shaft.stroke()
            let tip = NSBezierPath()
            tip.move(to: to)
            tip.line(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
            tip.line(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
            tip.close()
            tip.lineJoinStyle = .round
            tip.lineWidth = 2
            tip.fill()
            tip.stroke()
        case let .box(rect):
            color.setStroke()
            let p = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            p.lineWidth = lineWidth
            p.stroke()
        case let .pen(points):
            guard let first = points.first else { return }
            let p = NSBezierPath()
            p.move(to: first)
            points.dropFirst().forEach { p.line(to: $0) }
            p.lineWidth = lineWidth
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            color.setStroke()
            p.stroke()
        case let .highlight(rect):
            // Multiply keeps the text underneath readable, like a real highlighter.
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.saveGState()
            ctx.setBlendMode(.multiply)
            color.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            ctx.restoreGState()
        case let .text(string, origin):
            (string as NSString).draw(at: origin, withAttributes: Markup.textAttributes(color, size))
        case let .step(n, c):
            let r = stepRadius
            let disc = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            color.setFill()
            disc.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            disc.lineWidth = max(1.5, 2 * size.scale)
            disc.stroke()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: r * 1.15, weight: .heavy),
                .foregroundColor: Markup.isLight(color) ? NSColor.black : NSColor.white,
            ]
            let label = "\(n)" as NSString
            let s = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: c.x - s.width / 2, y: c.y - s.height / 2), withAttributes: attrs)
        case let .blur(rect):
            guard let pixelated, let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.draw(pixelated, in: viewBounds)
            ctx.restoreGState()
        }
    }
}

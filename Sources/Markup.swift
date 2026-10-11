import AppKit
import Carbon.HIToolbox
import CoreImage

// MARK: - Quick markup: arrows, boxes, text and blur drawn on a selection

enum MarkupTool: CaseIterable {
    case arrow, box, text, blur

    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .box: "rectangle"
        case .text: "textformat"
        case .blur: "drop.halffull"
        }
    }

    var name: String {
        switch self {
        case .arrow: "Arrow (A)"
        case .box: "Box (R)"
        case .text: "Text (T)"
        case .blur: "Blur (B)"
        }
    }

    init?(keyCode: Int) {
        switch keyCode {
        case kVK_ANSI_A: self = .arrow
        case kVK_ANSI_R: self = .box
        case kVK_ANSI_T: self = .text
        case kVK_ANSI_B: self = .blur
        default: return nil
        }
    }
}

enum Markup {
    static let colors: [NSColor] = [.systemRed, .systemYellow, .systemBlue, .black, .white]
    static let lineWidth: CGFloat = 4
    static let font = NSFont.systemFont(ofSize: 22, weight: .bold)

    static func textAttributes(_ color: NSColor) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = (color == .black ? NSColor.white : NSColor.black).withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 3
        return [.font: font, .foregroundColor: color, .shadow: shadow]
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

enum Annotation {
    case arrow(from: CGPoint, to: CGPoint, color: NSColor)
    case box(CGRect, color: NSColor)
    case text(String, at: CGPoint, color: NSColor)
    case blur(CGRect)

    /// Draws into the current graphics context, in overlay view coordinates.
    func draw(pixelated: CGImage?, viewBounds: CGRect) {
        switch self {
        case let .arrow(from, to, color):
            let dx = to.x - from.x, dy = to.y - from.y
            let length = hypot(dx, dy)
            guard length > 1 else { return }
            let head = min(22, length * 0.6)
            let ux = dx / length, uy = dy / length
            let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
            let half = head * 0.55
            color.set()
            let shaft = NSBezierPath()
            shaft.move(to: from)
            shaft.line(to: base)
            shaft.lineWidth = Markup.lineWidth
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
        case let .box(rect, color):
            color.setStroke()
            let p = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            p.lineWidth = Markup.lineWidth
            p.stroke()
        case let .text(string, origin, color):
            (string as NSString).draw(at: origin, withAttributes: Markup.textAttributes(color))
        case let .blur(rect):
            guard let pixelated, let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.draw(pixelated, in: viewBounds)
            ctx.restoreGState()
        }
    }
}

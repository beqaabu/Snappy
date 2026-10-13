import AppKit
import Carbon.HIToolbox

// MARK: - Overlay window

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct WindowTarget {
    let id: CGWindowID
    let rect: CGRect // in overlay view coordinates
}

final class OverlayView: NSView {
    let image: CGImage
    let windows: [WindowTarget] // front-to-back
    var onCapture: (CGImage) -> Void = { _ in }
    var onCopyText: (CGImage) -> Void = { _ in }
    var onCaptureScreen: () -> Void = {}
    var onCaptureWindow: (CGWindowID) -> Void = { _ in }
    var onCancel: () -> Void = {}

    private enum Mode { case selection, window }
    private enum Tool { case selection, screen, window, close }
    private var mode: Mode = .selection
    private var hoveredWindow: WindowTarget?

    private(set) var selection: CGRect = .zero
    private enum Drag {
        case none, create(start: CGPoint), move(offset: CGPoint), resize(left: Bool, right: Bool, bottom: Bool, top: Bool)
        case draw(start: CGPoint), moveMark(index: Int, last: CGPoint, moved: Bool)
    }
    private var drag: Drag = .none
    private let handleSize: CGFloat = 10

    // Markup
    private enum BarItem { case tool(MarkupTool), size, color(Int), undo, copyText, capture }
    private var tool: MarkupTool?
    private var colorIndex = 0
    private var color: NSColor { Markup.colors[colorIndex] }
    private var size: MarkupSize = .medium
    private var annotations: [Annotation] = []
    private var history: [[Annotation]] = [] // snapshots for undo
    private var selectedMark: Int?
    private var draft: Annotation?
    private var textField: NSTextField?
    private var textFieldSize: MarkupSize = .medium
    private var hoverLabel: (text: String, rect: CGRect)?
    private var editingExistingText = false // the undo step was already recorded when editing began
    private lazy var pixelatedImage = Markup.pixelated(image, pointScale: CGFloat(image.width) / bounds.width)

    init(frame: CGRect, image: CGImage, windows: [WindowTarget], selection: CGRect? = nil) {
        self.image = image
        self.windows = windows
        super.init(frame: frame)
        if let selection, bounds.contains(selection) { self.selection = selection }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry helpers

    private var hasSelection: Bool { selection.width >= 2 && selection.height >= 2 }

    private func window(at p: CGPoint) -> WindowTarget? { windows.first { $0.rect.contains(p) } }

    private var toolbarRect: CGRect {
        let w: CGFloat = 364, h: CGFloat = 56 // 3 buttons × 96 + close 44 + gaps
        return CGRect(x: bounds.midX - w / 2, y: 32, width: w, height: h)
    }

    // (tool, rect, SF symbol, label)
    private func toolbarItems() -> [(Tool, CGRect, String, String)] {
        let bar = toolbarRect
        var x = bar.minX + 6
        func item(_ w: CGFloat) -> CGRect { defer { x += w + 6 }; return CGRect(x: x, y: bar.minY + 6, width: w, height: bar.height - 12) }
        return [
            (.selection, item(96), "rectangle.dashed", "Selection"),
            (.screen, item(96), "display", "Screen"),
            (.window, item(96), "macwindow", "Window"),
            (.close, CGRect(x: bar.maxX - 50, y: bar.minY + 6, width: 44, height: bar.height - 12), "xmark", ""),
        ]
    }

    /// The bar attached to the selection: markup tools, colors, undo and the capture button.
    private func selectionBar() -> (rect: CGRect, items: [(BarItem, CGRect)]) {
        let h: CGFloat = 44
        var items: [(BarItem, CGRect)] = []
        var x: CGFloat = 6
        func add(_ item: BarItem, _ size: CGFloat, gap: CGFloat = 2) {
            items.append((item, CGRect(x: x, y: (h - size) / 2, width: size, height: size)))
            x += size + gap
        }
        for t in MarkupTool.allCases { add(.tool(t), 32) }
        x += 8
        add(.size, 32)
        x += 6
        for i in Markup.colors.indices { add(.color(i), 24) }
        x += 8
        add(.undo, 32, gap: 2)
        add(.copyText, 32, gap: 6)
        add(.capture, 36, gap: 0)
        let w = x + 6

        let gap: CGFloat = 12
        var rect = CGRect(x: selection.midX - w / 2, y: selection.minY - gap - h, width: w, height: h) // below
        rect.origin.x = min(max(rect.minX, 8), bounds.maxX - w - 8)
        if rect.minY < 8 || rect.intersects(toolbarRect) { rect.origin.y = selection.maxY + gap }      // or above
        if rect.maxY > bounds.maxY - 8 { rect.origin.y = selection.maxY - gap - h }                    // or inside
        return (rect, items.map { ($0.0, $0.1.offsetBy(dx: rect.minX, dy: rect.minY)) })
    }

    private func handleRects() -> [(CGRect, Bool, Bool, Bool, Bool)] {
        let s = selection, h = handleSize
        func r(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x - h / 2, y: y - h / 2, width: h, height: h) }
        // (rect, left, right, bottom, top)
        return [
            (r(s.minX, s.minY), true, false, true, false),
            (r(s.maxX, s.minY), false, true, true, false),
            (r(s.minX, s.maxY), true, false, false, true),
            (r(s.maxX, s.maxY), false, true, false, true),
            (r(s.midX, s.minY), false, false, true, false),
            (r(s.midX, s.maxY), false, false, false, true),
            (r(s.minX, s.midY), true, false, false, false),
            (r(s.maxX, s.midY), false, true, false, false),
        ]
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(image, in: bounds)

        // Dim everything except the selection (or hovered window).
        let hole: CGRect? = mode == .window ? hoveredWindow?.rect : (hasSelection ? selection : nil)
        ctx.saveGState()
        ctx.addRect(bounds)
        if let hole { ctx.addRect(hole) }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        defer { drawToolbar(); drawHoverLabel() }

        if mode == .window {
            if let r = hoveredWindow?.rect {
                NSColor.systemBlue.setStroke()
                let p = NSBezierPath(rect: r.insetBy(dx: 1.5, dy: 1.5))
                p.lineWidth = 3
                p.stroke()
            } else {
                drawHint("Click a window to capture it  ·  Esc to cancel")
            }
            return
        }

        guard hasSelection else {
            drawHint("Drag to select an area  ·  Esc to cancel")
            return
        }

        drawAnnotations()

        // Border + handles.
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
        for (rect, _, _, _, _) in handleRects() {
            let p = NSBezierPath(ovalIn: rect)
            NSColor.white.setFill(); p.fill()
            NSColor.systemBlue.setStroke(); p.lineWidth = 1.5; p.stroke()
        }

        // Size label.
        let scale = CGFloat(image.width) / bounds.width
        let label = "\(Int(selection.width * scale)) × \(Int(selection.height * scale))"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let size = (label as NSString).size(withAttributes: attrs)
        var bg = CGRect(x: selection.minX, y: selection.maxY + 6, width: size.width + 12, height: size.height + 4)
        // Off the top of the screen, or under the markup bar? Tuck it inside the selection's top-left corner.
        if bg.maxY > bounds.maxY || bg.insetBy(dx: -4, dy: -4).intersects(selectionBar().rect) {
            bg.origin = CGPoint(x: selection.minX + 6, y: selection.maxY - bg.height - 6)
        }
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        (label as NSString).draw(at: CGPoint(x: bg.minX + 6, y: bg.minY + 2), withAttributes: attrs)

        drawSelectionBar()
    }

    private func drawAnnotations() {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selection).addClip()
        for a in annotations { a.draw(pixelated: pixelatedImage, viewBounds: bounds) }
        draft?.draw(pixelated: pixelatedImage, viewBounds: bounds)
        if let i = selectedMark, annotations.indices.contains(i) {
            // Marching-ants outline around the selected mark: white under black dashes reads on any background.
            let outline = NSBezierPath(roundedRect: annotations[i].bounds.insetBy(dx: -4, dy: -4), xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.5
            NSColor.white.setStroke(); outline.stroke()
            outline.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.black.setStroke(); outline.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSymbol(_ name: String, in rect: CGRect, size: CGFloat, color: NSColor = .white) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold).applying(.init(paletteColors: [color]))
        guard let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        icon.draw(in: CGRect(x: rect.midX - icon.size.width / 2, y: rect.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
    }

    private func drawSelectionBar() {
        let bar = selectionBar()
        if let tool { drawToolHint(tool.hint, near: bar.rect) }
        NSColor(white: 0.12, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: bar.rect, xRadius: 12, yRadius: 12).fill()
        for (item, r) in bar.items {
            switch item {
            case .tool(let t):
                if t == tool {
                    NSColor.white.withAlphaComponent(0.22).setFill()
                    NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
                }
                drawSymbol(t.symbol, in: r, size: 14)
            case .color(let i):
                Markup.colors[i].setFill()
                NSBezierPath(ovalIn: r.insetBy(dx: 4, dy: 4)).fill()
                NSColor.white.withAlphaComponent(i == colorIndex ? 1 : 0.35).setStroke()
                let ring = NSBezierPath(ovalIn: r.insetBy(dx: i == colorIndex ? 1.5 : 4, dy: i == colorIndex ? 1.5 : 4))
                ring.lineWidth = i == colorIndex ? 2 : 1
                ring.stroke()
            case .size:
                // A dot that grows with the size; click cycles small → medium → large.
                let d: CGFloat = [6, 10, 15][size.rawValue]
                NSColor.white.setFill()
                NSBezierPath(ovalIn: CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d)).fill()
            case .undo:
                drawSymbol("arrow.uturn.backward", in: r, size: 13, color: .white.withAlphaComponent(history.isEmpty && textField == nil ? 0.3 : 1))
            case .copyText:
                drawSymbol("text.viewfinder", in: r, size: 14)
            case .capture:
                NSColor.systemBlue.setFill()
                NSBezierPath(ovalIn: r).fill()
                drawSymbol("camera.fill", in: r, size: 14)
            }
        }
    }

    /// A small caption on the far side of the markup bar from the selection, saying what the active tool does.
    private func drawToolHint(_ text: String, near bar: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let barBelowSelection = bar.maxY <= selection.minY
        var pill = CGRect(x: bar.midX - size.width / 2 - 10, y: barBelowSelection ? bar.minY - size.height - 14 : bar.maxY + 6,
                          width: size.width + 20, height: size.height + 8)
        pill.origin.x = min(max(pill.minX, 8), bounds.maxX - pill.width - 8)
        if pill.minY < 4 || pill.maxY > bounds.maxY - 4 { return }
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 10, y: pill.minY + 4), withAttributes: attrs)
    }

    private func drawHint(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let bg = CGRect(x: bounds.midX - size.width / 2 - 14, y: bounds.midY - size.height / 2 - 8, width: size.width + 28, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 10, yRadius: 10).fill()
        (text as NSString).draw(at: CGPoint(x: bg.minX + 14, y: bg.minY + 8), withAttributes: attrs)
    }

    private func drawToolbar() {
        NSColor(white: 0.12, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: toolbarRect, xRadius: 14, yRadius: 14).fill()

        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        for (tool, rect, symbol, label) in toolbarItems() {
            let active = (tool == .selection && mode == .selection) || (tool == .window && mode == .window)
            if active {
                NSColor.white.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
            }
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium).applying(.init(paletteColors: [.white]))
            guard let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(config) else { continue }
            let iconY = label.isEmpty ? rect.midY - icon.size.height / 2 : rect.midY - 1
            icon.draw(in: CGRect(x: rect.midX - icon.size.width / 2, y: iconY, width: icon.size.width, height: icon.size.height))
            if !label.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                let size = (label as NSString).size(withAttributes: attrs)
                (label as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.minY + 4), withAttributes: attrs)
            }
        }
    }

    private func setMode(_ m: Mode) {
        endText(keep: true)
        mode = m
        drag = .none
        hoveredWindow = m == .window ? window(at: convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)) : nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func use(_ tool: Tool) {
        switch tool {
        case .selection: setMode(.selection)
        case .window: setMode(.window)
        case .screen: onCaptureScreen()
        case .close: onCancel()
        }
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let label = buttonLabels().first { $0.rect.contains(p) }
        if label?.text != hoverLabel?.text || label?.rect != hoverLabel?.rect {
            hoverLabel = label
            needsDisplay = true
        }
        guard mode == .window else { return }
        let hovered = toolbarRect.contains(p) ? nil : window(at: p)
        if hovered?.id != hoveredWindow?.id {
            hoveredWindow = hovered
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        hoverLabel = nil
        endText(keep: true)
        if let (tool, _, _, _) = toolbarItems().first(where: { $0.1.contains(p) }) { use(tool); return }
        if toolbarRect.contains(p) { return }
        if mode == .window {
            if let w = window(at: p) { onCaptureWindow(w.id) }
            return
        }
        if hasSelection {
            let bar = selectionBar()
            if let (item, _) = bar.items.first(where: { $0.1.contains(p) }) { use(item); return }
            if bar.rect.contains(p) { return }
            for (rect, l, r, b, t) in handleRects() where rect.insetBy(dx: -4, dy: -4).contains(p) {
                drag = .resize(left: l, right: r, bottom: b, top: t); return
            }
            if selection.contains(p), let i = annotations.indices.reversed().first(where: { annotations[$0].hit(p, outlineOnly: tool != nil) }) {
                if event.clickCount == 2, let text = annotations[i].text {
                    // Double-click a text mark to edit it.
                    let mark = annotations[i]
                    change { annotations.remove(at: i) }
                    selectedMark = nil
                    beginText(at: mark.bounds.origin, text: text, color: mark.color, size: mark.size, exactOrigin: true)
                    editingExistingText = true
                    return
                }
                selectedMark = i
                drag = .moveMark(index: i, last: p, moved: false)
                needsDisplay = true
                return
            }
            selectedMark = nil
            if let tool, selection.contains(p) {
                switch tool {
                case .text: beginText(at: p, text: "", color: color, size: size)
                case .step:
                    let next = (annotations.compactMap(\.stepNumber).max() ?? 0) + 1
                    change { annotations.append(Annotation(kind: .step(next, at: p), color: color, size: size)) }
                default: drag = .draw(start: p)
                }
                needsDisplay = true
                return
            }
            if event.clickCount == 2 && selection.contains(p) { capture(); return }
            if selection.contains(p) {
                drag = .move(offset: CGPoint(x: p.x - selection.minX, y: p.y - selection.minY)); return
            }
        }
        selectedMark = nil
        drag = .create(start: p)
        selection = CGRect(origin: p, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        var p = convert(event.locationInWindow, from: nil)
        p.x = min(max(p.x, 0), bounds.maxX); p.y = min(max(p.y, 0), bounds.maxY)
        switch drag {
        case .none: return
        case .create(let start):
            selection = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        case .move(let off):
            var o = CGPoint(x: p.x - off.x, y: p.y - off.y)
            o.x = min(max(o.x, 0), bounds.maxX - selection.width)
            o.y = min(max(o.y, 0), bounds.maxY - selection.height)
            selection.origin = o
        case .resize(let l, let r, let b, let t):
            var minX = selection.minX, maxX = selection.maxX, minY = selection.minY, maxY = selection.maxY
            if l { minX = p.x }; if r { maxX = p.x }; if b { minY = p.y }; if t { maxY = p.y }
            // Allow dragging past the opposite edge by flipping which edge is moving.
            let flipX = minX > maxX, flipY = minY > maxY
            selection = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
            if flipX || flipY { drag = .resize(left: flipX ? !l : l, right: flipX ? !r : r, bottom: flipY ? !b : b, top: flipY ? !t : t) }
        case .draw(let start):
            let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            let kind: Annotation.Kind?
            switch tool {
            case .arrow: kind = .arrow(from: start, to: p)
            case .box: kind = .box(rect)
            case .highlight: kind = .highlight(rect)
            case .blur: kind = .blur(rect)
            case .pen:
                if case .pen(let points)? = draft?.kind { kind = .pen(points + [p]) } else { kind = .pen([start, p]) }
            case .text, .step, nil: kind = nil
            }
            draft = kind.map { Annotation(kind: $0, color: color, size: size) }
        case .moveMark(let i, let last, let moved):
            if !moved { history.append(annotations) } // one undo step per drag
            annotations[i].move(by: p.x - last.x, p.y - last.y)
            drag = .moveMark(index: i, last: p, moved: true)
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        if case .draw(let start) = drag, let d = draft {
            let p = convert(event.locationInWindow, from: nil)
            let bigEnough: Bool
            if case .pen(let points) = d.kind { bigEnough = points.count > 2 } else { bigEnough = hypot(p.x - start.x, p.y - start.y) > 4 }
            if bigEnough { change { annotations.append(d) } }
        }
        draft = nil
        drag = .none
        if !hasSelection { selection = .zero }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func rightMouseDown(with event: NSEvent) { onCancel() }

    override func resetCursorRects() {
        defer { addCursorRect(toolbarRect, cursor: .arrow) }
        if mode == .window { addCursorRect(bounds, cursor: .pointingHand); return }
        addCursorRect(bounds, cursor: .crosshair)
        guard hasSelection else { return }
        addCursorRect(selection, cursor: tool == nil ? .openHand : tool == .text ? .iBeam : .crosshair)
        for (rect, _, _, _, _) in handleRects() { addCursorRect(rect.insetBy(dx: -4, dy: -4), cursor: .pointingHand) }
        addCursorRect(selectionBar().rect, cursor: .arrow)
    }

    /// What each button does, shown in a label as soon as you hover it.
    private func buttonLabels() -> [(text: String, rect: CGRect)] {
        let keys = ["Selection": "S", "Screen": "C", "Window": "W", "3s Timer": "D"]
        var labels = toolbarItems().map { item -> (text: String, rect: CGRect) in
            let label = item.3
            return (label.isEmpty ? "Cancel (Esc)" : "\(label) (\(keys[label] ?? ""))", item.1)
        }
        guard mode == .selection, hasSelection else { return labels }
        for (item, rect) in selectionBar().items {
            let text: String
            switch item {
            case .tool(let t): text = t.name
            case .size: text = "Size: \(["small", "medium", "large"][size.rawValue])"
            case .color: text = "Colour"
            case .undo: text = "Undo (⌘Z)"
            case .copyText: text = "Copy text (⌘C)"
            case .capture: text = "Capture (Return)"
            }
            labels.append((text, rect))
        }
        return labels
    }

    private func drawHoverLabel() {
        guard let (text, rect) = hoverLabel else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        var pill = CGRect(x: rect.midX - size.width / 2 - 8, y: rect.maxY + 8, width: size.width + 16, height: size.height + 8)
        if pill.maxY > bounds.maxY - 4 { pill.origin.y = rect.minY - pill.height - 8 } // no room above: show below
        pill.origin.x = min(max(pill.minX, 4), bounds.maxX - pill.width - 4)
        NSColor(white: 0.05, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 4), withAttributes: attrs)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch Int(event.keyCode) {
            case kVK_ANSI_Z: use(.undo)
            case kVK_ANSI_C where mode == .selection && hasSelection: use(.copyText)
            default: super.keyDown(with: event)
            }
            return
        }
        if mode == .selection, hasSelection, let t = MarkupTool(keyCode: Int(event.keyCode)) { use(.tool(t)); return }
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            if let i = selectedMark { change { annotations.remove(at: i) }; selectedMark = nil }
        case kVK_Escape:
            if selectedMark != nil { selectedMark = nil; needsDisplay = true } else { onCancel() }
        case kVK_ANSI_S: use(.selection)
        case kVK_ANSI_C: use(.screen)
        case kVK_ANSI_W: use(.window)
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            if mode == .window { if let w = hoveredWindow { onCaptureWindow(w.id) } }
            else if hasSelection { capture() }
        default: super.keyDown(with: event)
        }
    }

    private func capture() {
        endText(keep: true)
        guard hasSelection else { return }
        if let shot = selectedImage() { onCapture(shot) }
    }

    /// The selection, cut from the marked-up screen at full pixel resolution.
    private func selectedImage() -> CGImage? {
        let scale = CGFloat(image.width) / bounds.width
        // CGImage origin is top-left; view origin is bottom-left.
        let px = CGRect(x: selection.minX * scale,
                        y: (bounds.height - selection.maxY) * scale,
                        width: selection.width * scale,
                        height: selection.height * scale).integral
        return composited()?.cropping(to: px)
    }

    /// Recognizes text in the selection instead of saving an image. Uses the marked-up image,
    /// so anything blurred stays unreadable.
    private func copyText() {
        endText(keep: true)
        guard hasSelection else { return }
        if let shot = selectedImage() { onCopyText(shot) }
    }

    /// The frozen screen with the markup drawn on top, at full pixel resolution.
    private func composited() -> CGImage? {
        guard !annotations.isEmpty else { return image }
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let scale = CGFloat(image.width) / bounds.width
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for a in annotations { a.draw(pixelated: pixelatedImage, viewBounds: bounds) }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    // MARK: Markup

    /// Records an undo step, then applies a change to the marks.
    private func change(_ body: () -> Void) {
        history.append(annotations)
        body()
        needsDisplay = true
    }

    private func use(_ item: BarItem) {
        switch item {
        case .tool(let t):
            endText(keep: true)
            tool = tool == t ? nil : t
            selectedMark = nil
        case .size:
            size = size.next
            if let i = selectedMark { change { annotations[i].size = size } }
            if let field = textField { textFieldSize = size; field.font = Markup.font(size); resizeTextField() }
        case .color(let i):
            colorIndex = i
            textField?.textColor = color
            if let i = selectedMark, annotations[i].hasColor { change { annotations[i].color = color } }
        case .undo:
            if textField != nil { endText(keep: false) } else if let previous = history.popLast() { annotations = previous; selectedMark = nil }
        case .copyText:
            copyText()
            return
        case .capture:
            capture()
            return
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func textLineHeight(_ size: MarkupSize) -> CGFloat {
        ("Ag" as NSString).size(withAttributes: Markup.textAttributes(.white, size)).height
    }

    /// Opens a text field at `p` (centred on the click, or with its text origin exactly at `p` when editing).
    private func beginText(at p: CGPoint, text: String, color: NSColor, size: MarkupSize, exactOrigin: Bool = false) {
        let field = NSTextField(string: text)
        field.font = Markup.font(size)
        field.textColor = color
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.wantsLayer = true
        field.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        field.layer?.borderWidth = 1
        field.layer?.cornerRadius = 3
        field.delegate = self
        let h = textLineHeight(size)
        let origin = exactOrigin ? CGPoint(x: p.x - 2, y: p.y - 1) : CGPoint(x: p.x - 2, y: p.y - h / 2)
        field.frame = CGRect(origin: origin, size: CGSize(width: 60, height: h + 2))
        textFieldSize = size
        textField = field
        resizeTextField()
        addSubview(field)
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: text.utf16.count, length: 0)
    }

    private func resizeTextField() {
        guard let field = textField else { return }
        let attrs = Markup.textAttributes(.white, textFieldSize)
        let width = (field.stringValue as NSString).size(withAttributes: attrs).width
        field.frame.size = CGSize(width: max(60, width + 12), height: textLineHeight(textFieldSize) + 2)
    }

    /// Turns the open text field (if any) into a text annotation, or discards it.
    private func endText(keep: Bool) {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue
        if keep, !text.trimmingCharacters(in: .whitespaces).isEmpty, let c = field.textColor {
            let mark = Annotation(kind: .text(text, at: CGPoint(x: field.frame.minX + 2, y: field.frame.minY + 1)), color: c, size: textFieldSize)
            if editingExistingText { annotations.append(mark) } else { change { annotations.append(mark) } }
        }
        editingExistingText = false
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}

extension OverlayView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { resizeTextField() }

    func controlTextDidEndEditing(_ obj: Notification) { endText(keep: true) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)): endText(keep: false); return true
        case #selector(NSResponder.insertNewline(_:)): endText(keep: true); return true
        default: return false
        }
    }
}

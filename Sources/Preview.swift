import AppKit

// MARK: - Floating preview shown after a capture
//
// Sits in the bottom-right corner for a few seconds. Click to open the file,
// drag it into another app, or hover and click the X to dismiss.

final class PreviewPanel: NSPanel {
    private static var current: PreviewPanel?
    private static let visibleFor: TimeInterval = 5

    private var timer: Timer?

    static func show(image: CGImage, file: URL, on screen: NSScreen) {
        current?.dismiss()
        let panel = PreviewPanel(image: image, file: file, screen: screen)
        current = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        panel.startTimer()
    }

    static func dismissCurrent() { current?.dismiss(animated: false) }

    private init(image: CGImage, file: URL, screen: NSScreen) {
        let maxSize = CGSize(width: 220, height: 160)
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let scale = min(maxSize.width / w, maxSize.height / h, 1 / screen.backingScaleFactor)
        let size = CGSize(width: max(w * scale, 60), height: max(h * scale, 40))
        let margin: CGFloat = 20
        let frame = CGRect(x: screen.visibleFrame.maxX - size.width - margin,
                           y: screen.visibleFrame.minY + margin,
                           width: size.width, height: size.height)

        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovableByWindowBackground = false

        let view = PreviewView(frame: CGRect(origin: .zero, size: size), image: image, file: file)
        view.onDismiss = { [weak self] in self?.dismiss() }
        view.onHover = { [weak self] inside in inside ? self?.stopTimer() : self?.startTimer() }
        contentView = view
    }

    override var canBecomeKey: Bool { false }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.visibleFor, repeats: false) { [weak self] _ in self?.dismiss() }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func dismiss(animated: Bool = true) {
        stopTimer()
        if Self.current === self { Self.current = nil }
        guard animated else { orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; animator().alphaValue = 0 }) { self.orderOut(nil) }
    }
}

private final class PreviewView: NSView, NSDraggingSource {
    let image: CGImage
    let file: URL
    var onDismiss: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }

    private var hovering = false
    private var mouseDownAt: CGPoint?
    private let radius: CGFloat = 8

    init(frame: CGRect, image: CGImage, file: URL) {
        self.image = image
        self.file = file
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var closeRect: CGRect { CGRect(x: 6, y: bounds.maxY - 26, width: 20, height: 20) }

    override func draw(_ dirtyRect: NSRect) {
        let clip = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        NSGraphicsContext.current?.cgContext.draw(image, in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: radius - 1, yRadius: radius - 1)
        border.lineWidth = 3
        border.stroke()

        guard hovering else { return }
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(ovalIn: closeRect).fill()
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold).applying(.init(paletteColors: [.white]))
        if let x = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")?.withSymbolConfiguration(config) {
            x.draw(in: CGRect(x: closeRect.midX - x.size.width / 2, y: closeRect.midY - x.size.height / 2, width: x.size.width, height: x.size.height))
        }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true; onHover(true) }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true; onHover(false) }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hovering && closeRect.insetBy(dx: -4, dy: -4).contains(p) { onDismiss(); return }
        mouseDownAt = p
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownAt else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - start.x, p.y - start.y) > 3 else { return }
        mouseDownAt = nil
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        item.setDraggingFrame(bounds, contents: NSImage(cgImage: image, size: bounds.size))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownAt != nil else { return }
        mouseDownAt = nil
        NSWorkspace.shared.open(file)
        onDismiss()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { onDismiss() }
    }
}

// MARK: - Small notice in the same corner, e.g. after copying text

final class ToastPanel: NSPanel {
    private static var current: ToastPanel?

    static func show(_ title: String, detail: String?, symbol: String, on screen: NSScreen) {
        PreviewPanel.dismissCurrent()
        current?.orderOut(nil)
        let panel = ToastPanel(title: title, detail: detail, symbol: symbol, screen: screen)
        current = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak panel] in
            guard let panel, current === panel else { return }
            current = nil
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }) { panel.orderOut(nil) }
        }
    }

    private init(title: String, detail: String?, symbol: String, screen: NSScreen) {
        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .white
        // At most two short lines, so long copies don't make a huge notice.
        let lines = (detail ?? "").split(separator: "\n", omittingEmptySubsequences: true)
        var shown = lines.prefix(2).map { $0.count > 48 ? $0.prefix(47) + "…" : String($0) }.joined(separator: "\n")
        if lines.count > 2 { shown += " …" }
        let detailField = NSTextField(labelWithString: shown)
        detailField.font = .systemFont(ofSize: 12)
        detailField.textColor = NSColor.white.withAlphaComponent(0.75)
        detailField.isHidden = detail == nil
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 18, weight: .medium).applying(.init(paletteColors: [.white])))!)

        let text = NSStackView(views: [titleField, detailField])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [icon, text])
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 16)

        let size = row.fittingSize
        let margin: CGFloat = 20
        let frame = CGRect(x: screen.visibleFrame.maxX - size.width - margin, y: screen.visibleFrame.minY + margin,
                           width: size.width, height: size.height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.appearance = NSAppearance(named: .darkAqua)
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        row.frame = background.bounds
        background.addSubview(row)
        contentView = background
    }

    override var canBecomeKey: Bool { false }
}

// MARK: - Countdown for delayed captures

final class CountdownPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")

    /// Shows 3, 2, 1 in the middle of `screen`, then hides and calls `done`.
    static func run(seconds: Int, on screen: NSScreen, done: @escaping () -> Void) {
        let panel = CountdownPanel(screen: screen)
        panel.orderFrontRegardless()
        func tick(_ remaining: Int) {
            guard remaining > 0 else {
                panel.orderOut(nil)
                // Give the window server a moment to remove the panel before the screen is captured.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: done)
                return
            }
            panel.label.stringValue = "\(remaining)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick(remaining - 1) }
        }
        tick(seconds)
    }

    private init(screen: NSScreen) {
        let size: CGFloat = 120
        let frame = CGRect(x: screen.frame.midX - size / 2, y: screen.frame.midY - size / 2, width: size, height: size)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        background.material = .hudWindow
        background.appearance = NSAppearance(named: .darkAqua)
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 28
        label.font = .monospacedDigitSystemFont(ofSize: 64, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = CGRect(x: 0, y: (size - 78) / 2, width: size, height: 78)
        background.addSubview(label)
        contentView = background
    }

    override var canBecomeKey: Bool { false }
}

// Snappy: a tiny Ubuntu-style screenshot tool for macOS.
// Press Cmd+Shift+2 (or use the menu bar icon), drag a region, move/resize it,
// then click the camera button (or press Return) to save + copy to clipboard.

import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import ServiceManagement

// MARK: - Global hotkey (Carbon, no Accessibility permission needed)

final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let me = Unmanaged<HotKey>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &spec, selfPtr, &handler)
        let id = EventHotKeyID(signature: OSType(0x534E4150), id: 1) // 'SNAP'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}

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
    var onCapture: (CGRect) -> Void = { _ in }
    var onCaptureScreen: () -> Void = {}
    var onCaptureWindow: (CGWindowID) -> Void = { _ in }
    var onCancel: () -> Void = {}

    private enum Mode { case selection, window }
    private enum Tool { case selection, screen, window, close }
    private var mode: Mode = .selection
    private var hoveredWindow: WindowTarget?

    private var selection: CGRect = .zero
    private enum Drag { case none, create(start: CGPoint), move(offset: CGPoint), resize(left: Bool, right: Bool, bottom: Bool, top: Bool) }
    private var drag: Drag = .none
    private let handleSize: CGFloat = 10
    private let buttonSize: CGFloat = 44

    init(frame: CGRect, image: CGImage, windows: [WindowTarget]) {
        self.image = image
        self.windows = windows
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry helpers

    private var hasSelection: Bool { selection.width >= 2 && selection.height >= 2 }

    private func window(at p: CGPoint) -> WindowTarget? { windows.first { $0.rect.contains(p) } }

    private var toolbarRect: CGRect {
        let w: CGFloat = 3 * 96 + 44 + 4 * 6 + 8, h: CGFloat = 56
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

    private var captureButtonRect: CGRect {
        let gap: CGFloat = 12
        var y = selection.minY - gap - buttonSize           // below the selection
        if y < 8 { y = selection.maxY + gap }                // or above
        if y + buttonSize > bounds.maxY - 8 { y = selection.minY + gap } // or inside
        var x = selection.midX - buttonSize / 2
        x = min(max(x, 8), bounds.maxX - buttonSize - 8)
        return CGRect(x: x, y: y, width: buttonSize, height: buttonSize)
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

        defer { drawToolbar() }

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
        var labelOrigin = CGPoint(x: selection.minX, y: selection.maxY + 6)
        if labelOrigin.y + size.height + 4 > bounds.maxY { labelOrigin.y = selection.maxY - size.height - 10 }
        let bg = CGRect(x: labelOrigin.x, y: labelOrigin.y, width: size.width + 12, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        (label as NSString).draw(at: CGPoint(x: bg.minX + 6, y: bg.minY + 2), withAttributes: attrs)

        // Capture button.
        let b = captureButtonRect
        NSColor.white.setFill()
        NSBezierPath(ovalIn: b).fill()
        NSColor.systemBlue.setFill()
        NSBezierPath(ovalIn: b.insetBy(dx: 4, dy: 4)).fill()
        if let cam = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Capture")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold).applying(.init(paletteColors: [.white]))) {
            let cs = cam.size
            cam.draw(in: CGRect(x: b.midX - cs.width / 2, y: b.midY - cs.height / 2, width: cs.width, height: cs.height))
        }
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
        guard mode == .window else { return }
        let p = convert(event.locationInWindow, from: nil)
        let hovered = toolbarRect.contains(p) ? nil : window(at: p)
        if hovered?.id != hoveredWindow?.id {
            hoveredWindow = hovered
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let (tool, _, _, _) = toolbarItems().first(where: { $0.1.contains(p) }) { use(tool); return }
        if toolbarRect.contains(p) { return }
        if mode == .window {
            if let w = window(at: p) { onCaptureWindow(w.id) }
            return
        }
        if hasSelection {
            if captureButtonRect.contains(p) { capture(); return }
            if event.clickCount == 2 && selection.contains(p) { capture(); return }
            for (rect, l, r, b, t) in handleRects() where rect.insetBy(dx: -4, dy: -4).contains(p) {
                drag = .resize(left: l, right: r, bottom: b, top: t); return
            }
            if selection.contains(p) {
                drag = .move(offset: CGPoint(x: p.x - selection.minX, y: p.y - selection.minY)); return
            }
        }
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
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
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
        addCursorRect(selection, cursor: .openHand)
        for (rect, _, _, _, _) in handleRects() { addCursorRect(rect.insetBy(dx: -4, dy: -4), cursor: .pointingHand) }
        addCursorRect(captureButtonRect, cursor: .pointingHand)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape: onCancel()
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
        guard hasSelection else { return }
        let scale = CGFloat(image.width) / bounds.width
        // CGImage origin is top-left; view origin is bottom-left.
        let px = CGRect(x: selection.minX * scale,
                        y: (bounds.height - selection.maxY) * scale,
                        width: selection.width * scale,
                        height: selection.height * scale).integral
        onCapture(px)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var overlay: OverlayWindow?
    private var loginItem: NSMenuItem!

    private var saveFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snappy")

        let menu = NSMenu()
        menu.addItem(withTitle: "Take Screenshot  (⌘⇧2)", action: #selector(start), keyEquivalent: "")
        menu.addItem(withTitle: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(.separator())
        loginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snappy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in self?.start() }

        // Trigger the Screen Recording permission prompt early on first launch.
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    @objc func start() {
        guard overlay == nil else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return }

        let windows = Self.windowTargets(on: displayID)

        Task { @MainActor in
            do {
                let image = try await Self.grab(displayID: displayID, screen: screen)
                self.showOverlay(on: screen, image: image, windows: windows)
            } catch {
                self.permissionAlert(error)
            }
        }
    }

    private static func grab(displayID: CGDirectDisplayID, screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "Snappy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Display not found"])
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * screen.backingScaleFactor)
        config.height = Int(screen.frame.height * screen.backingScaleFactor)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Normal app windows on this display, front-to-back, in overlay view coordinates.
    private static func windowTargets(on displayID: CGDirectDisplayID) -> [WindowTarget] {
        let display = CGDisplayBounds(displayID) // top-left origin, like window bounds
        let me = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? pid_t) != me,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict),
                  b.width > 40, b.height > 40, b.intersects(display)
            else { return nil }
            let rect = CGRect(x: b.minX - display.minX, y: display.height - (b.maxY - display.minY), width: b.width, height: b.height)
            return WindowTarget(id: id, rect: rect)
        }
    }

    private static func grabWindow(_ id: CGWindowID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let w = content.windows.first(where: { $0.windowID == id }) else {
            throw NSError(domain: "Snappy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Window not found"])
        }
        let filter = SCContentFilter(desktopIndependentWindow: w)
        let config = SCStreamConfiguration()
        config.width = Int(w.frame.width * CGFloat(filter.pointPixelScale))
        config.height = Int(w.frame.height * CGFloat(filter.pointPixelScale))
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func showOverlay(on screen: NSScreen, image: CGImage, windows: [WindowTarget]) {
        let win = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = true
        win.acceptsMouseMovedEvents = true
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.setFrame(screen.frame, display: false)

        let view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), image: image, windows: windows)
        view.onCancel = { [weak self] in self?.closeOverlay() }
        view.onCaptureScreen = { [weak self] in
            self?.closeOverlay()
            self?.save(image)
        }
        view.onCaptureWindow = { [weak self] id in
            self?.closeOverlay()
            Task { @MainActor in
                if let shot = try? await Self.grabWindow(id) { self?.save(shot) } else { NSSound.beep() }
            }
        }
        view.onCapture = { [weak self] rect in
            self?.closeOverlay()
            if let cropped = image.cropping(to: rect) { self?.save(cropped) }
        }
        win.contentView = view
        overlay = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
    }

    private func closeOverlay() {
        overlay?.orderOut(nil)
        overlay = nil
    }

    private func save(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }

        try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = saveFolder.appendingPathComponent("Screenshot \(f.string(from: Date())).png")
        try? png.write(to: url)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)

        let shutter = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif")
        (NSSound(contentsOf: shutter, byReference: true) ?? NSSound(named: "Grab"))?.play()
    }

    private func permissionAlert(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Snappy needs Screen Recording permission"
        alert.informativeText = "Enable Snappy in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen Snappy.\n\n(\(error.localizedDescription))"
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    @objc func openFolder() {
        try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(saveFolder)
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

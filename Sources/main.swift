// Snappy: a tiny Ubuntu-style screenshot tool for macOS.
// Press the shortcut (Cmd+Shift+2 by default, changeable in Settings) or use the menu bar icon,
// drag a region, move/resize it, then click the camera button (or press Return) to capture.

import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey!
    private var overlay: OverlayWindow?
    private var takeItem: NSMenuItem!
    private let settings = SettingsModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snappy")

        let menu = NSMenu()
        takeItem = menu.addItem(withTitle: "", action: #selector(start), keyEquivalent: "")
        menu.addItem(withTitle: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snappy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        hotKey = HotKey { [weak self] in self?.start() }
        settings.applyShortcut = { [weak self] shortcut in
            guard let self else { return false }
            self.updateMenu()
            return self.hotKey.register(shortcut)
        }
        settings.pauseShortcut = { [weak self] paused in
            guard let self else { return }
            if paused { self.hotKey.unregister() } else { self.hotKey.register(Prefs.shortcut) }
        }
        settings.shortcutFailed = !hotKey.register(Prefs.shortcut)
        updateMenu()
        UpdateCheck.scheduleAutomaticChecks()

        // Trigger the Screen Recording permission prompt early on first launch.
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    private let lastSelectionKey = "lastSelection"

    private func updateMenu() {
        takeItem.title = "Take Screenshot  (\(Prefs.shortcut.display))"
    }

    @objc func openSettings() { SettingsWindow.show(model: settings) }

    @objc func start() {
        guard overlay == nil else { return }
        PreviewPanel.dismissCurrent()
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
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
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

        let last = UserDefaults.standard.string(forKey: lastSelectionKey).map(NSRectFromString)
        let view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), image: image, windows: windows, selection: last)
        view.onCancel = { [weak self] in self?.closeOverlay() }
        view.onCaptureScreen = { [weak self] in
            self?.closeOverlay()
            self?.save(image, on: screen)
        }
        view.onCaptureWindow = { [weak self] id in
            self?.closeOverlay()
            Task { @MainActor in
                if let shot = try? await Self.grabWindow(id) { self?.save(shot, on: screen) } else { NSSound.beep() }
            }
        }
        view.onCopyText = { [weak self, weak view] shot in
            guard let self, let view else { return }
            UserDefaults.standard.set(NSStringFromRect(view.selection), forKey: self.lastSelectionKey)
            self.closeOverlay()
            TextRecognition.recognize(shot) { text in
                guard !text.isEmpty else {
                    Sounds.noText()
                    ToastPanel.show("No text found", detail: "Try a larger or sharper selection.", symbol: "text.viewfinder", on: screen)
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                Sounds.scan()
                let lines = text.split(separator: "\n").count
                ToastPanel.show("Copied \(lines) line\(lines == 1 ? "" : "s") of text", detail: text, symbol: "doc.on.clipboard", on: screen)
            }
        }
        view.onCapture = { [weak self, weak view] shot in
            guard let self, let view else { return }
            UserDefaults.standard.set(NSStringFromRect(view.selection), forKey: self.lastSelectionKey)
            self.closeOverlay()
            self.save(shot, on: screen)
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

    private func save(_ image: CGImage, on screen: NSScreen) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let format = Prefs.format
        let fileData = format == .png ? png : rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        guard let fileData else { return }

        // The preview needs a file to open and drag, so clipboard-only captures go to a temporary folder.
        let folder = Prefs.saveToFile ? Prefs.saveFolder : FileManager.default.temporaryDirectory.appendingPathComponent("Snappy")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = folder.appendingPathComponent("Screenshot \(f.string(from: Date())).\(format.fileExtension)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try fileData.write(to: url)
        } catch {
            if Prefs.saveToFile { saveFailedAlert(folder: folder, error: error); return }
        }

        if Prefs.copyToClipboard {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(png, forType: .png)
        }

        Sounds.shutter()

        if Prefs.showPreview, FileManager.default.fileExists(atPath: url.path) {
            PreviewPanel.show(image: image, file: url, on: screen)
        }
    }

    private func saveFailedAlert(folder: URL, error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Snappy couldn't save the screenshot"
        alert.informativeText = "Saving to \((folder.path as NSString).abbreviatingWithTildeInPath) failed: \(error.localizedDescription)\n\nChoose a different folder in Settings."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { openSettings() }
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
        let folder = Prefs.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

// Snappy: a tiny Ubuntu-style screenshot tool for macOS.
// Press Cmd+Shift+2 (or use the menu bar icon), drag a region, move/resize it,
// then click the camera button (or press Return) to save + copy to clipboard.

import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import ServiceManagement

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

    private let lastSelectionKey = "lastSelection"

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

        try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = saveFolder.appendingPathComponent("Screenshot \(f.string(from: Date())).png")
        do { try png.write(to: url) } catch { NSSound.beep(); return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)

        let shutter = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif")
        (NSSound(contentsOf: shutter, byReference: true) ?? NSSound(named: "Grab"))?.play()

        PreviewPanel.show(image: image, file: url, on: screen)
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

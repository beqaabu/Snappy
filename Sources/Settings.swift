import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

// MARK: - Stored preferences

enum ImageFormat: String {
    case png, jpeg
    var fileExtension: String { self == .png ? "png" : "jpg" }
}

enum Prefs {
    enum Key {
        static let shortcut = "shortcut"
        static let saveFolder = "saveFolder"
        static let format = "format"
        static let saveToFile = "saveToFile"
        static let copyToClipboard = "copyToClipboard"
        static let showPreview = "showPreview"
        static let playSound = "playSound"
    }

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [Key.format: ImageFormat.png.rawValue, Key.saveToFile: true,
                                     Key.copyToClipboard: true, Key.showPreview: true, Key.playSound: true])
    }

    static var shortcut: Shortcut {
        get { defaults.data(forKey: Key.shortcut).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.shortcut) }
    }

    static let defaultSaveFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots")

    static var saveFolder: URL {
        get { defaults.string(forKey: Key.saveFolder).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultSaveFolder }
        set { defaults.set(newValue == defaultSaveFolder ? nil : newValue.path, forKey: Key.saveFolder) }
    }

    static var format: ImageFormat { ImageFormat(rawValue: defaults.string(forKey: Key.format) ?? "") ?? .png }
    static var saveToFile: Bool { defaults.bool(forKey: Key.saveToFile) }
    static var copyToClipboard: Bool { defaults.bool(forKey: Key.copyToClipboard) }
    static var showPreview: Bool { defaults.bool(forKey: Key.showPreview) }
    static var playSound: Bool { defaults.bool(forKey: Key.playSound) }
}

// MARK: - Keyboard shortcut

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier mask
    var key: String       // how the key itself is shown, e.g. "2" or "F5"

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), key: "2")

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
    ]
    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    /// A shortcut from a key press, or nil if it isn't usable as a global shortcut.
    /// Needs ⌘, ⌃ or ⌥ (plain typing keys would hijack normal typing), except for function keys.
    init?(event: NSEvent) {
        let code = Int(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        let isFunctionKey = Self.functionKeys[code] != nil
        guard isFunctionKey || flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else { return nil }
        guard let key = Self.functionKeys[code] ?? Self.namedKeys[code] ?? Self.character(for: UInt16(code)) else { return nil }
        self.init(keyCode: UInt32(code), modifiers: mods, key: key)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// The unmodified character a key types in the current keyboard layout (so ⇧2 shows "2", not "@").
    private static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length).uppercased()
        return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
    }
}

// MARK: - Settings window

final class SettingsModel: ObservableObject {
    @Published private(set) var shortcut = Prefs.shortcut
    @Published var shortcutFailed = false
    @Published var saveFolder = Prefs.saveFolder

    /// Registers a shortcut globally; returns false if macOS refused it.
    var applyShortcut: (Shortcut) -> Bool = { _ in true }
    /// Called with true while the recorder is listening, so the current shortcut doesn't fire.
    var pauseShortcut: (Bool) -> Void = { _ in }

    func setShortcut(_ s: Shortcut) {
        shortcut = s
        Prefs.shortcut = s
        shortcutFailed = !applyShortcut(s)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveFolder
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveFolder = url
        Prefs.saveFolder = url
    }

    func resetFolder() {
        saveFolder = Prefs.defaultSaveFolder
        Prefs.saveFolder = Prefs.defaultSaveFolder
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Prefs.Key.format) private var format = ImageFormat.png.rawValue
    @AppStorage(Prefs.Key.saveToFile) private var saveToFile = true
    @AppStorage(Prefs.Key.copyToClipboard) private var copyToClipboard = true
    @AppStorage(Prefs.Key.showPreview) private var showPreview = true
    @AppStorage(Prefs.Key.playSound) private var playSound = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                LabeledContent("Screenshot shortcut") {
                    ShortcutRecorder(shortcut: model.shortcut, onRecord: model.setShortcut, onListening: model.pauseShortcut)
                }
                if model.shortcutFailed {
                    Text("macOS wouldn't register this shortcut. Another app may be using it; try a different one.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("After capturing") {
                // At least one destination must stay on.
                Toggle("Save to a file", isOn: $saveToFile).disabled(saveToFile && !copyToClipboard)
                Toggle("Copy to the clipboard", isOn: $copyToClipboard).disabled(copyToClipboard && !saveToFile)
                Toggle("Show a preview in the corner", isOn: $showPreview)
                Toggle("Play the shutter sound", isOn: $playSound)
            }

            Section("Files") {
                LabeledContent("Save to") {
                    HStack(spacing: 8) {
                        Text((model.saveFolder.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        if model.saveFolder != Prefs.defaultSaveFolder {
                            Button { model.resetFolder() } label: { Image(systemName: "arrow.uturn.backward") }
                                .buttonStyle(.borderless)
                                .help("Reset to ~/Pictures/Screenshots")
                        }
                        Button("Choose…") { model.chooseFolder() }
                    }
                }
                Picker("Format", selection: $format) {
                    Text("PNG").tag(ImageFormat.png.rawValue)
                    Text("JPEG").tag(ImageFormat.jpeg.rawValue)
                }
            }
            .disabled(!saveToFile)

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch { NSSound.beep() }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A button that shows the shortcut and, when clicked, records the next key combination.
struct ShortcutRecorder: View {
    let shortcut: Shortcut
    let onRecord: (Shortcut) -> Void
    let onListening: (Bool) -> Void
    @State private var listening = false
    @State private var monitor: Any?

    var body: some View {
        Button { listening ? stop() : start() } label: {
            Text(listening ? "Type a shortcut…" : shortcut.display)
                .frame(minWidth: 110)
                .foregroundStyle(listening ? .secondary : .primary)
        }
        .help(listening ? "Press Esc to cancel" : "Click to change")
        .onDisappear { stop() }
    }

    private func start() {
        listening = true
        onListening(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape { stop(); return nil }
            if let s = Shortcut(event: event) {
                stop()
                onRecord(s)
            } else {
                NSSound.beep() // needs ⌘, ⌃ or ⌥ (or a function key)
            }
            return nil
        }
    }

    private func stop() {
        guard listening else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        listening = false
        onListening(false)
    }
}

enum SettingsWindow {
    private static var window: NSWindow?

    static func show(model: SettingsModel) {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            controller.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: controller)
            w.title = "Snappy Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

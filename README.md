# Snappy

A tiny, Ubuntu-style screenshot tool for macOS. Press one shortcut, pick an area, a window or the whole screen, and click once to capture.

- Lives in the menu bar, no Dock icon
- Freezes the screen while you choose, so menus and tooltips stay put
- Drag to select, then move or resize the selection before capturing
- One-click full-screen and single-window captures
- Remembers your last selection, so repeat shots of the same area take one click
- Saves a PNG to `~/Pictures/Screenshots` and copies it to the clipboard
- Shows a preview in the corner: click to open it, drag it into any app
- A few small Swift files, no dependencies

## Usage

Press **⌘⇧2** (or click the menu bar icon → Take Screenshot). A toolbar appears at the bottom of the screen:

| Button | Key | Action |
|---|---|---|
| Selection | `S` | Drag a box. Drag inside it to move, drag the handles to resize. |
| Screen | `C` | Capture the whole screen immediately. |
| Window | `W` | Hover a window to highlight it, click to capture it. |
| ✕ | `Esc` | Cancel (right-click also cancels). |

In Selection mode, click the blue camera button, press `Return`/`Space`, or double-click the selection to capture.

The capture covers the display the mouse pointer is on.

After each capture a thumbnail appears in the bottom-right corner for 5 seconds (it stays while you hover it). Click it to open the screenshot, drag it into another app to share it, or click its ✕ to dismiss.

## Install

Requires macOS 15.2 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/beqaabu/Snappy.git
cd Snappy
./build.sh --install
```

This builds `Snappy.app`, copies it to `/Applications` and launches it. Use `./build.sh` alone to only build into `build/`.

### Screen Recording permission

On first launch macOS asks for Screen Recording permission. Enable Snappy in **System Settings → Privacy & Security → Screen & System Audio Recording**, then quit and reopen Snappy.

The app is ad-hoc signed, so macOS may ask again after you rebuild it. Just re-enable it.

### Launch at login

Click the menu bar icon and enable **Launch at Login**.

## Customizing

The code is in [`Sources/`](Sources):

- **Shortcut:** the `HotKey(keyCode:modifiers:)` call in `applicationDidFinishLaunching` ([`main.swift`](Sources/main.swift))
- **Save folder:** `saveFolder` in `AppDelegate` ([`main.swift`](Sources/main.swift))
- **Sound:** `save(_:on:)` ([`main.swift`](Sources/main.swift))
- **Preview duration and size:** `visibleFor` and `maxSize` in [`Preview.swift`](Sources/Preview.swift)

## License

[MIT](LICENSE)

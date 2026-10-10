# Snappy

A tiny, Ubuntu-style screenshot tool for macOS. Press one shortcut, pick an area, a window or the whole screen, and click once to capture.

- Lives in the menu bar, no Dock icon
- Freezes the screen while you choose, so menus and tooltips stay put
- Drag to select, then move or resize the selection before capturing
- One-click full-screen and single-window captures
- Saves a PNG to `~/Pictures/Screenshots` and copies it to the clipboard
- One Swift file, no dependencies

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

## Install

Requires macOS 15.2 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/<your-username>/Snappy.git
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

Everything is in [`Snappy.swift`](Snappy.swift):

- **Shortcut:** the `HotKey(keyCode:modifiers:)` call in `applicationDidFinishLaunching`
- **Save folder:** `saveFolder` in `AppDelegate`
- **Sound:** `save(_:)`

## License

[MIT](LICENSE)

#!/bin/sh
# Builds Snappy.app into ./build. Usage: ./build.sh [--install]
set -e
cd "$(dirname "$0")"
APP=build/Snappy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macos15.2 Sources/*.swift -o "$APP/Contents/MacOS/Snappy"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Snappy</string>
  <key>CFBundleIdentifier</key><string>com.local.snappy</string>
  <key>CFBundleExecutable</key><string>Snappy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.2</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
if [ "$1" = "--install" ]; then
  pkill -x Snappy || true
  rm -rf /Applications/Snappy.app
  cp -R "$APP" /Applications/
  open /Applications/Snappy.app
  echo "Installed to /Applications/Snappy.app"
fi

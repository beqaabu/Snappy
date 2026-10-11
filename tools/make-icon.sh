#!/bin/zsh
# Regenerates Resources/AppIcon.icns (and docs/icon.png) from tools/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build/icon Resources docs
cp tools/make-icon.swift build/icon/main.swift
swiftc -O -o build/icon/make-icon build/icon/main.swift -framework Cocoa
./build/icon/make-icon build/icon
iconutil -c icns build/icon/AppIcon.iconset -o Resources/AppIcon.icns
sips -Z 256 build/icon/icon-preview.png --out docs/icon.png >/dev/null
echo "Wrote Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"

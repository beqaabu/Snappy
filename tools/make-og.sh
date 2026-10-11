#!/bin/zsh
# Regenerates site/og.png (the website's link preview) from tools/make-og.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/og
cp tools/make-og.swift build/og/main.swift
swiftc -O -o build/og/make-og build/og/main.swift -framework Cocoa
./build/og/make-og site/og.png

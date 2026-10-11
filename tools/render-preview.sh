#!/bin/zsh
# Renders docs/preview.png (the README image) from Snappy's real overlay over a mock desktop.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build docs
swiftc -swift-version 5 -o build/render-preview $(ls Sources/*.swift | grep -v main.swift) tools/preview/main.swift
build/render-preview docs/preview.png
sips -Z 1600 docs/preview.png >/dev/null # keep the README image light

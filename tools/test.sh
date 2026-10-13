#!/bin/zsh
# Runs the unit tests (plain assertions, no XCTest).
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
swiftc -swift-version 5 -o build/Tests $(ls Sources/*.swift | grep -v main.swift) Tests/main.swift
exec ./build/Tests

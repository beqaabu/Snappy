#!/bin/zsh
# Builds Snappy and packages it for a GitHub release:
#   dist/Snappy-<version>.zip  versioned archive
#   dist/Snappy.zip            same file, so releases/latest/download/Snappy.zip always works
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
rm -rf dist
mkdir -p dist
ZIP="dist/Snappy-$VERSION.zip"
ditto -c -k --keepParent build/Snappy.app "$ZIP"
cp "$ZIP" dist/Snappy.zip
echo "Packaged $ZIP"

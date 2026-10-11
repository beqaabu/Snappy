#!/bin/zsh
# Builds Snappy.app (universal, macOS 14+) into build/.
#
#   ./build.sh            build only
#   ./build.sh --install  also copy to /Applications and launch it
#
# The app is signed with a self-signed certificate, signing/id.p12 (created on first run if missing;
# CI restores it from a secret). A stable signature means the Screen Recording permission survives
# rebuilds and updates; ad-hoc signing would make macOS treat every build as a new app.
#
#   ADHOC=1  sign ad hoc instead (CI build checks, which don't need the real certificate)
set -euo pipefail
cd "$(dirname "$0")"

KC="$PWD/signing/signing.keychain-db"
KC_PASS=snappy
IDENTITY="Snappy Local Signing"
MIN_MACOS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" Info.plist)

APP=build/Snappy.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos$MIN_MACOS -o build/Snappy-$arch Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/Snappy" build/Snappy-arm64 build/Snappy-x86_64
rm build/Snappy-arm64 build/Snappy-x86_64

if [[ -n "${ADHOC:-}" ]]; then
  codesign --force --sign - "$APP"
else
  if [[ ! -f signing/id.p12 ]]; then
    mkdir -p signing
    openssl req -x509 -newkey rsa:2048 -nodes -keyout signing/key.pem -out signing/cert.pem -days 3650 \
      -subj "/CN=$IDENTITY" -addext "basicConstraints=critical,CA:false" \
      -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
    openssl pkcs12 -export -legacy -inkey signing/key.pem -in signing/cert.pem -out signing/id.p12 -passout pass:$KC_PASS
  fi
  if [[ ! -f "$KC" ]]; then
    security create-keychain -p $KC_PASS "$KC"
    security set-keychain-settings "$KC"
    security unlock-keychain -p $KC_PASS "$KC"
    security import signing/id.p12 -k "$KC" -P $KC_PASS -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s -k $KC_PASS "$KC" >/dev/null
  fi

  # codesign only finds identities in the keychain search list, so add ours just for the signing step.
  security unlock-keychain -p $KC_PASS "$KC"
  ORIG_KEYCHAINS=(${(f)"$(security list-keychains -d user | tr -d '" ')"})
  security list-keychains -d user -s "${ORIG_KEYCHAINS[@]}" "$KC"
  trap 'security list-keychains -d user -s "${ORIG_KEYCHAINS[@]}"' EXIT
  codesign --force --sign "$IDENTITY" "$APP"
fi
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Snappy || true
  rm -rf /Applications/Snappy.app
  cp -R "$APP" /Applications/
  open /Applications/Snappy.app
  echo "Installed /Applications/Snappy.app"
fi

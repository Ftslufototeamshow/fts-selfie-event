#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES=("$ROOT"/macos-app/*.swift)
PLIST="$ROOT/macos-app/Info.plist"
DIST="$ROOT/dist"
APP="$DIST/FTS Printer 014.app"
MACOS="$APP/Contents/MacOS"
mkdir -p "$MACOS"
rm -f "$MACOS/FTS Printer"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$DIST/build"
COMMON=(-parse-as-library -O -sdk "$SDK" -framework SwiftUI -framework AppKit -framework Foundation -framework Security -framework CryptoKit -framework ImageIO)
xcrun swiftc "${SOURCES[@]}" "${COMMON[@]}" -target arm64-apple-macos13.0 -o "$DIST/build/fts-printer-arm64"
xcrun swiftc "${SOURCES[@]}" "${COMMON[@]}" -target x86_64-apple-macos13.0 -o "$DIST/build/fts-printer-x86_64"
lipo -create "$DIST/build/fts-printer-arm64" "$DIST/build/fts-printer-x86_64" -output "$MACOS/FTS Printer"
cp "$PLIST" "$APP/Contents/Info.plist"
chmod +x "$MACOS/FTS Printer"
codesign --force --deep --sign - "$APP"
rm -f "$DIST/FTS-Printer-macOS-v0.1.4.zip" "$DIST/FTS-Printer-macOS-v0.1.4.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/FTS-Printer-macOS-v0.1.4.zip"
DMG="$DIST/FTS-Printer-macOS-v0.1.4.dmg"
rm -f "$DMG"
for attempt in 1 2 3; do
  if hdiutil create -volname "FTS Printer 014" -srcfolder "$APP" -ov -format UDZO "$DMG"; then
    break
  fi
  echo "DMG creation attempt $attempt failed; retrying..."
  rm -f "$DMG"
  sleep $((attempt * 3))
done
test -s "$DMG"
file "$MACOS/FTS Printer"
codesign --verify --deep --strict "$APP"

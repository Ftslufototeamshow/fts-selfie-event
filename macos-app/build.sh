#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES=("$ROOT"/macos-app/*.swift)
PLIST="$ROOT/macos-app/Info.plist"
DIST="$ROOT/dist"
APP="$DIST/FTS Printer.app"
MACOS="$APP/Contents/MacOS"
mkdir -p "$MACOS"
RES="$APP/Contents/Resources"
mkdir -p "$RES"
rm -f "$MACOS/FTS Printer"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$DIST/build"
COMMON=(-parse-as-library -O -sdk "$SDK" -framework SwiftUI -framework AppKit -framework Foundation -framework Security -framework CryptoKit -framework ImageIO)
xcrun swiftc "${SOURCES[@]}" "${COMMON[@]}" -target arm64-apple-macos13.0 -o "$DIST/build/fts-printer-arm64"
xcrun swiftc "${SOURCES[@]}" "${COMMON[@]}" -target x86_64-apple-macos13.0 -o "$DIST/build/fts-printer-x86_64"
lipo -create "$DIST/build/fts-printer-arm64" "$DIST/build/fts-printer-x86_64" -output "$MACOS/FTS Printer"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "$ROOT/macos-app/Resources/fts_printer_header.jpg" "$RES/fts_printer_header.jpg"
cp "$ROOT/macos-app/Resources/fts_printer_icon.jpg" "$RES/fts_printer_icon.jpg"
ICONSET="$DIST/build/FTSPrinter.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  set -- $spec
  sips -s format png -z "$1" "$1" "$ROOT/macos-app/Resources/fts_printer_icon.jpg" --out "$ICONSET/$2" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES/FTSPrinter.icns"
chmod +x "$MACOS/FTS Printer"
codesign --force --deep --sign - "$APP"
rm -f "$DIST/FTS-Printer-macOS-v0.2.1-design.zip" "$DIST/FTS-Printer-macOS-v0.2.1-design.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/FTS-Printer-macOS-v0.2.1-design.zip"
DMG="$DIST/FTS-Printer-macOS-v0.2.1-design.dmg"
rm -f "$DMG"
for attempt in 1 2 3; do
  if hdiutil create -volname "FTS Printer" -srcfolder "$APP" -ov -format UDZO "$DMG"; then
    break
  fi
  echo "DMG creation attempt $attempt failed; retrying..."
  rm -f "$DMG"
  sleep $((attempt * 3))
done
test -s "$DMG"
file "$MACOS/FTS Printer"
codesign --verify --deep --strict "$APP"

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

# Build a native macOS .icns bundle icon from the approved FTS artwork.
ICON_SRC="$ROOT/macos-app/Resources/fts_printer_icon.jpg"
ICONSET="$DIST/build/FTSPrinter.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -s format png -z 16 16 "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -s format png -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -s format png -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -s format png -z 64 64 "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -s format png -z 128 128 "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -s format png -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -s format png -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -s format png -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -s format png -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -s format png -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$RES/FTSPrinter.icns"
test -s "$RES/FTSPrinter.icns"

chmod +x "$MACOS/FTS Printer"
codesign --force --deep --sign - "$APP"
rm -f "$DIST/FTS-Printer-macOS-v0.3.14-live-device-panel.zip" "$DIST/FTS-Printer-macOS-v0.3.14-live-device-panel.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/FTS-Printer-macOS-v0.3.14-live-device-panel.zip"
DMG="$DIST/FTS-Printer-macOS-v0.3.14-live-device-panel.dmg"
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

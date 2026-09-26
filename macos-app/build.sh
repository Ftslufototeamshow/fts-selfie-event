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
# AppKit is used instead of sips because it accepts the same image formats as the app itself.
ICON_SRC="$ROOT/macos-app/Resources/fts_printer_icon.jpg"
ICONSET="$DIST/build/FTSPrinter.iconset"
ICON_SWIFT="$DIST/build/make_fts_icon.swift"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cat > "$ICON_SWIFT" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else { exit(2) }
let source = CommandLine.arguments[1]
let output = CommandLine.arguments[2]
guard let image = NSImage(contentsOfFile: source) else {
    fputs("Cannot decode FTS app icon with AppKit\n", stderr)
    exit(13)
}

let specs:[(String,Int)] = [
    ("icon_16x16.png",16),("icon_16x16@2x.png",32),
    ("icon_32x32.png",32),("icon_32x32@2x.png",64),
    ("icon_128x128.png",128),("icon_128x128@2x.png",256),
    ("icon_256x256.png",256),("icon_256x256@2x.png",512),
    ("icon_512x512.png",512),("icon_512x512@2x.png",1024)
]

for (name,size) in specs {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes:nil,
        pixelsWide:size,
        pixelsHigh:size,
        bitsPerSample:8,
        samplesPerPixel:4,
        hasAlpha:true,
        isPlanar:false,
        colorSpaceName:.deviceRGB,
        bytesPerRow:0,
        bitsPerPixel:0
    ) else { exit(14) }

    rep.size = NSSize(width:size,height:size)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep:rep) else { exit(15) }
    NSGraphicsContext.current = context
    NSColor.clear.set()
    NSRect(x:0,y:0,width:size,height:size).fill()
    image.draw(
        in:NSRect(x:0,y:0,width:size,height:size),
        from:NSRect(origin:.zero,size:image.size),
        operation:.copy,
        fraction:1.0,
        respectFlipped:true,
        hints:[.interpolation:NSImageInterpolation.high]
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data=rep.representation(using:.png,properties:[:]) else { exit(16) }
    try data.write(to:URL(fileURLWithPath:output).appendingPathComponent(name))
}
SWIFT
swift "$ICON_SWIFT" "$ICON_SRC" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$RES/FTSPrinter.icns"
test -s "$RES/FTSPrinter.icns"

chmod +x "$MACOS/FTS Printer"
codesign --force --deep --sign - "$APP"
rm -f "$DIST/FTS-Printer-macOS-v0.3.30-print-path-restore.zip" "$DIST/FTS-Printer-macOS-v0.3.30-print-path-restore.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/FTS-Printer-macOS-v0.3.30-print-path-restore.zip"
DMG="$DIST/FTS-Printer-macOS-v0.3.30-print-path-restore.dmg"
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

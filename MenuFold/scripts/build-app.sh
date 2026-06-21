#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$(cd "$ROOT/.." && pwd)/outputs}"
APP="$OUTPUT_ROOT/MenuFold.app"
BUILD="$ROOT/.build"
ICONSET="$BUILD/AppIcon.iconset"

SOURCE_FILES=("$ROOT"/Sources/MenuFold/**/*.swift)
xcrun swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target arm64-apple-macos15.0 \
  "${SOURCE_FILES[@]}" \
  -o "$BUILD/MenuFold" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -framework IOKit

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET" "$OUTPUT_ROOT"
cp "$BUILD/MenuFold" "$APP/Contents/MacOS/MenuFold"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"

swift "$ROOT/scripts/make-icon.swift" "$BUILD/AppIcon-1024.png"
for entry in \
  "16 icon_16x16.png" "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  size="${entry%% *}"
  name="${entry#* }"
  sips -z "$size" "$size" "$BUILD/AppIcon-1024.png" --out "$ICONSET/$name" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Keep the designated requirement stable so TCC permissions survive local rebuilds.
codesign --force --deep --sign - \
  -r='designated => identifier "com.local.MenuFold"' \
  "$APP"
echo "$APP"

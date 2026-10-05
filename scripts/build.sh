#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
/usr/bin/swift build -c release --product Melatonin
BIN_DIR="$(/usr/bin/swift build -c release --show-bin-path)"
APP="$ROOT/dist/Melatonin.app"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/usr/bin/install -m 755 "$BIN_DIR/Melatonin" "$APP/Contents/MacOS/Melatonin"
/usr/bin/install -m 644 Resources/Info.plist "$APP/Contents/Info.plist"
/usr/bin/swift scripts/icon.swift "$ROOT/.build/AppIcon.iconset"
/usr/bin/iconutil -c icns "$ROOT/.build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
# Local ad-hoc signing, not a Developer ID signature or Apple notarization.
/usr/bin/codesign --force --sign - --options runtime "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/Melatonin.app.zip"
printf '\nBuilt: %s\nDownload: %s\n' "$APP" "$ROOT/dist/Melatonin.app.zip"

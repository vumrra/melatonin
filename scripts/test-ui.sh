#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
/usr/bin/swift build --product Melatonin
BIN_DIR="$(/usr/bin/swift build --show-bin-path)"
/usr/bin/swiftc -swift-version 6 -warnings-as-errors -parse-as-library -D LIFECYCLE_TEST \
  -I "$BIN_DIR/Modules" \
  Sources/Melatonin/MelatoninApp.swift Sources/Melatonin/ControlPanel.swift \
  Sources/Melatonin/MenuBarEye.swift Tests/MenuLifecycleTests.swift \
  "$BIN_DIR/MelatoninCore.build/PowerControl.swift.o" \
  -o "$ROOT/.build/MenuLifecycleTests"
# Opens only our own app UI; all power access is read-only.
"$ROOT/.build/MenuLifecycleTests"

#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Separate compile-time entry point: render our own UI, never capture the desktop or change pmset.
/usr/bin/swift build --scratch-path .build/preview -Xswiftc -DPANEL_PREVIEW --product Melatonin
BIN_DIR="$(/usr/bin/swift build --scratch-path .build/preview --show-bin-path)"
"$BIN_DIR/Melatonin" "$ROOT/.build/previews"

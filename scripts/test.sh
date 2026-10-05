#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Portable on the standalone macOS Command Line Tools; full Xcode is not required.
# Real system access is read-only. All setting changes and authorization failures use fakes.
/usr/bin/swift run -Xswiftc -warnings-as-errors MelatoninCoreTests
/bin/bash -n scripts/build.sh
/usr/bin/plutil -lint Resources/Info.plist
# Compile (never execute) both exact privileged scripts to validate AppleScript syntax.
/usr/bin/osacompile -o .build/authorize-on.scpt -e 'do shell script "/usr/bin/pmset -a disablesleep 1" with administrator privileges'
/usr/bin/osacompile -o .build/authorize-off.scpt -e 'do shell script "/usr/bin/pmset -a disablesleep 0" with administrator privileges'

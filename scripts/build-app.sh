#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Building this app requires macOS 14+ and Xcode Command Line Tools." >&2
    exit 1
fi
swift build -c release --product PhotoExport
binary_dir="$(swift build -c release --show-bin-path)"
app="dist/Apple Photo Export.app"
mkdir -p "$app/Contents/MacOS"
cp "$binary_dir/PhotoExport" "$app/Contents/MacOS/PhotoExport"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
echo "Launch with: open 'dist/Apple Photo Export.app'"

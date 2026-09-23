#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/StatsDirect Viewer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -module-cache-path "${TMPDIR:-/tmp}/statsdirect-swift-cache" Sources/main.swift -o "$APP/Contents/MacOS/StatsDirectViewer" -framework Cocoa -framework WebKit
cp Info.plist "$APP/Contents/Info.plist"
rm -rf "$APP/Contents/Resources/Content"
cp -R Content "$APP/Contents/Resources/Content"
codesign --force --deep --sign - "$APP"
printf 'Built %s\n' "$APP"

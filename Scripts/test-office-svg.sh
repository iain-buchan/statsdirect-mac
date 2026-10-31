#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
mkdir -p .build
TEST_WORK="$(mktemp -d "$PWD/.build/office-svg.XXXXXX")"
trap 'rm -rf "$TEST_WORK"' EXIT
/usr/bin/swiftc -target arm64-apple-macosx14.0 -module-cache-path "$PWD/.build/swift-cache" \
  Sources/LegacyReport.swift Sources/RChartExport.swift Sources/OfficeSVG.swift Tests/office-svg-driver.swift \
  -o "$TEST_WORK/checks" -framework Cocoa -framework CoreText -framework WebKit
"$TEST_WORK/checks"

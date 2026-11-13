#!/bin/bash
# Exercise update sheets in an isolated AppKit process with injected discovery and download.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/swift-cache
TEST_WORK="$(mktemp -d "$PWD/.build/update-host.XXXXXX")"
trap 'rm -rf "$TEST_WORK"' EXIT
python3 - "$TEST_WORK" <<'PY'
from pathlib import Path
import sys

source = Path('Sources/main.swift').read_text()
Path(sys.argv[1], 'Viewer.swift').write_text(source[:source.rindex('MainActor.assumeIsolated {')])
PY
SOURCES=()
for source in Sources/*.swift; do
  if [[ "$source" != 'Sources/main.swift' ]]; then SOURCES+=("$source"); fi
done
swiftc -Onone -whole-module-optimization -emit-executable -module-name StatsDirectUpdateHostTest \
  -target arm64-apple-macosx14.0 -module-cache-path .build/swift-cache \
  "${SOURCES[@]}" "$TEST_WORK/Viewer.swift" Tests/update-host-driver.swift \
  -o "$TEST_WORK/driver" -framework Cocoa -framework WebKit -framework PDFKit -framework Security
"$TEST_WORK/driver"

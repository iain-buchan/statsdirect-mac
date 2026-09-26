#!/bin/bash
# Exercises the native host and WKWebViews against the real bundled example and engine.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BASE="${1:-$ROOT/StatsDirect Viewer.app}"
mkdir -p .build
TEST_WORK="$(mktemp -d "$ROOT/.build/learning-context.XXXXXX")"
TEST_APP="$TEST_WORK/StatsDirect Context Test.app"
python3 - "$TEST_WORK" <<'PY'
from pathlib import Path
import sys
source=Path('Sources/main.swift').read_text()
Path(sys.argv[1],'Viewer.swift').write_text(source[:source.rindex('MainActor.assumeIsolated {')])
PY
SOURCES=()
for source in Sources/*.swift; do
  if [[ "$source" != 'Sources/main.swift' ]]; then SOURCES+=("$source"); fi
done
swiftc -target arm64-apple-macosx14.0 -module-cache-path .build/swift-cache "${SOURCES[@]}" "$TEST_WORK/Viewer.swift" Tests/learning-workspace-driver.swift -o "$TEST_WORK/driver" -framework Cocoa -framework WebKit -framework PDFKit -framework Security
cp -cR "$BASE" "$TEST_APP"
cp "$TEST_WORK/driver" "$TEST_APP/Contents/MacOS/StatsDirectViewer"
rsync -a Content/ "$TEST_APP/Contents/Resources/Content/"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.statsdirect.viewer.contexttest.${TEST_WORK##*.}" "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName StatsDirect Context Test' "$TEST_APP/Contents/Info.plist"
codesign --force --sign - "$TEST_APP"
"$TEST_APP/Contents/MacOS/StatsDirectViewer" "${@:2}"

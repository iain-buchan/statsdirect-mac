#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export STATSDIRECT_CONFIGURATION="${STATSDIRECT_CONFIGURATION:-Debug}"
source Scripts/native-build-flags.sh
# Typecheck this large host once rather than once per primary source file.
# Debug remains unoptimised, with normal debug symbols.
if [[ "$STATSDIRECT_CONFIGURATION" == Debug ]]; then STATSDIRECT_SWIFT_FLAGS+=(-whole-module-optimization); fi
BASE="${1:-/Applications/StatsDirect.app}"
mkdir -p "$ROOT/.build"
TEST_WORK="$(mktemp -d "$ROOT/.build/r-console-integration.XXXXXX")"
trap 'rm -rf "$TEST_WORK"' EXIT
TEST_APP="$TEST_WORK/StatsDirect Console Integration Test.app"
WORKER_OUTPUT_KEY="$(printf '%s' "$TEST_APP/Contents/MacOS/RConsoleWorker" | shasum -a 256)"
WORKER_OBJECT_DIRECTORY="$ROOT/.build/r-console-worker-objects/${WORKER_OUTPUT_KEY%% *}"
trap 'rm -rf "$TEST_WORK" "$WORKER_OBJECT_DIRECTORY"' EXIT

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
/usr/bin/swiftc "${STATSDIRECT_SWIFT_FLAGS[@]}" -emit-executable -module-name StatsDirectConsoleIntegration \
  -emit-module-path "$TEST_WORK/StatsDirectConsoleIntegration.swiftmodule" \
  -target arm64-apple-macosx14.0 -module-cache-path "$ROOT/.build/swift-cache" \
  "${SOURCES[@]}" "$TEST_WORK/Viewer.swift" Tests/r-console-integration-driver.swift \
  -o "$TEST_WORK/driver" -framework Cocoa -framework WebKit -framework PDFKit \
  -framework Security -framework UniformTypeIdentifiers

/usr/bin/ditto --noqtn "$BASE" "$TEST_APP"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$TEST_APP/Contents/Info.plist")"
cp "$TEST_WORK/driver" "$TEST_APP/Contents/MacOS/$EXECUTABLE"
rm -rf "$TEST_APP/Contents/Resources/Content"
/usr/bin/ditto Content "$TEST_APP/Contents/Resources/Content"
/bin/bash Scripts/build-r-console-worker.sh "$TEST_APP/Contents/MacOS/RConsoleWorker"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.statsdirect.consoleintegration.${TEST_WORK##*.}" "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName StatsDirect Console Integration Test' "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName StatsDirect Console Integration Test' "$TEST_APP/Contents/Info.plist"
# Tests explicitly create their console; an optional prototype base must not
# create a second console at startup or share its application preferences.
/usr/libexec/PlistBuddy -c 'Delete :StatsDirectInteractiveConsolePrototype' "$TEST_APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/bin/codesign --force --sign - "$TEST_APP/Contents/MacOS/RConsoleWorker"
/usr/bin/codesign --force --sign - "$TEST_APP"
printf 'Test app: %s\n' "$TEST_APP"
"$TEST_APP/Contents/MacOS/$EXECUTABLE" --run-tests

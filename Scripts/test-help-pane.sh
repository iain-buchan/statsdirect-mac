#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
source Scripts/native-build-flags.sh
BASE="$ROOT/StatsDirect.app"
if [[ $# -gt 0 && "$1" != --* ]]; then BASE="$1"; shift; fi
PRIVATE_HELP=""
NAVIGATION_ONLY=false
TEST_ARGUMENTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --private-help)
      if [[ $# -lt 2 || ! -f "$2/index.html" || ! -f "$2/keyword-index.json" ]]; then
        echo 'Use --private-help with a freshly generated help directory containing keyword-index.json.' >&2
        exit 2
      fi
      PRIVATE_HELP="$(cd "$2" && pwd -P)"
      shift 2
      ;;
    --navigation-only) NAVIGATION_ONLY=true; shift ;;
    *) TEST_ARGUMENTS+=("$1"); shift ;;
  esac
done
TEST_WORK="$(mktemp -d "$ROOT/.build/help-pane.XXXXXX")"
trap 'rm -rf "$TEST_WORK"' EXIT   # the driver, its copy of the app and its module cache are not kept after the run
TEST_APP="$TEST_WORK/StatsDirect Help Pane Test.app"
swiftc "${STATSDIRECT_SWIFT_FLAGS[@]}" -target arm64-apple-macosx14.0 -module-cache-path .build/swift-cache Sources/HelpKeywordIndex.swift Tests/help-keyword-index-test.swift -o "$TEST_WORK/keyword-index-test"
if [[ -n "$PRIVATE_HELP" ]]; then
  "$TEST_WORK/keyword-index-test" "$PRIVATE_HELP"
else
  "$TEST_WORK/keyword-index-test"
fi
if [[ "$NAVIGATION_ONLY" == true ]]; then
  SOURCES=(Sources/HelpPane.swift Sources/HelpKeywordIndex.swift Sources/HelpIndexPicker.swift)
  EXTRA_FLAGS=(-D HELP_NAVIGATION_ONLY)
else
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
  SOURCES+=("$TEST_WORK/Viewer.swift")
  EXTRA_FLAGS=()
fi
swiftc "${STATSDIRECT_SWIFT_FLAGS[@]}" ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} -emit-executable -module-name StatsDirectTest -emit-module-path "$TEST_WORK/StatsDirectTest.swiftmodule" -target arm64-apple-macosx14.0 -module-cache-path .build/swift-cache "${SOURCES[@]}" Tests/help-pane-driver.swift -o "$TEST_WORK/driver" -framework Cocoa -framework WebKit -framework PDFKit -framework Security
cp -cR "$BASE" "$TEST_APP"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$TEST_APP/Contents/Info.plist")"
cp "$TEST_WORK/driver" "$TEST_APP/Contents/MacOS/$EXECUTABLE"
rsync -a --delete Content/ "$TEST_APP/Contents/Resources/Content/"
if [[ -n "$PRIVATE_HELP" ]]; then
  rsync -a --delete "$PRIVATE_HELP/" "$TEST_APP/Contents/Resources/Content/Help/"
  TEST_ARGUMENTS+=(--check-reader-escape)
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.statsdirect.viewer.helptest.${TEST_WORK##*.}" "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName StatsDirect Help Pane Test' "$TEST_APP/Contents/Info.plist"
codesign --force --sign - "$TEST_APP"
printf 'Test app: %s\n' "$TEST_APP"
"$TEST_APP/Contents/MacOS/$EXECUTABLE" --run-tests ${TEST_ARGUMENTS[@]+"${TEST_ARGUMENTS[@]}"}

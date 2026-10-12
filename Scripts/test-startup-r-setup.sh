#!/bin/bash
# Isolated application preferences/recents; injected R setup never installs software.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
source Scripts/native-build-flags.sh
BASE="${1:-$ROOT/StatsDirect.app}"
TEST_WORK="$(mktemp -d "$ROOT/.build/startup-r-setup.XXXXXX")"
TEST_APP="$TEST_WORK/StatsDirect Startup Test.app"
# Keep this isolated fixture out of Finder's Open With menu after the test.
unregister_fixture() {
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$TEST_APP" >/dev/null 2>&1 || true
}
trap unregister_fixture EXIT
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
swiftc "${STATSDIRECT_SWIFT_FLAGS[@]}" -emit-executable -module-name StatsDirectTest -emit-module-path "$TEST_WORK/StatsDirectTest.swiftmodule" -target arm64-apple-macosx14.0 -module-cache-path .build/swift-cache "${SOURCES[@]}" "$TEST_WORK/Viewer.swift" Tests/startup-r-setup-driver.swift -o "$TEST_WORK/driver" -framework Cocoa -framework WebKit -framework PDFKit -framework Security
cp -cR "$BASE" "$TEST_APP"
cp Info.plist "$TEST_APP/Contents/Info.plist"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$TEST_APP/Contents/Info.plist")"
cp "$TEST_WORK/driver" "$TEST_APP/Contents/MacOS/$EXECUTABLE"
rsync -a --delete Content/ "$TEST_APP/Contents/Resources/Content/"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.statsdirect.viewer.startuptest.${TEST_WORK##*.}" "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName StatsDirect Startup Test' "$TEST_APP/Contents/Info.plist"
codesign --force --sign - "$TEST_APP"
if [[ "${2:-}" != '--finder-only' ]]; then
  "$TEST_APP/Contents/MacOS/$EXECUTABLE" --startup-file
  "$TEST_APP/Contents/MacOS/$EXECUTABLE" --run-tests
fi
printf "stop('Opening a script must not run it')\n" > "$TEST_WORK/Requested.R"
open -W -n -a "$TEST_APP" --stdout "$TEST_WORK/finder-open.log" --stderr "$TEST_WORK/finder-open.err" "$TEST_WORK/Requested.R" --args --finder-file "$TEST_WORK/Requested.R"
cat "$TEST_WORK/finder-open.log" "$TEST_WORK/finder-open.err"
if ! grep -Fq 'PASS: Launch Services opens the actual requested file' "$TEST_WORK/finder-open.log"; then exit 1; fi

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
mkdir -p .build
TEST_WORK="$(mktemp -d "$ROOT/.build/grid-selection.XXXXXX")"
TEST_APP="$TEST_WORK/Grid Selection Test.app"
mkdir -p "$TEST_APP/Contents/MacOS"
python3 - "$TEST_APP" <<'PY'
import plistlib,sys
from pathlib import Path
app=Path(sys.argv[1])
info={'CFBundleIdentifier':'com.statsdirect.gridselection.'+app.parent.name.split('.')[-1], 'CFBundleExecutable':'GridSelectionTest','CFBundleName':'StatsDirect Grid Selection Test','CFBundlePackageType':'APPL','NSHighResolutionCapable':True}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
swiftc -parse-as-library -O -g -target arm64-apple-macosx14.0 Tests/grid-selection-driver.swift -o "$TEST_APP/Contents/MacOS/GridSelectionTest" -framework Cocoa -framework WebKit
codesign --force --sign - "$TEST_APP"
"$TEST_APP/Contents/MacOS/GridSelectionTest" "$ROOT" "$@"

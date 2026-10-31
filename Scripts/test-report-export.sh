#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
source Scripts/native-build-flags.sh
BASE="${1:-$ROOT/StatsDirect.app}"
TEST_WORK="$(mktemp -d "$ROOT/.build/report-export.XXXXXX")"
trap 'rm -rf "$TEST_WORK"' EXIT   # the driver, its copy of the app and its module cache are not kept after the run
TEST_APP="$TEST_WORK/StatsDirect Report Export Test.app"
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
swiftc "${STATSDIRECT_SWIFT_FLAGS[@]}" -emit-executable -module-name StatsDirectTest -emit-module-path "$TEST_WORK/StatsDirectTest.swiftmodule" -target arm64-apple-macosx14.0 -module-cache-path .build/swift-cache "${SOURCES[@]}" "$TEST_WORK/Viewer.swift" Tests/report-export-driver.swift Tests/report-*-checks.swift -o "$TEST_WORK/driver" -framework Cocoa -framework WebKit -framework PDFKit -framework Security
cp -cR "$BASE" "$TEST_APP"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$TEST_APP/Contents/Info.plist")"
cp "$TEST_WORK/driver" "$TEST_APP/Contents/MacOS/$EXECUTABLE"
rsync -a Content/ "$TEST_APP/Contents/Resources/Content/"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.statsdirect.viewer.reporttest.${TEST_WORK##*.}" "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName StatsDirect Report Export Test' "$TEST_APP/Contents/Info.plist"
codesign --force --sign - "$TEST_APP"
printf 'Test app: %s\n' "$TEST_APP"
"$TEST_APP/Contents/MacOS/$EXECUTABLE" "$ROOT/.build/report-export-output" "${@:2}"

if [[ " $* " == *" --notebook-only "* || $# -eq 1 || $# -eq 0 ]]; then
  NOTEBOOK_PYTHON="${NOTEBOOK_PYTHON:-python3}"
  "$NOTEBOOK_PYTHON" Tests/verify-report-notebooks.py "$ROOT/.build/report-export-output"
fi
if [[ " $* " == *" --notebook-import-only "* || $# -eq 1 || $# -eq 0 ]]; then
  "${RSCRIPT:-Rscript}" --vanilla "$ROOT/.build/report-export-output/imported-replay.R"
  python3 - "$ROOT/.build/report-export-output/imported-replay.pdf" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert p.stat().st_size>1000 and p.read_bytes().startswith(b'%PDF-')
print('PASS: imported native run record replays in R and draws plots without its original workbook')
PY
fi

if [[ " $* " == *" --notebook-import-only "* || " $* " == *" --notebook-only "* || " $* " == *" --saving-only "* || " $* " == *" --images-only "* || " $* " == *" --single-region-only "* || " $* " == *" --raster-readback-only "* ]]; then :
elif [[ " $* " == *" --svg-isolation-only "* ]]; then python3 Tests/verify-report-svg.py "$ROOT/.build/report-export-output"
elif [[ " $* " == *" --alignment-only "* ]]; then python3 Tests/verify-report-alignment.py "$ROOT/.build/report-export-output"
elif [[ " $* " == *" --creole-only "* ]]; then python3 Tests/verify-report-creole.py "$ROOT/.build/report-export-output"
elif [[ " $* " == *" --presentation-only "* ]]; then python3 Tests/verify-report-presentation.py "$ROOT/.build/report-export-output"
elif [[ " $* " != *" --deletion-only "* && " $* " != *" --transfer-only "* && " $* " != *" --legacy-only "* && " $* " != *" --records-only "* && " $* " != *" --legacy-file "* && " $* " != *" --report-file "* ]]; then python3 Tests/verify-report-documents.py "$ROOT/.build/report-export-output"; python3 Tests/verify-report-alignment.py "$ROOT/.build/report-export-output"; python3 Tests/verify-report-svg.py "$ROOT/.build/report-export-output"; fi

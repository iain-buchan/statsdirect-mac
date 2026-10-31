#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
mkdir -p .build
TEST_WORK="$(mktemp -d "$PWD/.build/r-chart-export-lifetime.XXXXXX")"
trap 'rm -rf "$TEST_WORK"' EXIT
python3 - "$TEST_WORK/RChartExport.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Sources/RChartExport.swift').read_text()
import re
matches = list(re.finditer(r'(?m)^([ \t]*)await image\.decode\(\);$', source))
assert len(matches) == 1
match = matches[0]
indent = match.group(1)
held = ["window.__statsDirectHeldPromise = new Promise(resolve => { window.__statsDirectReleaseDecode = resolve; });",
        "image.decode = () => { window.__statsDirectDecodeHeld = true; return window.__statsDirectHeldPromise; };",
        "await image.decode();"]
source = source[:match.start()] + "\n".join(indent + line for line in held) + source[match.end():]
anchor = '        super.init()\n        web.navigationDelegate = self'
assert source.count(anchor) == 1
source = source.replace(anchor, '''        super.init()
        RChartLifetimeProbe.record(renderer: self, web: web)
        web.navigationDelegate = self''')
# A production render deadline, when present, is shortened only in this
# throwaway compiled copy. No runtime back door or test mode is shipped.
anchor = 'private static let renderTimeoutNanoseconds: UInt64 = 15_000_000_000'
assert source.count(anchor) == 1
source = source.replace(anchor, 'private static let renderTimeoutNanoseconds: UInt64 = 2_000_000_000')
Path(sys.argv[1]).write_text(source)
PY
/usr/bin/swiftc -target arm64-apple-macosx14.0 -module-cache-path "$PWD/.build/swift-cache" \
  Sources/LegacyReport.swift "$TEST_WORK/RChartExport.swift" Sources/ReportImageClipboard.swift \
  Sources/RConsoleSVGWindow.swift Tests/r-chart-export-lifetime-driver.swift \
  -o "$TEST_WORK/checks" -framework Cocoa -framework WebKit -framework UniformTypeIdentifiers
"$TEST_WORK/checks" "$TEST_WORK"

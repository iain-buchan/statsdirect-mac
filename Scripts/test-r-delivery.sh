#!/bin/bash
# R+ delivery (worksheet R rules 6.1 and 6.2) without launching R.app, RStudio or StatsDirect: the R.app start-up file
# under Rscript, the R+ file names and leftover clean-up on fake folder trees, and a real console worker whose host is
# killed. The console worker needs the svglite package, which Scripts/prepare-r-console-svg.sh prepares (it installs
# it only when it is missing).
# Usage: Scripts/test-r-delivery.sh [RConsoleWorker]   (built here when not given)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
mkdir -p .build
TEST_WORK="$(mktemp -d "$ROOT/.build/r-delivery.XXXXXX")"
OWN_WORKER_OBJECT_DIRECTORY=""
cleanup() {
  if [[ -n "$OWN_WORKER_OBJECT_DIRECTORY" ]]; then rm -rf "$OWN_WORKER_OBJECT_DIRECTORY"; fi
  rm -rf "$TEST_WORK"
}
trap cleanup EXIT
R_SCRIPT="${R_SCRIPT:-$(command -v Rscript)}"
if [[ -n "${1:-}" ]]; then
  WORKER="$1"
else
  WORKER="$TEST_WORK/RConsoleWorker"
  WORKER_OUTPUT_KEY="$(printf '%s' "$WORKER" | shasum -a 256)"
  OWN_WORKER_OBJECT_DIRECTORY="$ROOT/.build/r-console-worker-objects/${WORKER_OUTPUT_KEY%% *}"
  /bin/bash Scripts/build-r-console-worker.sh "$WORKER" > /dev/null
fi
if [[ ! -x "$WORKER" ]]; then printf 'Missing R worker: %s\n' "$WORKER" >&2; exit 1; fi
WORKER="$(cd "$(dirname "$WORKER")" && pwd)/$(basename "$WORKER")"
/bin/bash Scripts/prepare-r-console-svg.sh
/usr/bin/swiftc -target arm64-apple-macosx14.0 -module-cache-path "$ROOT/.build/swift-cache" \
  Sources/RInstallation.swift Sources/RConsoleSession.swift Sources/RExternalSession.swift Tests/r-delivery-driver.swift \
  -o "$TEST_WORK/driver"
"$TEST_WORK/driver" "$R_SCRIPT" "$TEST_WORK" "$WORKER" "$ROOT/Content/R/console-bootstrap.R"

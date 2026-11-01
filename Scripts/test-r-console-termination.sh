#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
mkdir -p .build
TEST_WORK="$(mktemp -d "$ROOT/.build/r-console-termination.XXXXXX")"
OWN_WORKER_OBJECT_DIRECTORY=""
cleanup() {
  if [[ -n "$OWN_WORKER_OBJECT_DIRECTORY" ]]; then rm -rf "$OWN_WORKER_OBJECT_DIRECTORY"; fi
  if [[ "${STATSDIRECT_KEEP_CONSOLE_TERMINATION_TEST:-0}" == 1 ]]; then
    printf 'Retained termination fixtures: %s\n' "$TEST_WORK"
  else
    rm -rf "$TEST_WORK"
  fi
}
trap cleanup EXIT
if [[ -n "${1:-}" ]]; then
  WORKER="$1"
else
  WORKER="$TEST_WORK/RConsoleWorker"
  WORKER_OUTPUT_KEY="$(printf '%s' "$WORKER" | shasum -a 256)"
  OWN_WORKER_OBJECT_DIRECTORY="$ROOT/.build/r-console-worker-objects/${WORKER_OUTPUT_KEY%% *}"
  /bin/bash Scripts/build-r-console-worker.sh "$WORKER"
fi
if [[ ! -x "$WORKER" ]]; then printf 'Missing R worker: %s\n' "$WORKER" >&2; exit 1; fi
WORKER="$(cd "$(dirname "$WORKER")" && pwd)/$(basename "$WORKER")"
/bin/bash Scripts/prepare-r-console-svg.sh
/usr/bin/swiftc -swift-version 6 -parse-as-library -target arm64-apple-macosx14.0 \
  -module-cache-path "$ROOT/.build/swift-cache" \
  Sources/RConsoleSession.swift Sources/RInstallation.swift Tests/r-console-termination-checks.swift \
  -framework AppKit -o "$TEST_WORK/driver"
python3 - "$TEST_WORK" "$WORKER" "$ROOT/Content/R/console-bootstrap.R" <<'PY'
from pathlib import Path
import json
import os
import signal
import subprocess
import sys
import time

root, worker, bootstrap = map(Path, sys.argv[1:])
for kind in ('idle', 'busy', 'readline', 'startup', 'restart-retired'):
    folder = root / kind
    folder.mkdir()
    child = subprocess.Popen([str(root / 'driver'), kind, str(folder), str(worker), str(bootstrap)],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        try:
            output, _ = child.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            output, _ = child.communicate()
            raise AssertionError(f'{kind}: actual NSApplication.terminate timed out\n{output.decode(errors="replace")}')
        text = output.decode(errors='replace')
        print(text, end='', flush=True)
        assert child.returncode == 0, (kind, child.returncode)
        assert (folder / 'drain-complete.txt').read_text() == 'complete', kind
        assert (folder / 'application-will-terminate.txt').read_text() == 'terminated', kind
        assert time.time() - float((folder / 'quit-start.txt').read_text()) < 5, (kind, 'Quit exceeded its bounded retirement interval')
        manifest = json.loads((folder / 'manifest.json').read_text())
        for record in manifest['workers']:
            try:
                os.kill(record['pid'], 0)
            except ProcessLookupError:
                pass
            else:
                raise AssertionError(f'{kind}: orphan worker/probe {record["pid"]}')
            for key in ('temporary', 'ipc'):
                if key in record:
                    assert not Path(record[key]).exists(), (kind, key, record[key])
            if 'directory' in record:
                directory = Path(record['directory'])
                assert (directory / 'user-file.txt').read_text().strip() == 'preserved user content', kind
                if kind in ('idle', 'readline'):
                    assert (directory / 'finalizer.txt').read_text().strip() == 'finalized', kind
                if kind == 'idle':
                    assert b'%%EOF' in (directory / 'still-open.pdf').read_bytes()[-64:], kind
                if kind == 'readline':
                    assert not (directory / 'after-question.txt').exists(), kind
        print(f'PASS: actual AppKit Quit during {kind} exits, drains/reaps all owned processes, cleans private temporary files and preserves user content', flush=True)
    finally:
        # The process group was created only for this fixture. On a failed
        # assertion or timeout, never leave a test worker or held probe alive.
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
print('PASS: all five real NSApplication termination cases')
PY

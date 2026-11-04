#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_WORK="${STATSDIRECT_BUILD_WORK:-$PWD/.build}"
mkdir -p "$BUILD_WORK"
BUILD_WORK="$(cd "$BUILD_WORK" && pwd -P)"
CONTENT_RECORD="$(mktemp "$BUILD_WORK/content-build-input.XXXXXX")"
CONTENT_SNAPSHOT=""
cleanup_content_inputs() {
  case "$CONTENT_SNAPSHOT" in "$BUILD_WORK"/content-inputs.*) rm -rf -- "$CONTENT_SNAPSHOT";; esac
  case "$CONTENT_RECORD" in "$BUILD_WORK"/content-build-input.*) rm -f -- "$CONTENT_RECORD";; esac
}
trap cleanup_content_inputs EXIT
# Resolve one published content revision for the app build. CI/rebuilds opt into
# committed offline inputs or an explicit cached pin; installed apps never fetch.
CONTENT_MODE="${STATSDIRECT_CONTENT_MODE:-latest}"
CONTENT_ARGS=(--mode "$CONTENT_MODE" --record "$CONTENT_RECORD")
if [[ -n "${STATSDIRECT_CONTENT_REVISION:-}" ]]; then CONTENT_ARGS+=(--revision "$STATSDIRECT_CONTENT_REVISION"); fi
if [[ -n "${STATSDIRECT_CONTENT_REPOSITORY:-}" ]]; then CONTENT_ARGS+=(--repository "$STATSDIRECT_CONTENT_REPOSITORY"); fi
python3 Scripts/prepare-content-build.py "${CONTENT_ARGS[@]}"
if [[ "$CONTENT_MODE" != offline ]]; then
  "${NODE:-node}" Learn/build.mjs
fi
source Scripts/native-build-flags.sh
# A separate destination lets a new build be tested while the user keeps working
# in the current app. Never replace the executable/resources of that live app.
APP="${STATSDIRECT_APP_OUTPUT:-$PWD/StatsDirect.app}"
mkdir -p "$(dirname "$APP")"
APP="$(cd "$(dirname "$APP")" && pwd -P)/$(basename "$APP")"
# Freeze the validated reader inputs now, so another content refresh cannot
# change what this build packages while native compilation is running.
CONTENT_SNAPSHOT="$(mktemp -d "$BUILD_WORK/content-inputs.XXXXXX")"
ditto Content "$CONTENT_SNAPSHOT/Content"
mkdir -p "$CONTENT_SNAPSHOT/Learn"
ditto Learn/AuthoredTutor "$CONTENT_SNAPSHOT/Learn/AuthoredTutor"
cp Learn/lessons.json "$CONTENT_SNAPSHOT/Learn/lessons.json"
cp "$CONTENT_RECORD" "$CONTENT_SNAPSHOT/content-build-input.json"
python3 Scripts/check-content-imports.py --root "$CONTENT_SNAPSHOT"
python3 - "$CONTENT_SNAPSHOT" <<'PY'
from pathlib import Path
import json, sys
root = Path(sys.argv[1])
help = json.loads((root / 'Content/help-manifest.json').read_text())
record = json.loads((root / 'content-build-input.json').read_text())
if help['repository'] == 'https://github.com/iain-buchan/statisticalhelp':
    if record.get('revision') != help['commit'] or record.get('publicationManifestSHA256') != help.get('publicationManifestSHA256'):
        raise SystemExit('Content changed while capturing build inputs; retry the build.')
    bundle = (root / 'Content/Learn/app.js').read_text()
    if record['revision'] not in bundle or record['publicationManifestSHA256'] not in bundle:
        raise SystemExit('Learning bundle does not match the captured publication; regenerate it and retry the build.')
PY
cp "$CONTENT_SNAPSHOT/content-build-input.json" "$BUILD_WORK/content-build-input.json"
if [[ "${STATSDIRECT_ENGINE_PREBUILT:-0}" != "1" ]]; then
DOTNET_BIN="${DOTNET:-$(command -v dotnet || true)}"
if [[ -z "$DOTNET_BIN" && -x "$PWD/../../work/dotnet/dotnet" ]]; then DOTNET_BIN="$PWD/../../work/dotnet/dotnet"; fi
if [[ -z "$DOTNET_BIN" ]]; then
  printf 'Install the .NET 10 SDK, set DOTNET to its executable, or use ./docker-build.sh.\n' >&2
  exit 1
fi
export DOTNET_CLI_HOME="$BUILD_WORK/dotnet-home"
export NUGET_PACKAGES="${NUGET_PACKAGES:-$BUILD_WORK/nuget}"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_GENERATE_ASPNET_CERTIFICATE=false
DOTNET_BIN="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$DOTNET_BIN")"
export DOTNET_BIN
fi
# Restore only the pinned engine revision when this clone has not initialised it.
if [[ ! -f FullEngine/Upstream/StatsDirectUI/UI/OperationTestHost.cs ]]; then
  git submodule sync --recursive
  git submodule update --init --recursive
fi
FullEngine/build.sh
mkdir -p "$BUILD_WORK/native/$STATSDIRECT_CONFIGURATION"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
swiftc "${STATSDIRECT_SWIFT_FLAGS[@]}" -emit-executable -module-name StatsDirect -emit-module-path "$BUILD_WORK/native/$STATSDIRECT_CONFIGURATION/StatsDirect.swiftmodule" -target arm64-apple-macosx14.0 -module-cache-path "$BUILD_WORK/swift-cache" Sources/*.swift -o "$APP/Contents/MacOS/StatsDirect" -framework Cocoa -framework WebKit -framework PDFKit -framework Security
# The compiler links the dSYM while its temporary object files still exist.
statsdirect_store_symbols "$APP/Contents/MacOS/StatsDirect.dSYM" "$BUILD_WORK/symbols/$STATSDIRECT_CONFIGURATION/StatsDirect.app.dSYM"
# R remains an optional first-use installation for users. The small console
# helper is built against the build Mac's R headers and loads R at runtime.
/bin/bash Scripts/build-r-console-worker.sh "$APP/Contents/MacOS/RConsoleWorker"
WORKER_SYMBOLS="$BUILD_WORK/native/$STATSDIRECT_CONFIGURATION/RConsoleWorker.dSYM"
rm -rf "$WORKER_SYMBOLS"
xcrun dsymutil "$APP/Contents/MacOS/RConsoleWorker" -o "$WORKER_SYMBOLS"
statsdirect_store_symbols "$WORKER_SYMBOLS" "$BUILD_WORK/symbols/$STATSDIRECT_CONFIGURATION/RConsoleWorker.dSYM"
cp FullEngine/publish/StatsDirectEngine.dylib "$APP/Contents/Frameworks/StatsDirectEngine.dylib"
ditto FullEngine/publish "$APP/Contents/Resources/Engine"
python3 Scripts/build-icon.py "$BUILD_WORK"
cp "$BUILD_WORK/StatsDirect.icns" "$APP/Contents/Resources/StatsDirect.icns"
cp Info.plist "$APP/Contents/Info.plist"
# AI downloads its pinned, signed runtime on explicit first use. Remove any old
# payload when rebuilding an existing output directory; credentials live elsewhere.
rm -rf "$APP/Contents/Resources/TutorRuntime"
cp STATSDIRECT-LICENSE.txt STATISTICALHELP-LICENSE.txt DOTNET-LICENSE.txt DOTNET-ThirdPartyNotices.txt "$APP/Contents/Resources/"
# Replace the generated help as a unit so removed upstream assets cannot linger.
rm -rf "$APP/Contents/Resources/Content/Help"
ditto "$CONTENT_SNAPSHOT/Content" "$APP/Contents/Resources/Content"
cp "$CONTENT_SNAPSHOT/content-build-input.json" "$APP/Contents/Resources/content-build-input.json"
codesign --force --sign - "$APP/Contents/Frameworks/StatsDirectEngine.dylib"
codesign --force --sign - "$APP/Contents/MacOS/RConsoleWorker"
codesign --force --sign - "$APP"
python3 Scripts/verify-symbols.py "$APP" "$BUILD_WORK/symbols/$STATSDIRECT_CONFIGURATION"
printf 'Built %s (%s); symbols: %s\n' "$APP" "$STATSDIRECT_CONFIGURATION" "$BUILD_WORK/symbols/$STATSDIRECT_CONFIGURATION"

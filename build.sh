#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source Scripts/native-build-flags.sh
# A separate destination lets a new build be tested while the user keeps working
# in the current app. Never replace the executable/resources of that live app.
APP="${STATSDIRECT_APP_OUTPUT:-$PWD/StatsDirect.app}"
mkdir -p "$(dirname "$APP")"
APP="$(cd "$(dirname "$APP")" && pwd -P)/$(basename "$APP")"
BUILD_WORK="${STATSDIRECT_BUILD_WORK:-$PWD/.build}"
mkdir -p "$BUILD_WORK"
BUILD_WORK="$(cd "$BUILD_WORK" && pwd -P)"
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
cp FullEngine/publish/StatsDirectEngine.dylib "$APP/Contents/Frameworks/StatsDirectEngine.dylib"
ditto FullEngine/publish "$APP/Contents/Resources/Engine"
python3 Scripts/build-icon.py "$BUILD_WORK"
cp "$BUILD_WORK/StatsDirect.icns" "$APP/Contents/Resources/StatsDirect.icns"
cp Info.plist "$APP/Contents/Info.plist"
python3 Scripts/bundle-chatgpt.py "$APP" "$BUILD_WORK/codex-runtime"
cp STATSDIRECT-LICENSE.txt STATISTICALHELP-LICENSE.txt DOTNET-LICENSE.txt DOTNET-ThirdPartyNotices.txt "$APP/Contents/Resources/"
# Replace the generated help as a unit so removed upstream assets cannot linger.
rm -rf "$APP/Contents/Resources/Content/Help"
ditto Content "$APP/Contents/Resources/Content"
codesign --force --sign - "$APP/Contents/Frameworks/StatsDirectEngine.dylib"
codesign --force --sign - "$APP"
python3 Scripts/verify-symbols.py "$APP" "$BUILD_WORK/symbols/$STATSDIRECT_CONFIGURATION"
printf 'Built %s (%s); symbols: %s\n' "$APP" "$STATSDIRECT_CONFIGURATION" "$BUILD_WORK/symbols/$STATSDIRECT_CONFIGURATION"

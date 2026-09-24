#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 FullEngine/import_upstream.py --check
BUILD_WORK="${STATSDIRECT_BUILD_WORK:-$PWD/.build}"
mkdir -p "$BUILD_WORK"
BUILD_WORK="$(cd "$BUILD_WORK" && pwd -P)"
MAC_RUNTIME="$BUILD_WORK/dotnet-osx-arm64"
if [[ -n "${STATSDIRECT_ENGINE_PREBUILT:-}" ]]; then
  # docker-build.sh already published the engine and staged a macOS runtime.
  if [[ ! -f FullEngine/publish/StatsDirect.Headless.dll || ! -x "$MAC_RUNTIME/dotnet" || ! -f "$MAC_RUNTIME/runtime-version" ]]; then
    printf 'No prebuilt engine in FullEngine/publish and %s. Run ./docker-build.sh.\n' "$MAC_RUNTIME" >&2
    exit 1
  fi
  DOTNET_ROOT_DIR="$MAC_RUNTIME"
  RUNTIME_VERSION="$(<"$MAC_RUNTIME/runtime-version")"
  HOST_HEADERS="$MAC_RUNTIME/include"
  ENGINE_DOTNET="$MAC_RUNTIME/dotnet"
else
  : "${DOTNET_BIN:?Set DOTNET_BIN to the .NET 10 SDK executable}"
  "$DOTNET_BIN" publish FullEngine/StatsDirect.Headless.csproj -c Release -r osx-arm64 --self-contained false -o FullEngine/publish --nologo
  DOTNET_ROOT_DIR="$(cd "$(dirname "$DOTNET_BIN")" && pwd)"
  RUNTIME_VERSION="$("$DOTNET_BIN" --list-runtimes | awk '$1=="Microsoft.NETCore.App" && $2 ~ /^10\./ {v=$2} END {print v}')"
  HOST_HEADERS="$DOTNET_ROOT_DIR/packs/Microsoft.NETCore.App.Host.osx-arm64/$RUNTIME_VERSION/runtimes/osx-arm64/native"
  ENGINE_DOTNET="$DOTNET_BIN"
fi
clang++ -std=c++17 -dynamiclib -arch arm64 FullEngine/TextMetrics.cpp -o FullEngine/publish/libStatsDirectText.dylib -framework CoreText -framework CoreFoundation
codesign --force --sign - FullEngine/publish/libStatsDirectText.dylib
"$ENGINE_DOTNET" FullEngine/publish/StatsDirect.Headless.dll
cp FullEngine/publish/test-operations-results.txt Tests/test-operations-results.txt
mkdir -p FullEngine/publish/dotnet/shared/Microsoft.NETCore.App
# ditto replaces files without nesting duplicate runtime folders on repeat builds.
ditto "$DOTNET_ROOT_DIR/shared/Microsoft.NETCore.App/$RUNTIME_VERSION" "FullEngine/publish/dotnet/shared/Microsoft.NETCore.App/$RUNTIME_VERSION"
cp "$DOTNET_ROOT_DIR/host/fxr/$RUNTIME_VERSION/libhostfxr.dylib" FullEngine/publish/dotnet/
clang++ -std=c++17 -dynamiclib -arch arm64 -I "$HOST_HEADERS" FullEngine/bridge.cpp -o FullEngine/publish/StatsDirectEngine.dylib
codesign --force --sign - FullEngine/publish/StatsDirectEngine.dylib
clang++ -std=c++17 -arch arm64 Tests/bridge-driver.cpp -o Tests/bridge-driver
python3 Tests/test_engine.py

python3 Tests/test_agreement.py

clang++ -std=c++17 -arch arm64 Tests/operation-driver.cpp -o Tests/operation-driver
python3 Tests/test_menu.py Tests/operation-driver

python3 Tests/test_data_graphics.py Tests/operation-driver
python3 Tests/test_sessions.py Tests/operation-driver

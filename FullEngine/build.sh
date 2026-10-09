#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/native-build-flags.sh
python3 FullEngine/import_upstream.py --check
BUILD_WORK="${STATSDIRECT_BUILD_WORK:-$PWD/.build}"
mkdir -p "$BUILD_WORK/symbols/$STATSDIRECT_CONFIGURATION"
MAC_RUNTIME="$BUILD_WORK/dotnet-osx-arm64"
if [[ "${STATSDIRECT_ENGINE_PREBUILT:-0}" == "1" ]]; then
  if [[ ! -f FullEngine/publish/StatsDirect.Headless.dll || ! -x "$MAC_RUNTIME/dotnet" || ! -f "$MAC_RUNTIME/runtime-version" ]]; then
    printf 'Prebuilt engine/runtime missing. Run ./docker-build.sh.\n' >&2; exit 1
  fi
  DOTNET_ROOT_DIR="$MAC_RUNTIME"
  RUNTIME_VERSION="$(<"$MAC_RUNTIME/runtime-version")"
  HOST_HEADERS="$MAC_RUNTIME/include"
  ENGINE_DOTNET="$MAC_RUNTIME/dotnet"
else
  : "${DOTNET_BIN:?Set DOTNET_BIN to the .NET 10 SDK executable}"
  "$DOTNET_BIN" run --project FullEngine/Upstream/tests/DistributionRegression/DistributionRegression.csproj -c Release --nologo
  "$DOTNET_BIN" publish FullEngine/StatsDirect.Headless.csproj -c Release -r osx-arm64 --self-contained false -o FullEngine/publish --nologo
  DOTNET_ROOT_DIR="$(cd "$(dirname "$DOTNET_BIN")" && pwd)"
  RUNTIME_VERSION="$("$DOTNET_BIN" --list-runtimes | awk '$1=="Microsoft.NETCore.App" && $2 ~ /^10\./ {v=$2} END {print v}')"
  HOST_HEADERS="$DOTNET_ROOT_DIR/packs/Microsoft.NETCore.App.Host.osx-arm64/$RUNTIME_VERSION/runtimes/osx-arm64/native"
  ENGINE_DOTNET="$DOTNET_BIN"
fi
clang++ "${STATSDIRECT_NATIVE_FLAGS[@]}" -std=c++17 -dynamiclib -arch arm64 FullEngine/TextMetrics.cpp -o FullEngine/publish/libStatsDirectText.dylib -framework CoreText -framework CoreFoundation
statsdirect_store_symbols FullEngine/publish/libStatsDirectText.dylib.dSYM "$BUILD_WORK/symbols/$STATSDIRECT_CONFIGURATION/libStatsDirectText.dylib.dSYM"
codesign --force --sign - FullEngine/publish/libStatsDirectText.dylib
"$ENGINE_DOTNET" FullEngine/publish/StatsDirect.Headless.dll
cp FullEngine/publish/test-operations-results.txt Tests/test-operations-results.txt
mkdir -p FullEngine/publish/dotnet/shared/Microsoft.NETCore.App
# ditto replaces files without nesting duplicate runtime folders on repeat builds.
ditto "$DOTNET_ROOT_DIR/shared/Microsoft.NETCore.App/$RUNTIME_VERSION" "FullEngine/publish/dotnet/shared/Microsoft.NETCore.App/$RUNTIME_VERSION"
cp "$DOTNET_ROOT_DIR/host/fxr/$RUNTIME_VERSION/libhostfxr.dylib" FullEngine/publish/dotnet/
clang++ "${STATSDIRECT_NATIVE_FLAGS[@]}" -std=c++17 -dynamiclib -arch arm64 -I "$HOST_HEADERS" FullEngine/bridge.cpp -o FullEngine/publish/StatsDirectEngine.dylib
statsdirect_store_symbols FullEngine/publish/StatsDirectEngine.dylib.dSYM "$BUILD_WORK/symbols/$STATSDIRECT_CONFIGURATION/StatsDirectEngine.dylib.dSYM"
codesign --force --sign - FullEngine/publish/StatsDirectEngine.dylib
if [[ "${STATSDIRECT_RUN_TESTS:-0}" == "1" ]]; then ./test.sh; fi

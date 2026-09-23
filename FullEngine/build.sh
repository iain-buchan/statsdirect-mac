#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DOTNET_BIN:?Set DOTNET_BIN to the .NET 10 SDK executable}"
"$DOTNET_BIN" publish FullEngine/StatsDirect.Headless.csproj -c Release -r osx-arm64 --self-contained false -o FullEngine/publish --nologo
clang++ -std=c++17 -dynamiclib -arch arm64 FullEngine/TextMetrics.cpp -o FullEngine/publish/libStatsDirectText.dylib -framework CoreText -framework CoreFoundation
codesign --force --sign - FullEngine/publish/libStatsDirectText.dylib
"$DOTNET_BIN" FullEngine/publish/StatsDirect.Headless.dll
cp FullEngine/publish/test-operations-results.txt Tests/test-operations-results.txt
RUNTIME_VERSION="$("$DOTNET_BIN" --list-runtimes | awk '$1=="Microsoft.NETCore.App" && $2 ~ /^10\./ {v=$2} END {print v}')"
DOTNET_ROOT_DIR="$(cd "$(dirname "$DOTNET_BIN")" && pwd)"
HOST_HEADERS="$DOTNET_ROOT_DIR/packs/Microsoft.NETCore.App.Host.osx-arm64/$RUNTIME_VERSION/runtimes/osx-arm64/native"
mkdir -p FullEngine/publish/dotnet/shared/Microsoft.NETCore.App
# ditto replaces files without nesting duplicate runtime folders on repeat builds.
ditto "$DOTNET_ROOT_DIR/shared/Microsoft.NETCore.App/$RUNTIME_VERSION" "FullEngine/publish/dotnet/shared/Microsoft.NETCore.App/$RUNTIME_VERSION"
cp "$DOTNET_ROOT_DIR/host/fxr/$RUNTIME_VERSION/libhostfxr.dylib" FullEngine/publish/dotnet/
clang++ -std=c++17 -dynamiclib -arch arm64 -I "$HOST_HEADERS" FullEngine/bridge.cpp -o FullEngine/publish/StatsDirectEngine.dylib
codesign --force --sign - FullEngine/publish/StatsDirectEngine.dylib
clang++ -std=c++17 -arch arm64 Tests/bridge-driver.cpp -o Tests/bridge-driver
python3 Tests/test_engine.py

python3 Tests/test_agreement.py

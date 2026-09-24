#!/bin/bash
# Runs inside the container. Produces everything the Mac build needs from the
# .NET SDK, and nothing that needs macOS:
#   FullEngine/publish              managed engine, published for osx-arm64
#   <build work>/dotnet-osx-arm64   macOS .NET runtime staged for the app bundle
#   <build work>/dotnet-osx-arm64/include  hostfxr headers for bridge.cpp
#   <build work>/dotnet-osx-arm64/runtime-version  the version published against
set -euo pipefail
cd /work

if [[ ! -f FullEngine/Upstream/StatsDirectUI/UI/OperationTestHost.cs ]]; then
  printf 'Engine source is missing. Run: git submodule update --init --recursive\n' >&2
  exit 1
fi

BUILD_WORK="${STATSDIRECT_BUILD_WORK:-/work/.build}"
mkdir -p "$BUILD_WORK"
BUILD_WORK="$(cd "$BUILD_WORK" && pwd -P)"
RUNTIME_DIR="$BUILD_WORK/dotnet-osx-arm64"

export HOME="$BUILD_WORK/container-home"
export DOTNET_CLI_HOME="$BUILD_WORK/dotnet-home"
export NUGET_PACKAGES="${NUGET_PACKAGES:-$BUILD_WORK/nuget}"
mkdir -p "$HOME" "$DOTNET_CLI_HOME" "$NUGET_PACKAGES"

dotnet publish FullEngine/StatsDirect.Headless.csproj -c Release -r osx-arm64 --self-contained false -o FullEngine/publish --nologo

# Stage the same runtime version the SDK builds against, for macOS instead of Linux.
RUNTIME_VERSION="$(dotnet --list-runtimes | awk '$1=="Microsoft.NETCore.App" && $2 ~ /^10\./ {v=$2} END {print v}')"
if [[ -z "$RUNTIME_VERSION" ]]; then
  printf 'The container image has no Microsoft.NETCore.App 10 runtime.\n' >&2
  exit 1
fi

if [[ ! -d "$RUNTIME_DIR/shared/Microsoft.NETCore.App/$RUNTIME_VERSION" ]]; then
  dotnet-install.sh --runtime dotnet --version "$RUNTIME_VERSION" --os osx --architecture arm64 \
    --install-dir "$RUNTIME_DIR" --no-path
fi

# The hostfxr headers bridge.cpp includes ship in the macOS host pack.
HEADER_SOURCE="$NUGET_PACKAGES/microsoft.netcore.app.host.osx-arm64/$RUNTIME_VERSION/runtimes/osx-arm64/native"
if [[ ! -f "$HEADER_SOURCE/hostfxr.h" ]]; then
  HOST_PACK_WORK="$BUILD_WORK/host-pack"
  mkdir -p "$HOST_PACK_WORK"
  cat > "$HOST_PACK_WORK/host-pack.csproj" <<PROJECT
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup>
  <ItemGroup><PackageDownload Include="Microsoft.NETCore.App.Host.osx-arm64" Version="[$RUNTIME_VERSION]" /></ItemGroup>
</Project>
PROJECT
  dotnet restore "$HOST_PACK_WORK/host-pack.csproj" --nologo
fi
if [[ ! -f "$HEADER_SOURCE/hostfxr.h" ]]; then
  printf 'The macOS host pack %s did not provide hostfxr.h.\n' "$RUNTIME_VERSION" >&2
  exit 1
fi
mkdir -p "$RUNTIME_DIR/include"
cp "$HEADER_SOURCE"/*.h "$RUNTIME_DIR/include/"
# Older runtimes from earlier images stay staged, so record which one this
# publish used rather than leave the Mac build to guess.
printf '%s\n' "$RUNTIME_VERSION" > "$RUNTIME_DIR/runtime-version"

printf 'Published the engine and staged .NET %s for osx-arm64 in %s\n' "$RUNTIME_VERSION" "$RUNTIME_DIR"

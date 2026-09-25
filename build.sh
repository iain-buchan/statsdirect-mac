#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/StatsDirect Viewer.app"
BUILD_WORK="${STATSDIRECT_BUILD_WORK:-$PWD/.build}"
mkdir -p "$BUILD_WORK"
BUILD_WORK="$(cd "$BUILD_WORK" && pwd -P)"
DOTNET_BIN="${DOTNET:-$(command -v dotnet || true)}"
if [[ -z "$DOTNET_BIN" && -x "$PWD/../../work/dotnet/dotnet" ]]; then DOTNET_BIN="$PWD/../../work/dotnet/dotnet"; fi
if [[ -z "$DOTNET_BIN" ]]; then
  printf 'Install the .NET 10 SDK or set DOTNET to its executable.\n' >&2
  exit 1
fi
export DOTNET_CLI_HOME="$BUILD_WORK/dotnet-home"
export NUGET_PACKAGES="${NUGET_PACKAGES:-$BUILD_WORK/nuget}"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_GENERATE_ASPNET_CERTIFICATE=false
DOTNET_BIN="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$DOTNET_BIN")"
export DOTNET_BIN
FullEngine/build.sh
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
swiftc -target arm64-apple-macosx14.0 -module-cache-path "$BUILD_WORK/swift-cache" Sources/main.swift Sources/RPane.swift Sources/RScriptGenerator.swift Sources/ReportRHost.swift Sources/GridHost.swift Sources/CSVFileIO.swift Sources/RDataFileIO.swift Sources/RDataHost.swift Sources/ExcelHost.swift Sources/AnalysisHost.swift Sources/ChartHost.swift Sources/OperationHost.swift Sources/LearningCore.swift Sources/LearnHost.swift Sources/CoursePack.swift Sources/CoursePackHost.swift -o "$APP/Contents/MacOS/StatsDirectViewer" -framework Cocoa -framework WebKit -framework PDFKit -framework Security
cp FullEngine/publish/StatsDirectEngine.dylib "$APP/Contents/Frameworks/StatsDirectEngine.dylib"
ditto FullEngine/publish "$APP/Contents/Resources/Engine"
python3 Scripts/build-icon.py "$BUILD_WORK"
cp "$BUILD_WORK/StatsDirect.icns" "$APP/Contents/Resources/StatsDirect.icns"
cp Info.plist "$APP/Contents/Info.plist"
cp STATSDIRECT-LICENSE.txt STATISTICALHELP-LICENSE.txt DOTNET-LICENSE.txt DOTNET-ThirdPartyNotices.txt "$APP/Contents/Resources/"
ditto Content "$APP/Contents/Resources/Content"
codesign --force --sign - "$APP/Contents/Frameworks/StatsDirectEngine.dylib"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"

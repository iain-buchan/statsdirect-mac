#!/bin/bash
# Local interactive-R prototype only. The installed app and signing candidate
# are inputs, never build destinations; no installer or release is produced.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export STATSDIRECT_CONFIGURATION=Release
source Scripts/native-build-flags.sh
/bin/bash Scripts/prepare-r-console-svg.sh

BASE_APP=/Applications/StatsDirect.app
BUILD_WORK="$PWD/.build/interactive-r-console.noindex"
APP="$BUILD_WORK/StatsDirect Console Prototype.app"
SYMBOLS="$BUILD_WORK/symbols/Release"
PLIST_BUDDY=/usr/libexec/PlistBuddy

if [[ ! -x "$BASE_APP/Contents/MacOS/StatsDirect" || ! -f "$BASE_APP/Contents/Info.plist" ]]; then
  printf 'Install StatsDirect in /Applications before building this isolated prototype.\n' >&2
  exit 1
fi

# Replacing an app bundle while that instance is running would invalidate its
# resources. Leave the existing prototype intact until it has been closed.
if [[ -e "$APP/Contents/MacOS/StatsDirect" ]] && /usr/sbin/lsof -t "$APP/Contents/MacOS/StatsDirect" >/dev/null 2>&1; then
  printf 'Close StatsDirect Console Prototype before rebuilding it.\n' >&2
  exit 1
fi

mkdir -p "$BUILD_WORK/native/Release" "$BUILD_WORK/swift-cache" "$SYMBOLS"
STAGE="$(mktemp -d "$BUILD_WORK/stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
STAGED_APP="$STAGE/StatsDirect Console Prototype.app"

# Keep the current engine bridge and runtime assets without rebuilding them or
# changing the installed StatsDirect application.
/usr/bin/ditto --noqtn "$BASE_APP" "$STAGED_APP"
rm -rf "$STAGED_APP/Contents/Resources/Content"
/usr/bin/ditto Content "$STAGED_APP/Contents/Resources/Content"

/usr/bin/swiftc "${STATSDIRECT_SWIFT_FLAGS[@]}" \
  -emit-executable -module-name StatsDirectConsolePrototype \
  -emit-module-path "$BUILD_WORK/native/Release/StatsDirectConsolePrototype.swiftmodule" \
  -target arm64-apple-macosx14.0 -module-cache-path "$BUILD_WORK/swift-cache" \
  Sources/*.swift -o "$STAGED_APP/Contents/MacOS/StatsDirect" \
  -framework Cocoa -framework WebKit -framework PDFKit \
  -framework Security -framework UniformTypeIdentifiers

# Swift emits matching symbols while its temporary objects still exist. The R
# helper needs dsymutil explicitly; neither symbol bundle belongs inside the app.
statsdirect_store_symbols "$STAGED_APP/Contents/MacOS/StatsDirect.dSYM" "$SYMBOLS/StatsDirect.app.dSYM"
/bin/bash Scripts/build-r-console-worker.sh "$STAGED_APP/Contents/MacOS/RConsoleWorker"
if [[ -e "$SYMBOLS/RConsoleWorker.dSYM" ]]; then
  PREVIOUS_SYMBOLS="$(mktemp -d "$BUILD_WORK/symbols/previous.XXXXXX")"
  mv "$SYMBOLS/RConsoleWorker.dSYM" "$PREVIOUS_SYMBOLS/"
fi
/usr/bin/xcrun dsymutil "$STAGED_APP/Contents/MacOS/RConsoleWorker" -o "$SYMBOLS/RConsoleWorker.dSYM"

PLIST="$STAGED_APP/Contents/Info.plist"
"$PLIST_BUDDY" -c 'Set :CFBundleIdentifier com.statsdirect.consoleprototype' "$PLIST"
"$PLIST_BUDDY" -c 'Set :CFBundleDisplayName StatsDirect Console Prototype' "$PLIST"
"$PLIST_BUDDY" -c 'Set :CFBundleName StatsDirect Console Prototype' "$PLIST"
"$PLIST_BUDDY" -c 'Delete :StatsDirectInteractiveConsolePrototype' "$PLIST" >/dev/null 2>&1 || true
"$PLIST_BUDDY" -c 'Add :StatsDirectInteractiveConsolePrototype bool true' "$PLIST"
/usr/bin/plutil -lint "$PLIST"

# This local prototype uses ad hoc signatures and never contacts Apple's
# signing/notarisation services or alters the live release.
/usr/bin/codesign --force --sign - "$STAGED_APP/Contents/MacOS/RConsoleWorker"
/usr/bin/codesign --force --sign - "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

# Publish locally only after compilation and verification have succeeded.
rm -rf "$APP"
mv "$STAGED_APP" "$APP"
printf 'Built %s\nSymbols: %s\n' "$APP" "$SYMBOLS"

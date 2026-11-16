#!/bin/zsh
# Packages a built StatsDirect.app for a GitHub release: the application ZIP (ditto, so that the bundle survives intact),
# the matching crash-debugging symbols, SHA256SUMS.txt and BUILD-INFO.txt, into a folder of the release's name.
#
#   Scripts/package-release.sh <app> <symbols folder> <version> <output folder> [--unsigned]
#
# With --unsigned the application ZIP is named -unsigned and BUILD-INFO.txt says so: this is the tested package that
# SIGNING.md step 2 keeps for comparison. The published ZIP is made from the signed app in SIGNING.md step 5.
# Both ZIPs are made without resource forks, extended attributes or access control lists (the in-app installer refuses them
# in the application ZIP), and both are checked for AppleDouble entries. The app is checked first: every account must be
# able to read all of it, and it carries no separate .NET symbol file (Scripts/check-app-bundle.py).
set -euo pipefail
APP=${1:?app bundle}; SYMBOLS=${2:?symbols folder}; VERSION=${3:?version}; OUT=${4:?output folder}; shift 4
SUFFIX=""; STATE="Developer ID signed, notarised and stapled."
while [[ $# -gt 0 ]]; do case $1 in --unsigned) SUFFIX="-unsigned"; STATE="Not yet signed: ad hoc signature from the build. To be signed and notarised by SIGNING.md before publication."; shift;; *) echo "unknown option $1" >&2; exit 2;; esac; done
ROOT=${0:A:h:h}
mkdir -p "$OUT"
ZIP="$OUT/StatsDirect-$VERSION-macOS-arm64$SUFFIX.zip"
SYMZIP="$OUT/StatsDirect-$VERSION-macOS-arm64-symbols.zip"
rm -f "$ZIP" "$SYMZIP"
python3 "$ROOT/Scripts/check-app-bundle.py" "$APP"
# The symbols of this build alone: a folder that was built into more than once also keeps those of the earlier builds.
other=$(find "$SYMBOLS" -mindepth 1 -maxdepth 1 ! -name '*.dSYM' | wc -l | tr -d ' ')
[[ "$other" == 0 ]] || { echo "$SYMBOLS holds more than this build's dSYM bundles: package from a fresh clone" >&2; exit 1; }
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
ditto -c -k --norsrc --noextattr "$SYMBOLS" "$SYMZIP"
for archive in "$ZIP" "$SYMZIP"; do
  # grep -c prints the count and exits 1 when it is 0
  stray=$(unzip -Z1 "$archive" | grep -c -E '^__MACOSX/|(^|/)\._[^/]*$' || true)
  [[ "$stray" == 0 ]] || { echo "$(basename "$archive") carries $stray AppleDouble entries" >&2; exit 1; }
done
PLIST="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "$VERSION" ]] || { echo "the app's version is not $VERSION" >&2; exit 1; }
ENGINE=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["version"], d["commit"][:8])' "$APP/Contents/Resources/Content/engine-info.json")
SOURCE=$(git -C "$ROOT" rev-parse HEAD)
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$SYMZIP")" > SHA256SUMS.txt)
cat > "$OUT/BUILD-INFO.txt" <<INFO
StatsDirect for Mac $VERSION — built $(date -u '+%-d %B %Y %H:%M UTC')
Source: $SOURCE
Apple Silicon (arm64), macOS 14 or later. Engine $ENGINE (the Windows calculation engine at its released tag).
Open the ZIP and copy StatsDirect.app to Applications.

$STATE
Built with build.sh (Release); every suite of test.sh and Tests/ run on this source before packaging.
See SHA256SUMS.txt for hashes.
INFO
ls -la "$OUT"

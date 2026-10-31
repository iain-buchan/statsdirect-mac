#!/bin/zsh
# Signs StatsDirect.app for distribution outside the App Store: every Mach-O inside the bundle first (the .NET runtime's
# libraries, the engine, the text layout library), then the bundle itself with the hardened runtime, the entitlements in
# StatsDirect.entitlements (beside Info.plist) and a secure timestamp; then verifies the signature as Gatekeeper will.
#
#   Scripts/sign-app.sh <app> "<Developer ID Application: Name (TEAMID)>"     sign for distribution
#   Scripts/sign-app.sh <app> -                                               ad hoc, hardened runtime still on (for testing)
#   Scripts/sign-app.sh <app> "<identity>" --notarize <keychain profile>      sign, submit to Apple, wait, staple, validate
#
# The keychain profile is made once with: xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-specific password>
set -euo pipefail
APP=${1:?app bundle}; IDENTITY=${2:?signing identity or -}; shift 2
NOTARIZE=""; PROFILE=""
while [[ $# -gt 0 ]]; do case $1 in --notarize) NOTARIZE=1; PROFILE=${2:?keychain profile}; shift 2;; *) echo "unknown option $1" >&2; exit 2;; esac; done
ROOT=${0:A:h:h}
ENTITLEMENTS="$ROOT/StatsDirect.entitlements"
WORKER_ENTITLEMENTS="$ROOT/RConsoleWorker.entitlements"
[[ -f "$ENTITLEMENTS" ]] || { echo "missing $ENTITLEMENTS" >&2; exit 2; }
[[ -f "$WORKER_ENTITLEMENTS" ]] || { echo "missing $WORKER_ENTITLEMENTS" >&2; exit 2; }
WORKER="$APP/Contents/MacOS/RConsoleWorker"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :StatsDirectInteractiveRConsole' "$APP/Contents/Info.plist" 2>/dev/null || true)" == true && ! -x "$WORKER" ]]; then
  echo "the interactive R helper is missing from this app" >&2
  exit 2
fi
timestamp=(--timestamp)
ADHOC_ENTITLEMENTS=""
trap '[[ -z "$ADHOC_ENTITLEMENTS" ]] || rm -f "$ADHOC_ENTITLEMENTS"' EXIT
if [[ "$IDENTITY" == "-" ]]; then
  # An ad hoc signature carries no team, so library validation would refuse every library in the bundle; for testing the
  # hardened runtime without a certificate the validation is switched off in a temporary copy of the entitlements. A
  # Developer ID signature gives every library the team and needs no such allowance.
  timestamp=()
  ADHOC_ENTITLEMENTS=$(mktemp -t statsdirect-entitlements)
  cp "$ENTITLEMENTS" "$ADHOC_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ADHOC_ENTITLEMENTS"
  ENTITLEMENTS="$ADHOC_ENTITLEMENTS"
fi
# Inner code first, deepest first: dynamic libraries, bundled executables and the engine host. codesign --deep is not used,
# since it signs only what the bundle structure declares and skips the runtime's loose libraries under Resources.
find "$APP/Contents" -type f \( -name '*.dylib' -o -perm -u+x \) -not -path '*/_CodeSignature/*' -not -name '*.sh' -not -name '*.py' -not -name '*.js' -not -name '*.R' \
  | sort -r | while IFS= read -r file; do
    if file "$file" | grep -q 'Mach-O'; then
      FILE_ENTITLEMENTS="$ENTITLEMENTS"
      if [[ "$file" == "$WORKER" ]]; then FILE_ENTITLEMENTS="$WORKER_ENTITLEMENTS"; fi
      codesign --force --sign "$IDENTITY" --options runtime "${timestamp[@]}" --entitlements "$FILE_ENTITLEMENTS" "$file"
    fi
  done
codesign --force --sign "$IDENTITY" --options runtime "${timestamp[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --entitlements - "$APP" 2>&1 | grep -q 'allow-jit' || { echo "entitlements missing from the signature" >&2; exit 1; }
if [[ -x "$WORKER" ]]; then
  codesign --display --entitlements - "$WORKER" 2>&1 | grep -q 'disable-library-validation' || { echo "R helper entitlements missing from the signature" >&2; exit 1; }
fi
if [[ "$IDENTITY" != "-" ]]; then
  spctl --assess --type exec --verbose=2 "$APP" || echo "Gatekeeper will accept the app once it is notarized and stapled"
fi
if [[ -n "$NOTARIZE" ]]; then
  ZIP="${APP%.app}-notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type exec --verbose=2 "$APP"
  rm -f "$ZIP"
fi
echo "Signed $APP with $IDENTITY${NOTARIZE:+, notarized and stapled}"

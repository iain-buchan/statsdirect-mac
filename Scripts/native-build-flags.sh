#!/bin/bash
# Shared by the application, native bridges and integration-test hosts.
STATSDIRECT_CONFIGURATION="${STATSDIRECT_CONFIGURATION:-Release}"
export STATSDIRECT_CONFIGURATION
case "$STATSDIRECT_CONFIGURATION" in
  Release)
    STATSDIRECT_SWIFT_FLAGS=(-O -whole-module-optimization -g)
    STATSDIRECT_NATIVE_FLAGS=(-O2 -g)
    ;;
  Debug)
    STATSDIRECT_SWIFT_FLAGS=(-Onone -g)
    STATSDIRECT_NATIVE_FLAGS=(-O0 -g)
    ;;
  *)
    printf 'STATSDIRECT_CONFIGURATION must be Release or Debug.\n' >&2
    exit 1
    ;;
esac

statsdirect_store_symbols() {
  local source="$1" destination="$2" previous
  if [[ ! -d "$source" ]]; then
    printf 'Missing compiler-produced symbols: %s\n' "$source" >&2
    return 1
  fi
  # Retain previous symbol bundles so earlier local builds remain diagnosable.
  if [[ -e "$destination" ]]; then
    previous="$(mktemp -d "$BUILD_WORK/symbols/previous.XXXXXX")"
    mv "$destination" "$previous/"
  fi
  mv "$source" "$destination"
}

# Allow non-shell test launchers to use precisely the same flags.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    --swift) printf '%s\n' "${STATSDIRECT_SWIFT_FLAGS[@]}" ;;
    --native) printf '%s\n' "${STATSDIRECT_NATIVE_FLAGS[@]}" ;;
    *) printf 'Use --swift or --native.\n' >&2; exit 1 ;;
  esac
fi

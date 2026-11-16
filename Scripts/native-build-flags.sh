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
# Match the Swift host and Info.plist on newer build Macs as well as CI. Without
# an explicit target, clang marks the bridges as requiring the build Mac's OS.
STATSDIRECT_NATIVE_FLAGS+=(-mmacosx-version-min=14.0)
# A release records source locations relative to the repository in its debug symbols (and, for the C++ sources, in any
# assertion text), so that neither the app nor its published symbols name the build Mac's folders or account. Debug builds
# keep full paths for lldb.
STATSDIRECT_SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ "$STATSDIRECT_CONFIGURATION" == Release ]]; then
  statsdirect_map_path() {
    STATSDIRECT_SWIFT_FLAGS+=(-file-prefix-map "$1=$2")
    STATSDIRECT_NATIVE_FLAGS+=("-ffile-prefix-map=$1=$2")
  }
  # The same folder as the shell names it, when it was reached through a link.
  STATSDIRECT_LOGICAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -L)"
  # Swift's module cache keeps its real path while a binary is linked: dsymutil reads the Apple frameworks' types from it,
  # and under a mapped path it finds none (the dSYM then lacks those types, with a warning for each framework). The cache's
  # path is in the temporary objects only, never in the dSYM. Swift applies the first map that matches, so the cache's own
  # comes before the repository's. It is repeated after it: for a compiler that applies the last, and because without the
  # second copy some frameworks' types are written into the dSYM twice.
  statsdirect_keep_module_caches() {
    local cache seen=""
    for cache in "$STATSDIRECT_SOURCE_ROOT/.build/swift-cache" "$STATSDIRECT_LOGICAL_ROOT/.build/swift-cache" ${BUILD_WORK:+"$BUILD_WORK/swift-cache"}; do
      case "$seen" in *"|$cache|"*) continue;; esac
      seen="$seen|$cache|"
      STATSDIRECT_SWIFT_FLAGS+=(-file-prefix-map "$cache=$cache")
    done
  }
  statsdirect_keep_module_caches
  statsdirect_map_path "$STATSDIRECT_SOURCE_ROOT" .
  if [[ "$STATSDIRECT_LOGICAL_ROOT" != "$STATSDIRECT_SOURCE_ROOT" ]]; then statsdirect_map_path "$STATSDIRECT_LOGICAL_ROOT" .; fi
  # A build area outside the repository is named as the one inside it would be.
  if [[ -n "${BUILD_WORK:-}" && "$BUILD_WORK" != "$STATSDIRECT_SOURCE_ROOT"/* && "$BUILD_WORK" != "$STATSDIRECT_LOGICAL_ROOT"/* ]]; then
    statsdirect_map_path "$BUILD_WORK" .build
  fi
  statsdirect_keep_module_caches
fi

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
  # dsymutil notes the binary it read in a relocation map. Keep the file's name only: the folder is the build Mac's.
  if [[ "$STATSDIRECT_CONFIGURATION" == Release ]]; then
    find "$destination/Contents/Resources/Relocations" -name '*.yml' -type f -exec \
      sed -i '' -E "s|^(binary-path:[[:space:]]*)'.*/([^/']+)'[[:space:]]*\$|\\1'\\2'|" {} + 2>/dev/null || true
  fi
}

# Once a binary's dSYM is stored, drop the linker's debug map from the binary itself: it lists the object files' folders
# on the build Mac and is of no use without them. The UUID is unchanged, so crash reports still match the dSYM.
statsdirect_strip_debug_map() {
  if [[ "$STATSDIRECT_CONFIGURATION" == Release ]]; then xcrun strip -S "$1"; fi
}

# Allow non-shell test launchers to use precisely the same flags.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    --swift) printf '%s\n' "${STATSDIRECT_SWIFT_FLAGS[@]}" ;;
    --native) printf '%s\n' "${STATSDIRECT_NATIVE_FLAGS[@]}" ;;
    *) printf 'Use --swift or --native.\n' >&2; exit 1 ;;
  esac
fi

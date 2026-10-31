#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
R_BIN="${R_BIN:-/usr/local/bin/R}"
R_HOME_PATH="$($R_BIN RHOME)"
OUTPUT="${1:-$PWD/.build/interactive-r-console-worker}"
OUTPUT_KEY="$(printf '%s' "$OUTPUT" | shasum -a 256)"
# The executable may target an app bundle. Keep unsigned build intermediates
# in the repository build area, never beside a bundled executable.
OBJECT_DIRECTORY="$PWD/.build/r-console-worker-objects/${OUTPUT_KEY%% *}"
OBJECT="$OBJECT_DIRECTORY/RConsoleWorker.o"
mkdir -p "$(dirname "$OUTPUT")" "$OBJECT_DIRECTORY"
# Retain the object so a later dsymutil can resolve the worker's debug map.
clang++ -std=c++17 -O2 -g -mmacosx-version-min=14.0 -arch arm64 \
  -I "$R_HOME_PATH/include" -c Native/RConsoleWorker.cpp -o "$OBJECT"
clang++ -g -mmacosx-version-min=14.0 -arch arm64 "$OBJECT" -o "$OUTPUT"
printf '%s\n' "$OUTPUT"

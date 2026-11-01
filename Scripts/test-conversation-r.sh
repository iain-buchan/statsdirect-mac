#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
TEST_WORK="$(mktemp -d "$PWD/.build/conversation-r.XXXXXX")"
trap 'rm -rf "$TEST_WORK"' EXIT   # the driver, its copy of the app and its module cache are not kept after the run
R_SCRIPT="${RSCRIPT:-/Library/Frameworks/R.framework/Resources/bin/Rscript}"
swiftc -warnings-as-errors -module-cache-path .build/swift-cache Sources/ConversationRScript.swift Tests/conversation-r-driver.swift -o "$TEST_WORK/driver"
"$TEST_WORK/driver" "$TEST_WORK" "$R_SCRIPT"

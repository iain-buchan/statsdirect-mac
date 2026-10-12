#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -warnings-as-errors -target arm64-apple-macosx14.0 Sources/TutorRuntime.swift Tests/tutor-runtime-driver.swift -o .build/tutor-runtime-tests
.build/tutor-runtime-tests "$@"

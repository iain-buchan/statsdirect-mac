#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -parse-as-library Sources/AISharingConsent.swift Tests/ai-sharing-tests.swift -o .build/ai-sharing-tests
.build/ai-sharing-tests

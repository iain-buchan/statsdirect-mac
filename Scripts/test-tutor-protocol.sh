#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
TEST_WORK="$(mktemp -d "$PWD/.build/tutor-protocol.XXXXXX")"
trap 'rm -rf "$TEST_WORK"' EXIT
SOURCES=(Sources/TutorRuntime.swift Sources/TutorRuntimeInstaller.swift Sources/ChatGPTTutor.swift)
swiftc -warnings-as-errors -target arm64-apple-macosx14.0 "${SOURCES[@]}" Tests/chatgpt-tutor-driver.swift -o "$TEST_WORK/chatgpt-test"
"$TEST_WORK/chatgpt-test" "$PWD/Tests/mock-chatgpt-server.py" "$TEST_WORK/chatgpt-mock" "$PWD/Content/Tutor" mock
swiftc -warnings-as-errors -target arm64-apple-macosx14.0 "${SOURCES[@]}" Tests/tutor-policy-driver.swift -o "$TEST_WORK/policy-test"
"$TEST_WORK/policy-test"

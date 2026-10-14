#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STATSDIRECT_AI_TEST_DRIVER=Tests/report-ai-driver.swift bash Scripts/test-script-ai.sh "$@"

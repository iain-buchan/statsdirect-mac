#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STATSDIRECT_LEARNING_TEST_DRIVER=Tests/learning-recovery-driver.swift bash Scripts/test-provider-learning.sh "$@"

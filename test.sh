#!/bin/bash
# Full engine, R comparison and browser model regression suite.
set -euo pipefail
cd "$(dirname "$0")"
python3 -c 'import sys;sys.path.insert(0,"Tests");from r_runtime import rscript;print("R comparisons:",rscript())'
clang++ -std=c++17 -arch arm64 Tests/bridge-driver.cpp -o Tests/bridge-driver
clang++ -std=c++17 -arch arm64 Tests/operation-driver.cpp -o Tests/operation-driver
bash Scripts/test-form-descriptors.sh
export STATSDIRECT_FORM_TRACE="$(mktemp -d "$PWD/.build/form-trace.XXXXXX")"
for test in engine agreement menu data_graphics sessions analysis_defaults form_contracts form_branches form_follow_ons upstream_update distribution_update core_5_0_13 core_2026_09_30 distribution_menu beta_feedback follow_on group_identifier write_back help_examples help_regression_r charts; do
  python3 "Tests/test_${test}.py"
done
python3 Tests/test_form_coverage.py
if command -v node >/dev/null 2>&1; then node --test Grid/*.test.mjs Learn/*.test.mjs Report/*.test.mjs; fi

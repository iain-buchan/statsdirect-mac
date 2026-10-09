#!/bin/bash
# Full engine, R comparison and browser model regression suite.
set -euo pipefail
cd "$(dirname "$0")"
python3 -c 'import sys;sys.path.insert(0,"Tests");from r_runtime import rscript;print("R comparisons:",rscript())'
clang++ -std=c++17 -arch arm64 Tests/bridge-driver.cpp -o Tests/bridge-driver
clang++ -std=c++17 -arch arm64 Tests/operation-driver.cpp -o Tests/operation-driver
for test in engine agreement menu data_graphics sessions analysis_defaults upstream_update distribution_update core_5_0_13 core_2026_09_30 distribution_menu beta_feedback follow_on group_identifier write_back help_examples; do
  python3 "Tests/test_${test}.py"
done
if command -v node >/dev/null 2>&1; then node --test Grid/*.test.mjs Learn/*.test.mjs Report/*.test.mjs; fi

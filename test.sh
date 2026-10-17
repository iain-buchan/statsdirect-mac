#!/bin/bash
# Full engine, R comparison and browser model regression suite.
set -euo pipefail
cd "$(dirname "$0")"
python3 -c 'import sys;sys.path.insert(0,"Tests");from r_runtime import rscript;print("R comparisons:",rscript())'
clang++ -std=c++17 -arch arm64 Tests/bridge-driver.cpp -o Tests/bridge-driver
clang++ -std=c++17 -arch arm64 Tests/operation-driver.cpp -o Tests/operation-driver
clang++ -std=c++17 -arch arm64 Tests/engine-driver.cpp -o Tests/engine-driver
bash Scripts/test-form-descriptors.sh
export STATSDIRECT_FORM_TRACE="$(mktemp -d "$PWD/.build/form-trace.XXXXXX")"
for test in managed_scripts engine agreement menu data_graphics sessions analysis_defaults form_contracts form_branches form_follow_ons upstream_update distribution_update core_5_0_13 core_2026_09_30 distribution_menu beta_feedback follow_on follow_on_numerics group_identifier write_back help_examples help_regression_r r_operations charts box_whisker acquisition_record chart_replay recipe_regressions chart_recipe_regressions distributions; do
  python3 "Tests/test_${test}.py"
done
python3 Tests/test_form_coverage.py
python3 Tests/test_combined_forms.py
# The engine's record of a run and the R scripts its writer makes from it (the statsdirect_r_script entry), run in R against the engine's results.
python3 Tests/test_run_record.py Tests/operation-driver Tests/engine-driver
if command -v node >/dev/null 2>&1; then node --test Grid/*.test.mjs Learn/*.test.mjs Report/*.test.mjs; fi

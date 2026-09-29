# StatsDirect 5.0.13 on Mac — integration audit

29 September 2026, Apple Silicon, .NET 10, R 4.6.1. Mac preview **0.3.12** incorporates engine **5.0.13**, commit `30fa75dc342dfe0123c6663bad1f8495f2ec9bab`, and help commit `5d78253cb44bb8f08bbaff72b9014e386bb6a773` (399 topics).

The engine advances from 5.0.8. Updates include regression and Cox fitting, survival, agreement/ICC/kappa, meta-analysis, noncentral-t calculations, contingency and exact tests, frequencies, proportions and rates. Operation definitions, report templates and help are imported together. The Mac copy of `Nonparametric.cs` is refreshed with only the two unused DevExpress imports removed. No calculation is replaced by R.

## Evidence

- The normal Mac build passes: 881 source/asset hashes, the upstream 1,552-check distribution suite, original operation fixtures, live native bridge, agreement SVG, menu/data/graphics, concurrent sessions, preferences, normality and distribution/report checks.
- **13 additional upstream suites pass**: GLM fitting, correlation/regression, Cox, agreement, survival, meta-analysis, noncentral t, crosstabs, frequencies, exact tests, chi-square, proportions and rates. The suites with numbered totals account for **61,076 checks**, plus the GLM suite. Their complete output is saved in the compressed logs alongside this document.
- The suites compile against the actual Mac headless assembly, except the self-contained GLM source project. Frequencies uses the Mac worksheet reader instead of the absent Windows cell-selection helper, retaining all expected values; its 3,603 checks pass. One Crosstabs block tests a Windows DataGridView control and is explicitly omitted; calculation, score-handling, progress and cancellation checks remain. No numerical expectations or tolerances are relaxed.
- Freshly regenerated R references pass **6,360 noncentral-t cases / 31,541 assertions** and **29,130 rate figures across 587 cases**. The noncentral-t R implementation independently conditions on the normal numerator, rather than the engine's chi-square denominator. Small differences from saved upstream fixtures are tested, not assumed equivalent.
- The **4,902-case distribution audit** has no change in any candidate output or status from the [5.0.8 audit](../Core-5.0.8/README.md). Inputs and fresh R output are also byte-identical. The same 322 candidate discrepancies against R have identical records and retain their previous independent high-precision adjudication; they are not reported as direct agreement with R. Hashes and source provenance are in [summary.json](summary.json).
- `Tests/test_core_5_0_13.py` passes through the Mac form/report bridge: corrected rate-difference limits against R; identical direct-standardisation results for worksheet and screen entry, including events greater than person-time; Cox precision `1e-9` with no splitting-ratio prompt and likelihood-ratio statistic checked against R survival; fractional observation counts rejected in the single-proportion form.
- Native app tests pass using the packaged 0.3.12 engine: HTML/PDF/DOCX exports, five-page PDF, report/partial-table clipboard paths, and the example workbook → selected PEFR pairs → engine → active report with SVG/R link → tutor context workflow. These are regression checks of the existing export and tutor integration, not a new live AI-service test.

This is numerical and host regression evidence, not certification of every Windows feature. Existing Mac platform limitations remain documented in [FullEngine/README.md](../../../FullEngine/README.md).

## Repeat

From the repository root:

```sh
./build.sh
python3 Tests/UpstreamSuites/run.py --dotnet /path/to/dotnet
python3 Tests/CoreDistributions/compare.py \
  --baseline dcc2af8f0ec55d736a98acac029297510195e2df \
  --candidate 30fa75dc342dfe0123c6663bad1f8495f2ec9bab \
  --dotnet /path/to/dotnet --output .build/core-distributions-5.0.13
python3 Tests/test_chi_square.py .build/analysis-driver
Scripts/test-report-export.sh "$PWD/StatsDirect Viewer.app"
Scripts/test-learning-workspace.sh "$PWD/StatsDirect Viewer.app"
```

Compile `.build/analysis-driver` from `Tests/analysis-driver.cpp` with `clang++ -std=c++17 -arch arm64` first. For fresh R references, copy `FullEngine/Upstream/tests/NoncentralTRegression/references.tsv` into a scratch directory and run its `reference.R` with that working directory. Generate rates with `figures-rates.R cases-rates.txt output.txt` from the upstream Rates benchmarks directory. Substitute those generated fixtures in the respective `.build/upstream-suites/<suite>/bin` directories and run the compiled suite again. Do not overwrite the pinned upstream fixtures. The regenerated inputs and resulting logs used here are archived alongside this document.

# Engine revision 176eef77b986 on Mac

30 September 2026. Mac **0.3.13** incorporates Windows core commit `176eef77b9868a485de19e382db90fe36219c239`, advancing from `30fa75dc342d`. Both commits carry the upstream version label **5.0.13**. About now shows the revision so the two builds can be distinguished. Matching help: `9894a2641329159fb0e251e5b6bb657b9171f5ba`, 399 topics / 979 assets.

The update includes descriptive statistics, parametric and nonparametric methods, ANOVA, randomisation, sample-size calculations, clinical epidemiology, distribution calculations and the corresponding operation/report definitions. The Mac `Nonparametric.cs` copy is exactly the new upstream file apart from two unused DevExpress imports. Other platform copies were reviewed and have no upstream changes. Windows `ctlPDF` changes that also apply to the Mac calculator are carried into its host: small noncentral-t upper tails by symmetry, Spearman score bounds and safe Kendall score validation. Fractional t degrees of freedom are accepted. The numerical routines themselves remain the Windows source.

## Validation

- Full Mac build, 882 source/asset hashes, the original operation fixtures, native engine bridge, agreement SVG, all menu mappings, data/graphics, multiple open forms, analysis defaults and previous numerical regression checks pass.
- **21 upstream suites pass** against this core: the previous 13 plus Randomization, SampleSize, ClinicalEpidemiology, Parametric, Descriptive, Nonparametric, AnalysisOfVariance and Distributions. Suite results, exact assembly hash and compressed logs are recorded in [summary.json](summary.json).
- Fresh R 4.6.1 references are generated and checked for **six menus**: ClinicalEpidemiology, Parametric, Nonparametric, Descriptive, AnalysisOfVariance and SampleSize. Five pass directly. Descriptive has 19 skewness discrepancies, with R residuals no greater than `2.5924015658080915e-17` against the engine's exact zero. Independent rational arithmetic on the exact binary64 inputs proves all 19 samples symmetric with third central moment zero: the engine is correct. The raw failing log and separate adjudication are retained. All other descriptive comparisons and its bootstrap checks pass. Both generated cases and expected figures are used; references and full validation output are archived here.
- The **4,902-case distribution audit** reproduces every prior candidate result and status exactly. Inputs, candidate output and fresh R output are byte-identical to the [5.0.8 audit](../Core-5.0.8/README.md). The same 322 R discrepancies have identical candidate records and retain their earlier independent high-precision adjudication; they are not counted as direct agreement with R.
- **1,156 Mac calculator cases pass**: 1,133 completed calculations checking 2,327 probabilities, plus 23 invalid-input cases. They use the upstream expected results and stated tolerances, through real Mac prompts and report generation. This catches the small noncentral-t tail, fractional t degrees of freedom and rank-limit hosting changes.
- Mac form/report regressions cover a one-observation summary, two-way ANOVA on quarter-unit differences around `1e15` against R, signed-rank differences near `1e-320`, and Gini/diversity bootstrap seeds. Identical seeds reproduce the numerical reports; changed seeds change bootstrap results. The seed is recorded in both report and input history.
- Packaged-app tests pass HTML, PDF and DOCX export, report/partial-table clipboard handling, and example workbook → selected PEFR pairs → engine → active SVG report → R link/tutor context. This verifies existing app integration; it does not test live AI-service replies.

## Boundaries of the tests

The upstream suites reference the actual Mac headless assembly, except the self-contained GLM source project. Frequencies uses the real Mac worksheet reader in place of the Windows selection helper. The Crosstabs test of a Windows DataGridView control is explicitly omitted.

Distributions retains the unchanged numerical range, multiple-comparison and inverse tests. Its Windows `ctlPDF` control cannot run on Mac. The Mac fixture test instead checks every supported forward-input case; **894 inverse-probability or direct rank-score input routes** are explicitly counted as unsupported in the current Mac form, not passed or silently ignored. No expected numerical values or tolerances are relaxed.

R-based LOESS and method-comparison regression remain deferred in the Mac menu, as before; importing the updated operation definition does not enable their Windows R-host integration. Existing platform limits remain in [FullEngine/README.md](../../../FullEngine/README.md).

## Repeat

From the repository root, with the pinned submodule and .NET 10 / R 4.6.1 available:

```sh
./build.sh
python3 Tests/UpstreamSuites/run.py --dotnet /path/to/dotnet
python3 Tests/CoreDistributions/compare.py \
  --baseline 30fa75dc342dfe0123c6663bad1f8495f2ec9bab \
  --candidate 176eef77b9868a485de19e382db90fe36219c239 \
  --dotnet /path/to/dotnet --output .build/core-distributions-176eef7
Scripts/test-report-export.sh "$PWD/StatsDirect Viewer.app"
Scripts/test-learning-workspace.sh "$PWD/StatsDirect Viewer.app"
```

The normal build includes `Tests/test_core_2026_09_30.py` and `Tests/test_distribution_menu.py`. For each fresh R menu above, run its upstream `benchmarks/make-benchmarks.R` in a separate scratch directory, passing `cases.txt expected.txt` (some scripts use these fixed filenames instead). Copy the generated `.txt` fixtures into that suite's `.build/upstream-suites/<suite>/bin/benchmarks` and run `dotnet .../Upstream<suite>.dll` again. Preserve the pinned upstream fixtures. Generation metadata, reference hashes and test results are archived in this audit.

For the fresh descriptive references, `python3 Tests/adjudicate_descriptive_roundoff.py --dotnet /path/to/dotnet --references /path/to/fresh/Descriptive` instruments the upstream test to emit every mismatch and independently checks exact symmetry. It does not change the raw exit code, expected values or tolerances.

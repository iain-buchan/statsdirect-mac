# Engine 5.0.14 on Mac

30 September 2026. Mac **0.3.14** pins the official engine **v5.0.14** tag, commit `b10edfefa54bb9ebcdb36b9019b428f75c7d136d`.

Compared with the `176eef77b986` revision already shipped in Mac 0.3.13, upstream changes only `StatsDirectUI.csproj` (version 5.0.13 → 5.0.14) and `changelog.md` (the release heading and summary). All calculation source, tests, operation definitions and report templates are unchanged. The manifest contains the same 882 paths: 881 hashes match, with only the project file's version hash differing. The matching help remains `9894a2641329159fb0e251e5b6bb657b9171f5ba` (399 topics, 979 assets).

The new Mac build displays engine 5.0.14 and revision `b10edfefa54b` in About; generated report footers use the same engine metadata. No numerical or host adaptations are needed for this tag.

## Verification

The normal Mac build reruns the upstream distribution regression (1,552 checks), original operation fixtures, native engine/report bridge, agreement SVG, menu and data/graphics tests, concurrent forms, analysis defaults, numerical regressions and 1,156 Mac calculator cases. Build output and the exact engine assembly hash are recorded in [summary.json](summary.json).

The [previous integration audit](../Core-176eef7/README.md) remains the numerical evidence for the unchanged source: 21 upstream suites, six freshly generated R reference groups and the 4,902-case distribution comparison. Those additional suites are not claimed as newly rerun for this metadata-only release. The earlier audit retains all discrepancies and their independent adjudication, including the 19 R skewness rounding residuals on exactly symmetric samples.

The packaged and re-extracted applications are checked for version, engine metadata and matching engine bytes, and pass deep/strict ad-hoc signature verification. Existing preview/platform limitations remain unchanged; this is not an Apple-notarised release.

To repeat the build, initialise the pinned submodule, then run `./build.sh` with .NET 10 and R available. `python3 FullEngine/import_upstream.py --check` verifies provenance without modifying files.

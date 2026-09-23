# Verification — 23 September 2026

## Numerical library

The NativeAOT shared library compiled successfully and passed Tests/test_engine.py. This exercises the exported C ABI, the same entry point called by the Mac host.

- Upstream fixture: all ten numeric values agree within rel=1e-11/abs=1e-12; power agrees when rounded to the expected 98.98%.
- Swapping before/after reverses the effect and t statistic and preserves two-sided P.
- Multiplying both columns by two scales effect, SD, SE and confidence limits, preserving t and P.
- Incomplete pairs are excluded together.
- Constant differences, insufficient complete pairs and invalid confidence are explicitly rejected by the prototype wrapper.
- Changing the first observation changes the calculated result.
- Vendored source hashes are checked against the recorded provenance manifest.

These are upstream expected-value comparisons, not a fresh Windows executable replay or an independent R run. The full-engine parity suite remains outside this prototype.

## Native Mac interaction

Verified through the actual running app:

1. Launch creates distinct help-library and example-data tabs.
2. Analysis → Parametric methods → Paired t test — PEFR example runs and opens Report 1.
3. Report 1 shows mean 56.111111, t 4.925774, df 8 and two-sided P 0.00115557.
4. Method help opens a separate help tab, retaining the data and Report 1 tabs.
5. Editing the first Before input from 312 to 332 and pressing Cmd+T opens Report 2 with mean 58.333333 and the Edited example data label.
6. Selecting Report 1 still shows its original 56.111111 result and Original worked example label.
7. The test edit was restored to 312, and Report 1 was selected for handoff.

The workspace and result layout were visually inspected. Prior-version PDF export/print preview checks are recorded in Git history; the PDF controls are retained but were not re-tested in this version. Copy into Office is not verified. Close-tab and next/previous actions are implemented but are not claimed here as manually tested.

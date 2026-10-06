# Mac 0.3.17 beta feedback validation — 6 October 2026

Release **v0.3.17**. Core calculation source remains the pinned 5.0.14 revision; no upstream numerical source was changed.

## Changes

- Fixed live tutor application access: the pinned runtime needs its dynamic-tool host enabled even when code mode is disabled. Shell, plugins, file execution and computer environments remain disabled; the native tool allowlist and per-question document scope remain enforced.
- Streamed replies, responsive Stop, locally rendered Markdown/equations and highlighted R with Copy/Open in R. Scripts open for review and run with the existing Run control.
- Per-lesson conversation/draft, expanded laptop conversation, current skill/R preferences in the tutor context, automatic option saves, readable selectors, clearer course/provider/assessment labels, correct question-set counts, separate post-feedback reflection, and refreshed evidence choices.
- Learning exports: HTML, PDF, DOCX, JSON and text; semantic MathML becomes editable Word equations. Version and bounded event diagnostics omit credentials and raw tool arguments.
- Report notes, Remove plot/Remove result and Undo; notes survive export and UI controls are removed from exports/clipboard.
- Generated data declare their heading row; invalid random generator inputs return a correctable form. Basic search is exact replacement; advanced search supports comparisons/expressions/counting without the missing Windows helper failure. Missing-value entry no longer exposes the internal sentinel.
- Live worksheet selection snapshots, selectable ranges for 2×2 forms, clearer labels-versus-values prompts, consolidated meta-analysis option forms with saved defaults, histogram bin count, and source-plus-derived worksheet copies aligned to selected rows.
- Dropdowns open below their buttons. Missing submodules initialise at the pinned revision. R comparison tests are separate from normal builds, Rscript is discovered portably, and an optional Docker SDK build path is provided.

## Verification

`./build.sh` passed: upstream source/hash check, 1,552 upstream distribution checks, original operation replay, .NET publish, Swift compile and app packaging. Deep strict local signature verification passed.

`./test.sh` passed: engine/reference comparisons, agreement, menu entry points, data/graphics, parallel sessions, analysis defaults, upstream and distribution regression cases, new beta-feedback cases and 63 JavaScript tests. The learning suite was repeated after the question-count display refinement (26 passed).

`python3 Tests/run_beta_feedback.py --live` passed using an isolated test application and the existing StatsDirect ChatGPT sign-in. The live question used only bundled teaching data: the native worksheet supplied nine PEFR pairs; the actual engine returned mean before-minus-after difference 56.111111, t=4.925774, two-sided P≈0.00115557 and the SVG agreement chart. The advanced response streamed and included the actual values in executable R code. This verifies that connection and workflow; it does not validate every possible AI answer or teaching adaptation.

Native checks cover all 12 curated guides, provider pack/practice/work/evidence/return flows, saving preferences, safe rich text, per-lesson history, a 960×680 conversation layout, opening R without automatic execution, report notes/removal/undo, all report and learning export formats, paginated PDFs, and full/partial-table clipboard payloads. A subsequent native run verified the final Word equation export and in-flight Stop interaction. DOCX inspection found an Office Math fraction and radical with no duplicate TeX text. Existing Excel clipboard compatibility was checked at the payload level; a real Excel paste was not repeated.

### Final release checks

The complete build and engine/R regression suite passed again before release, followed by these additional checks:

| Area | Result |
|---|---|
| Menu coverage | All 224 commands, 208 offline help links, 206 input hosts and two explicit R deferrals checked. |
| Excel | `test.xlsx` edited round-trip preserved all 11 sheets, 14,363 populated cells and 22 formulas, styles, types and cached results; verified independently with openpyxl. Recalculation and failed-save protection passed. |
| CSV and R files | Native/grid round-trips passed for UTF-8, UTF-16 and Windows-1252 CSV; RData/RDS retained factors, logicals, matrices, dates/times, row names, NA/NaN/Inf and edits. Invalid input/save protection passed. |
| R | Generated scripts and engine comparisons, selected ranges/missing pairs, session persistence, errors, inline plots and repeated plotting passed. R installer detection, package checksum/signature rejection and download error fixtures passed; no installation was performed. |
| Learning | All 12 examples ran through the real engine and independent R checks. Native lesson/provider/assessment/evidence/export flows and bounded tutor context passed. Mock runtime covered streaming, tool routing, duplicate/stale requests, cancellation, limit errors, retry and disconnect recovery. |
| Contingency tables | Selected C5:D6 reached the four-cell form without unrelated data; R comparisons, table edits, exact tests, simulation repeatability, invalid-input rejection and cancellation passed. |
| Large grid | In native WKWebView, a 10,000 × 10 paste grew the sheet without truncation, copied/exported all values, and supported atomic undo/redo. An oversized paste left data intact. The final run measured 61 ms for the paste operation on this Mac; this is not a general performance guarantee. |
| Derived data | Added a regression and corrected worksheet snapshots so pasted numeric source cells retain their numeric type when copied beside derived columns. |
| Reports | HTML/DOCX and five-page PDF checks passed, including SVGs, notes, removal/undo and full/partial clipboard tables. Learning DOCX retained editable equations. |
| Update service | Version comparison, published-release filtering, malformed responses, DNS/rate-limit/server fallback, cancellation and live GitHub lookup passed. |
| Distribution | Final ZIP integrity, version, absence of credential files, and deep strict code-signature checks passed after extraction. Native integration ran with that extracted app's resources and engine using `python3 Tests/run_beta_feedback.py --app '.build/release-0317-extracted/StatsDirect Viewer.app'`. The actual extracted executable also launched; About showed 0.3.17 / engine 5.0.14 and the Help dropdown placement was inspected. |

The final native suite used the mock tutor from startup and did not request Keychain access. The earlier live-account check above remains a separate, explicitly identified result.

## Keychain correction

The previous bundler replaced the official OpenAI Developer ID signature with ad-hoc signing. It now preserves and verifies the vendor signature and expected signing identity, preventing each differently signed build from appearing as a different credential owner. Routine native tests install the protocol fixture before opening Learning and do not initialise Keychain; the full native suite passed with this setup, and process inspection confirmed no real tutor process was launched. The fix keeps credential storage in Keychain; no Mac password is collected or stored, and no Keychain access controls were weakened. An existing entry may still require macOS approval when transitioning from the old locally signed component.

## Limits

Docker is not installed on this Mac, so that optional path was syntax checked but not executed. The ordinary .NET SDK build was executed. The app remains locally ad-hoc signed, not Apple Developer ID signed/notarised. No assessment email was sent and no accreditation is granted automatically. The sporadic single-column complaint was not independently reproduced verbatim; selection state, row ranges and single-column engine paths are covered by the checks above.

## Release package

`StatsDirect-0.3.17-macOS-arm64.zip` (156,434,052 bytes) passed archive integrity and deep strict signature verification after extraction. The extracted ChatGPT component retains OpenAI Developer ID team `2DC432GLL2`. `SHA256SUMS.txt` accompanies the ZIP on the [release page](https://github.com/iain-buchan/statsdirect-mac/releases/tag/v0.3.17).

SHA-256: `efb97e2de1626e7f31d9dbc5010c7e238c43d0496079e2293ee1d0640b5517a9`.

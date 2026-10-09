# Mac 0.3.23 — wider validation and host fixes

## Changes

- Cuzick’s trend test opens its prepared score table with one editable score per group.
- Grouped covariance uses the saved confidence default (normally 95%); disabling automatic confidence restores the question.
- Control-chart sequence input accepts the ISO dates imported from Excel, on the Windows OLE date scale. Other numeric inputs remain strict.
- Classic Excel notes move with inserted columns, including their cell references and move/size anchors. Legacy form controls remain protected from unsupported edits.
- The example workbook heading is corrected from GMTA to GMAT in the Mac copy and the core source. Core numerical code is unchanged: 5.0.14, revision `70eeec4` (workbook-only change from `00aa1ce`), [upstream PR #2](https://github.com/iain-buchan/statsdirect/pull/2).

## Statistical and worksheet checks

The baseline help replay grows from 33 to 53 worked examples. Explicit selections cover crossover groups, Latin square, nested ANOVA, covariance replicates, Poisson exposure and dummy predictors, matched logistic regression, stratified log-rank, repeated survival data, and the separate Cochran and two-sample z examples. Both quantile interval variants run separately; seeded Gini and diversity bootstraps reproduce the published results.

Comparisons retain signs and require the help’s printed precision. Explanatory prose is excluded from expected report output. Only conditional-logistic estimates allow an additional 1e-7 relative tolerance, reflecting documented sensitivity to iterative stopping; independent R checks confirm the matched model and Poisson model deviances to 1e-10. The complete workbook-example survey reports **53 matched analyses, 15 generated charts, and one explicit LOESS deferral**. SVG geometry is tested separately. This is not a claim that every example in all 399 help topics is covered.

The engine/R suite, 101 JavaScript tests, Excel import/round-trip/edge/insertion/compatibility tests and CSV/R file tests pass. Structural insertion includes 1,000,010 populated cells and checks atomic refusal, repeated saves, undo, formulas, formatting, notes and chart anchors. Import tests include Excel’s row/column endpoints and more than one million populated cells.

## Real Microsoft Office checks

Microsoft Excel and Word **16.113.3**, on this Mac:

- Excel opened the small and streamed formatted-workbook exports without repair messages. Manual recalculation and save produced independently verified formula results, while the table, chart, percentages, widths and merged label remained intact.
- Excel opened a streamed workbook with a shifted classic note. The original text, author and value stayed attached to C2 after save.
- Copying the full StatsDirect HTML report into Excel produced separate numeric cells, including negatives, scientific notation, a chi-square table and all 65 rows of the long test table.
- Word opened the exported DOCX and accepted the report clipboard contents. Both retained the agreement chart, three tables and the final table row across four pages; saved package contents were checked independently.
- Native Excel refuses insertion through part of an array. It can expand an Excel table; selecting a column crossing a merge can expand the selection to the whole merge. StatsDirect conservatively refuses those interior structural edits until it can preserve their full semantics. Whole structures can move intact.

## First-run and tutor checks

The real pinned ChatGPT runtime passes signed-out initialization, browser sign-in URL generation, cancellation and the controlled dynamic-tool protocol. These tests use fresh storage without account credentials. Mock integration covers successful authentication and failure paths. The live check also passes using the existing signed-in account and fictional example data: ChatGPT reads the nine PEFR pairs through the app tools, runs the real paired t test, creates an SVG agreement report, and streams the correct difference and equivalent R code. The native document-sharing confirmation is exercised before that request.

The real CRAN R download passes size, SHA-256, publisher-signature and macOS installer assessment checks. An isolated native fixture simulates missing R, a failed download, retry, installer handoff and completion: the pending script is retained and resumes with an output plot. It deliberately does not launch Installer or replace the existing R installation. A physical clean Mac installation and interactive first-time OAuth completion were not performed.

## Remaining limits

LOESS and method-comparison regression still have explicit R-based menu deferrals; R sessions remain available. Unsupported structural edits involving pivot/slicer/linked-data metadata, controls or certain Excel extensions are refused before mutation and results can open separately. Reading those workbooks is unaffected. This grid does not render all Excel formatting or provide arbitrary column dragging.

Apple Developer ID signing and notarisation were excluded from this work. The preview remains for Apple Silicon, macOS 14 or later.

## Packaged download

The Release build has no Swift warnings. The extracted ZIP passes archive integrity, executable/engine/resource identity, existing ad-hoc signature verification and matching debug-symbol checks. Signing credentials and notarisation are untouched.

- Application: `StatsDirect-0.3.23-macOS-arm64.zip`, 156,290,456 bytes; SHA-256 `7b6ffb2672d3a858485b0af1f71aeb4e0839e6a05db8d65d15f879460abb8165`.
- Symbols: `StatsDirect-0.3.23-macOS-arm64-symbols.zip`, 1,955,188 bytes; SHA-256 `a17865967d91937de03a54d3b3e5282038752dbb09e47d4a1813f4037622c7bb`.

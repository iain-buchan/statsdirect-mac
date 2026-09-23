# Verification — full headless engine, 23 September 2026

The updated application was built, launched and exercised on this Apple Silicon Mac. Code-signature verification passed for the local app bundle.

## Full engine

- Compiles the complete numerical/Builtins calculation source with the platform exclusions documented in FullEngine/README.md.
- Loads 284 original operation definitions.
- Original unmodified OperationsTester: paired t test passes all 15 specified outputs, exact sign passes all 11; one empty test is skipped. This checkout has no other populated operation tests.
- All 871 vendored source and asset files match the hashes recorded from upstream commit c56f888bd95604f9d656e90ad0236493a96f2ae7.
- The original C#/VB script engine compiles the paired operation's expression during execution.

## Application bridge

Tests/test_engine.py invokes a native test driver that loads the same hostfxr library and managed engine as the app. The driver avoids Apple's protected system Python process, which cannot host CoreCLR on this Mac.

- The live operation output agrees with all ten numerical fixture values and the formatted power.
- The engine's original HTML renderer produces the title, mean, confidence limits, P value and power expected in the help example.
- Swapping before/after reverses the mean, confidence interval and t statistic while preserving two-sided P.
- Doubling units doubles location/spread outputs while preserving t/P.
- Incomplete pairs are removed pairwise.
- Constant differences, insufficient usable pairs and invalid confidence levels fail explicitly.
- Editing the data changes the calculated report.

## Native UI

Using the application's native menu, Analysis → Parametric methods → Paired t test — PEFR example created Report 1. It displayed the original engine HTML: mean 56.111111, CI 29.842662 to 82.37956, t 4.925774, two-sided P 0.0012 at the engine's display precision, and power 98.98%.

Method help opened the original paired t topic in a separate tab, retaining the data and report tabs. Editing the first before value from 312 to 332 and pressing ⌘T created Report 2 with mean 58.333333, t 5.556956 and power 99.78%. Returning to Report 1 confirmed its original values were unchanged. The data value was restored to 312, and Report 1 was left selected.

## Limits

This verifies the paired viewer path and the two populated upstream tests. It does not establish coverage of every built procedure. Full chart rendering, external R integration, Office/RTF export, printing fidelity and notarization are not verified by this update. The optional agreement outputs are checked by the upstream paired test, but agreement rendering is off in the viewer.


## R tab update

Built the native R pane and tested it with the installed R 4.6.1. File → New R Tab (⌘R) started an R session alongside data and help tabs. Running the prefilled script produced paired t = 4.9258, df = 8, P = 0.001156 and mean difference 56.11111. Additional ANOVA code entered by the user also ran in that tab.

An isolated instance of the same RPane implementation verified that a variable assigned before a deliberate R error remained available in the next run; the error was displayed and the session returned to Ready. Stop / Reset terminated a script sleeping for 60 seconds. The next run started a fresh process and confirmed the old variable was absent. The corrected layout was visually inspected in that isolated instance so the user's active script and session were not interrupted.

The first R build is running in the user's current session. The final layout and contextual Save Script label are installed for the next app launch. The full calculation engine was unchanged by this update.


## Window frame controls

Added explicit titlebar Close, Minimise, Resize / Restore and Move controls using native AppKit window operations. An isolated window using the same frame-control implementation was visually inspected. Resize enlarged the window and restored its prior size; the Close control closed the test window. The move control uses AppKit's window-drag API, and custom sizing remains available by dragging the native window edges. The main viewer retains its miniaturizable window style. Closing the main window also checks for unsaved/running R work.

The on-disk executable was replaced atomically and re-signed, preserving the running user's R process and unsaved script. The final frame controls appear on the next launch.


## R launcher tab

Added a permanent “+ R session” tab. A separate copy of the full application verified that clicking it created R Session 1, a second click created R Session 2 while retaining Session 1, and closing a session left the launcher available. The final layout was visually checked with the toolbar and tab strip fixed at the top. The launcher is not counted as an open document. No changes were made to the user's active R session.


## Glide data-grid update

Glide Data Grid 6.0.3 is bundled locally with React 18. The TypeScript check and four data-store tests pass: rectangular paste with growth and atomic undo/redo, quoted clipboard text and numeric validation, CSV quoting, and selected-range extraction. The original operation tests and the native bridge tests still pass; an additional native test confirms arbitrary selected column names reach the engine's HTML report with unchanged numeric results.

A separate copy of the full Mac app displayed the real Glide canvas and accessible grid cells in its own tab. Live editing and analysis were observed in that window: the ninth before value changed from 290 to 333, and a new report displayed mean 60.888889, t 4.874386, and the input snapshot containing 333. An earlier report remained open in a separate tab. The user's open test window and its data were preserved. Native CSV-dialog and Office-specific clipboard behavior have not yet received a full manual verification pass.

This is not a million-row performance result. The store is sparse and text-backed, with numerical validation on analysis; typed column storage, Excel file import and benchmarking remain.


## Excel workbook update

Added native `.xlsx` Open/Save and a separate worksheet selector inside each imported grid tab, using ClosedXML 0.105.1 in the existing in-process .NET host. The bundled use case is upstream `StatsDirectUI/Assets/Data/test.xlsx` (the repository has no `text.xlsx`). Its unmodified source hash and revision are in Content/Examples/README.md.

The native C ABI test opens the actual workbook, imports its 11 sheets into the actual JavaScript workbook model, changes Parametric!A2 from 312 to 332, exports, and independently reads the result. All 14,355 populated cells, 22 formula expressions, cached formula results, worksheet names/visibility, cell types, number formats, fonts, fills, borders and alignment compare with the source, except the intended value change. A separate change to Graphics!T2 refreshes both dependent arithmetic results while retaining their formulas. Typed-export cases cover numerical values, dates, booleans, text identifiers with leading zeros, blanks and literal text beginning with an equals sign. Attempts to overwrite formula cells fail without changing the destination. Corrupt input and released workbook handles fail explicitly.

Eight JavaScript store/workbook tests and the TypeScript check pass. The existing engine fixtures and native paired-test regression tests still pass. Swift compilation and app signature verification passed.

In the isolated Mac test application, Open test.xlsx created a new document and displayed all 11 worksheet buttons with Parametric selected. Headers and data aligned with the Excel row numbers. Running the paired test on the imported first two columns produced a separate report with nine complete pairs. The native Save Excel dialog wrote a workbook, and the status confirmed that all worksheets were saved; the output file independently contained all 11 sheets. The final formatting-preserving export implementation was checked through the same native C ABI after that UI build. Existing running application sessions were retained.

Limits: `.xlsx` only; no legacy `.xls`/`.xlsb`, macro or password support. The grid displays values in its own style and is not a full Excel renderer. Formula cells are read-only; after edits, analysis on their potentially stale values is blocked. Supported expressions refresh at export, unsupported expressions retain their formulas with uncached results and a status message, and the file requests recalculation in Excel. Import limits are 50 MB compressed, 256 MB expanded, 128 sheets and 500,000 populated cells. Native Excel recalculation and general workbook feature conformance have not been independently verified in Excel itself.


## Chi-square r × c screen-data form

The original `ExactChiRbyCScreen` operation runs through the same in-process C ABI as the native form. The 4 × 3 help example produces Pearson χ² 9.958800186741366 (6 df), P 0.1263977896899532; G² 10.186039087816248, P 0.11703298636014443; Fisher–Freeman–Halton P 0.1426335176324087. These agree with independent R chisq.test, an independently calculated G statistic and pchisq, and fisher.test. Expected counts, cell contributions and the original low-expectation warning remain in the engine report.

Regression checks cover transpose invariance, edited counts, report options, custom trend scores, fixed-seed Monte Carlo reproducibility, validation of margins/counts/confidence/settings, individual zero counts, the original exact-test threshold and cancellation without a partial report. Four additional JavaScript tests check the actual form model and checkbox definitions, bringing the grid/model total to twelve. Both TypeScript entries pass type checking. No vendored calculation sources changed.

## Paired agreement SVG

The original TPaired operation receives doAgreement=true, calculates the limits, and invokes the original Ties chart renderer. Only Mac rendering boundaries changed: managed alignment values and CoreText font metrics replace Windows/GDI objects. The original Talbot axis-label algorithm is retained in platform-adapted rendering copies. SVG uses Arial consistently for drawing and measurement.

The nine-pair example retains exactly the same paired-test outputs with agreement on or off. Its limits are −10.868664691913338 and 123.09088691413557 around mean difference 56.111111111111114. The SVG test verifies all nine marker coordinates against paired means/differences, the three horizontal reference lines, axis bounds, safe label escaping, exclusion of missing pairs and redraw after an edit. Geometry tolerance is 0.0001 SVG units because the original renderer uses float intermediates. The standalone verified chart is Content/Examples/paired-agreement.svg. Broader chart conformance and Office paste behavior remain untested.

Native verification: selecting Agreement analysis (SVG) in the Glide tab and running the paired test created a new report with the original agreement limits and a visible SVG plot. The chart labels, all nine markers and three reference lines were visually inspected in WKWebView. The File menu enabled Save Chart as SVG for that report. The chi-square tab was also displayed with the embedded Glide grid and original option controls; its help-example report appeared in a separate tab.


## Complete Analysis menu update

The imported Windows menu has 148 commands, 135 unique operation definitions and 135 verified offline help paths. The interactive C ABI smoke test starts every enabled definition: 133 reach a real input boundary. LOESS and method-comparison regression are explicitly deferred because the engine R bridge still uses Windows discovery/graphics; their help and the separate native R tabs remain available.

The general host completes 47 representative analyses, including count/proportion/rate tests, sample size, random allocation, diagnostic tables, summaries, t and rank tests, ANOVA (including repeated/nested designs), grouped covariance, simple/multiple regression, agreement, Kaplan–Meier/log-rank, kappa, Mantel–Haenszel, meta-analysis, frequency tables and all ten distributions. These are end-to-end functional checks; they are not numerical certification of every menu entry. Fourteen independent R comparisons verify t-test confidence limits, Fisher P, one-way and replicated two-way ANOVA, Spearman correlation, regression slope and grouped-covariance interaction. Paired results and the agreement SVG remain checked against the original fixtures. Validation retry, stale-token rejection, the single-operation guard and cancellation while waiting for input are checked separately.

Seventeen JavaScript tests cover the existing grid/workbook paths plus ordered column selection, aligned missing tails, stale/error formula rejection, paste bounds and saving complete generated tables without a backing workbook. TypeScript and Swift compile checks pass. Original vendored calculation files remain unchanged. Native verification subsequently succeeded in a separate packaged app: the complete menu hierarchy was inspected, the general paired-test form selected the PEFR worksheet columns, 95% confidence and agreement, and produced the expected separate report with a visible nine-point SVG and both limits. Fisher's exact test opened its embedded 2 × 2 Glide grid; pasting 1/9 and 11/3 generated a separate report with two-sided P = 0.0028, and its method link opened the correct help tab while both reports remained open. Existing user sessions were retained.

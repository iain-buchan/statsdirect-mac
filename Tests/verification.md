# Published Mac update — 26 September 2026

Published [v0.3.10](https://github.com/iain-buchan/statsdirect-mac/releases/tag/v0.3.10), targeting commit `36bc277e5b9f0500e859e83ef7c3c5fa12f68c3f`, with the Apple Silicon application ZIP and SHA256SUMS.txt. Both assets were uploaded and verified before the draft was made public and latest. The ZIP is 153,314,538 bytes; SHA-256 `7484d55956fc7b8cda5d3f63abaf28339e221ee404ec1571a2db3f3e5739cd48`, also confirmed by GitHub asset metadata. Archive integrity and the extracted app’s deep, strict local signature verification passed. The release notes identify its ad-hoc signing/notarisation limitation and manual installation.

The real public update endpoint and website latest-release redirect both resolve to v0.3.10. Existing update-service tests passed. An isolated copy of the actual 0.3.9 app displayed “StatsDirect v0.3.10 is available” both automatically and when selecting Help → Check for Updates; its dialog correctly stated “You are using 0.3.9.” No updater code change was required: prior source pushes had not created a GitHub release.

# Example workbook menu — 26 September 2026

Mac build 0.3.10 replaces Help → Examples → StatsDirect Example Workbook with the direct Help → Example workbook command. Native UI verification in an isolated app confirmed the shortened entry and that selecting it opens test.xlsx with all 11 worksheets. The shared menu definition also supplies the macOS menu bar. Swift compilation and deep, strict signature verification passed for both packaged app paths. The calculation engine and workbook are unchanged.

# Teaching content audit — 26 September 2026

Mac build 0.3.9 incorporates the [educational-content audit](../Docs/Learn/CONTENT-AUDIT-2026-09-26.md): all seven lessons, 30 fixed questions, both tutor policies, the sample course pack, archived teaching content and R handoff explanations. Fourteen question wordings were revised; all answer keys remain unchanged.

The 16 learning/history/archive tests passed, including seven executed R examples and plots, independent numerical choices, preserved historical scoring and correct lesson attribution. All seven lesson workflows were exercised through the unchanged engine. All 37 generated-R operation fixtures and the existing data/setting handoff cases passed. Swift compilation, 0.3.9 packaging and strict local signature verification passed. Native UI checks in an isolated app confirmed the paired question and risk/NNT corrections without replacing the user’s open documents. The 5.0.8 engine binary is unchanged.

# Windows 5.0.8 core validation and Mac integration — 25 September 2026

The accepted core is `dcc2af8f0ec55d736a98acac029297510195e2df` (5.0.8). Before accepting it, the unchanged Windows numerical files were compiled independently of the Mac host and compared with 5.0.7 and R 4.6.1. The candidate completed 4,902 cases without a fault or timeout. All 322 candidate/R discrepancies passed independent high-precision checks under the documented tolerances; ten representative cases were repeated at 100 digits. The 400 ordinary seeded cases agree with R in both versions. Full inputs, raw outputs, source hashes, criteria and limitations are retained in the [numerical audit](../Docs/Validation/Core-5.0.8/README.md).

The Mac build imports all five new beta/special-function source files without modifying numerical algorithms. It verifies 879 source/asset hashes. The Mac distribution forms now request both tails directly from the new APIs; their old subtraction lost a t lower tail of 5e-41 as zero. Windows-only installer changes remain outside the Mac host. Existing platform copies, operation definitions, menus, workbook and imported help did not change in this core revision.

Validation passed:

- The upstream distribution suite: 1,552 checks, now included in normal builds.
- Original operation fixtures; paired analysis and SVG agreement geometry; all 224 menu commands and 206 enabled entry points; 47 analysis/calculator and 74 Data/Graphics cases; 14 R comparisons.
- Six interleaved forms, cancellation/validation and the complete saved-confidence/defaults suite.
- Existing normality/extreme-scale checks, plus new tiny t/F/chi-square tails, seven worksheet expressions using the updated SDMath functions, and the corrected 99.8% rate-ratio interval through the real report path. Reference calculations use stable R identities/forward-tail inversion where direct R quantiles are inaccurate.
- Dedicated chi-square tests, including independent R calculations, simulation and cancellation; all generated R-script checks and numerical comparisons.
- Full Swift build and package; strict local code-signature verification; packaged engine DLL and version metadata match the tested build byte-for-byte.
- Native About displays **StatsDirect 5.0.8**. Selecting Student's t from the menu opens its input form immediately. Entering t = −1e20 and 2 df produces a separate report showing lower tail `4.99999999999998E-41` and two-sided P `9.99999999999996E-41`, with the 5.0.8 footer and help/R links.

This remains a locally signed development build. The earlier help-suite and unsupported R-operation limitations below are unchanged; this does not certify every statistical procedure or Windows UI feature.

# Upstream refresh — 25 September 2026

The Mac build now uses Windows StatsDirect **5.0.7**, pinned to `c956b122c9b77683f58c4d10c221390183968cd3`, and statisticalhelp `d02543897aac61eb0a98e2c708628655c9e48072`. All 874 recorded engine source/asset hashes and 978 imported help-file hashes were verified. The bundled example workbook is byte-identical to the upstream workbook. The menu/help catalogue was regenerated; corrected operation titles are included.

The two changed Mac platform copies were reconciled with upstream: permutation-count formatting in Nonparametric and the zero-range axis message. The Mac distribution host also adopts the Windows normal-tail fix and the Kendall minimum of two observations. Numerical algorithms remain in the pinned upstream engine. About and report footers now read the imported version metadata.

Checks completed successfully:

- Full engine build and the original two populated operation tests (26 expected outputs; one empty test skipped).
- All 224 menu commands, 208 help links and 206 enabled input hosts; the two pre-existing R-dependent deferrals remain explicit.
- 47 completed analysis/calculator cases, 74 Data/Graphics cases and 14 independent R numerical comparisons.
- Paired-test output, original SVG agreement geometry, dedicated chi-square calculations against R, custom scores, seeded simulation, validation and cancellation.
- Six interleaved forms and the complete Analysis Options/default-confidence suite.
- New 5.0.7 regression checks: normality statistics under scaling by 1e300 and 1e-300 and translation by 1e12; Shapiro-Wilk against R; constant/two-value sample messages; tiny normal/F/Poisson tails against R; signed Kendall tau and the minimum sample size.
- All Mac-generated R-script checks and engine comparisons.
- Updated workbook round trip: 11 sheets, 14,363 populated cells, 22 formulas, cached results, types and styles; formula-input recalculation and invalid-file handling.
- Swift compilation; native About shows 5.0.7; the bundled workbook opens; the paired example runs with automatic 95% confidence and produces the expected report and SVG agreement chart. Its help link opens the refreshed offline topic, and the new R-code section expands correctly.
- Final app packaged with the rebuilt engine and content, verified byte-for-byte against the source build; local ad-hoc code signing and strict signature verification passed. This is still a development build, not a notarized installer.

The help repository's separate `RCode/check-rcode.R` suite passed **132 of 135** examples on the installed R. Three upstream reference checks remain unresolved; the imported help was kept unchanged:

- `agreement/mcr`: the optional `mcr` package is not installed, so this script could not run.
- `basic_descriptive_statistics/univariate_summary`: R prints the sum as `29985.239999999991`, while the literal expected fragment is `29985.24`.
- `regression_and_correlation/multiple_linear`: the Longley intercept and year coefficient differ in the final printed digit (`-3482258.63459583` versus `-3482258.63459582`, and `1829.15146461356` versus `1829.15146461355`).

At extreme numeric scales or very large offsets, normality statistics complete correctly but the existing chart axis renderer can report that the chart cannot be drawn. These tests do not claim complete Windows UI parity or coverage of every statistical procedure. The active user session was preserved; reopening the packaged app loads the updated engine.

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


## Dropdown menus, navigation and independent forms (23 September 2026)

Imported all Windows Data, Analysis and Graphics command trees, preserving label and operation order: 224 commands, 208 distinct operations and 208 existing offline help targets. All 206 enabled operations reach their first input; the two engine-R deferrals remain explicit. The complete menu suite passes 47 end-to-end analyses and 14 independent R comparisons; the Data/Graphics suite passes another 74 cases, including expected numeric/text transformations and SVG/text chart rendering without hidden renderer errors.

Plain arrow keys commit edited grid values and move in their indicated direction. Return moves down, modifiers retain the original shortcuts, and navigation clamps at table edges. Native tests exercised all four arrows in workbook and analysis cells, value-field entry and Escape cancellation. Both count-table hosts now fit the actual data dimensions; a 2 × 2 form shows exactly four entry cells plus headings.

Dropdown commands automatically open their first input. Separate forms retain their parameter state, report and suspended engine stack. A shared host execution lock is released at input boundaries and reacquired before the calculation continues; the original calculation source is unchanged. Six interleaved forms (including duplicate sign and paired tests, agreement SVG, seeded random allocation and generated data) match serial-run values, frames and input histories. Cancelling another form and rejecting stale/invalid input do not alter the remaining forms.

The command row contains File, Edit, Data, Analysis, Graphics, R, Help and Window. A separate document tab row provides direct selection and an accessible close button per document; Window retains the document list and keyboard switching. Closing an active generic form cancels only that job and releases it before removing the document. R and edited worksheets retain their unsaved-work checks.

Prototype boundaries: sort/filter generate new worksheets, basic search uses the advanced engine form, categorisation uses explicit boundaries, and Graphics Options exposes colour and boxed axes. These are working host equivalents, not full Windows UI parity.


Native final-build verification: two paired-test documents opened immediately via the menu shortcut. Advancing the second to its confidence question left the first on its original column-selection step. Closing the second via its own × button removed only that document; closing the first returned to the unchanged worksheet. Data → Generating → Fill Series opened directly at Length. An R session started alongside it and the tabs switched between both, retaining the form. The final tab layout was visually checked, and the packaged application's ad-hoc signature passed strict verification. The original engine-source hash check, paired regression/geometry tests and all 17 grid tests passed again.


## CSV/R data files and native frame controls (23 September 2026)

Added Open CSV and Save CSV to the grid and File menu, with Command-S routing for CSV documents. The parser and grid preserve quoted commas/quotes/newlines, Unicode, whitespace, leading-zero identifiers, literal formula text, empty fields and trailing blank records. Five new CSV model tests plus the previous 17 grid tests pass. The native Swift decoder/grid/export round trip passes UTF-8, UTF-8 BOM, UTF-16 little/big endian BOM and Windows-1252 fixtures, independently read with Python's CSV reader.

Added RDS and RData/rda import and table export through the installed base-R runtime, separate from interactive R sessions. The native Swift file host, actual grid model and native writer are exercised end to end. Base R's `identical` confirms unchanged data frames and matrices, including integer/double/logical/character columns, ordered factors with unused levels, row names, Date/POSIXct timestamps and time zones, NA/NaN/Inf, empty character strings, empty tables and all-missing rows. Edited integer/factor values persist; an invalid numeric edit leaves the previous destination byte-for-byte unchanged. Corrupt R input fails explicitly, and unsupported workspace objects are identified as omitted.

Native app verification: Open CSV loaded the test table, including `0012`, a quoted comma, café and a multiline note. Editing B2 from 12 to 13 then Command-S produced example-edited.csv with the expected values. Open R data loaded both table worksheets; Command-S saved all tables to RData, while Save RDS saved only the current table. Independent base-R reads of the actual files from the native dialogs matched the source tables exactly. The duplicate top-right frame controls are removed; native macOS window controls and document-tab close buttons remain.

## Worksheet/menu cleanup and About (23 September 2026)

A new launch opens one blank worksheet, with independent numbered worksheets from Command-N. Removed the worksheet paired-test footer, the separate PEFR data form and quick paired host path, default example observations, implementation badge, duplicate file toolbar buttons and automatic Help tab. R sessions now start with an empty editor. Analyses continue through the Windows operation menus and original engine forms.

File → Open consolidates XLSX, CSV, RDS/RData/rda and HTML selection. File → Export groups worksheet formats and SVG, with context validation; Command-S retains format-sensitive saving. Help contains the full library, contextual analysis help and an Examples submenu for the bundled workbook. A native About panel is available in both the app menu and Help, showing the prototype version and engine 5.0.5. Native Edit commands route grid Undo/Redo and clipboard operations to its store while retaining the text responder for editable fields.

Validation: Swift compile, TypeScript checking and all 23 grid/model tests pass. The new blank-workbook test verifies no demo cells or injected header row and correct physical coordinates on Excel/CSV export. Native UI verification in an isolated app build confirms the clean worksheet layout, two independent blank documents, paste → Command-Z → Shift-Command-Z, direct paired-test input, column/row snapshot, confidence prompt, agreement prompt and a completed report with SVG agreement chart. The three synthetic pairs produce mean difference 5.666667 and t 6.425396. The unified Open dialog imports the CSV fixture retaining identifiers, Unicode, quoted commas and multiline text; File then shows Save CSV and the expected export choices. A new R session has a blank editor and live R console. About opens correctly from both Help and the native app menu. The packaged app passes strict ad-hoc signature verification. Existing user documents were not closed or restarted.


## Completed reports to R scripts (23 September 2026)

Generated scripts use immutable completed-report snapshots. The generic host adds parameter names, input kinds and data-acquisition modes to input history; numerical source and calculation paths are unchanged. Both generic reports and the dedicated R×C screen retain an R script plan. Their report action and the R menu open a new independent R session, seed its editor and run once. The report bridge accepts only its generated report's main frame; externally opened HTML has no report bridge or script plan. Generated scripts remain unsaved until the user saves them.

The Swift generator quotes all data, names and text as R literals; numeric missing values retain row positions, independent groups retain different lengths, and source confidence percentages become proportions. Output tables and original scalar results are retained. Unsupported methods are explicitly labelled as data/settings starters. The 38 base-R mappings state their limitations, including auxiliary outputs, exact/tie conventions, quantile methods and Monte Carlo streams. R agreement plots use the base PDF device, which works without the optional XQuartz/Cairo libraries on this Mac.

Verification: the new `Tests/test_r_scripts.py` runs actual engine sessions, passes completed JSON to the compiled Swift generator, and executes the resulting standalone scripts with installed R. All 38 mappings run successfully, including the dedicated contingency snapshot. Numerical comparisons cover paired t/mean, summary t and CI, Fisher exact P, Spearman correlation, one-way ANOVA and simple regression. Additional checks cover paired missing-value alignment, 90% confidence, one-column differences, hostile-looking quoted text and Unicode, unsupported-method labelling, empty/duplicate labels, output tables, Fisher and Monte Carlo. Six interleaved engine forms still match serial runs including their expanded input histories. Swift compile and .NET publish pass; existing generated-parser duplication warnings remain in the .NET build.

To run: compile `Sources/RScriptGenerator.swift Tests/r-script-driver.swift` to a scratch executable with `swiftc`, then run `python3 Tests/test_r_scripts.py Tests/operation-driver /path/to/r-script-driver` after publishing the full engine. The generator uses the checked-in method recipes. Native on-screen verification passed after the Mac was unlocked: entered three synthetic pairs, completed paired t with agreement, closed the source analysis form, and clicked Continue in R on its report. A separate R tab opened with the generated script, ran automatically, and retained a live session. R returned t = 6.425396, two-sided P = 0.02337552, mean difference = 5.666667 and agreement limits 2.672772 to 8.660561, matching the report. The vector agreement PDF was saved in that session directory. Original user documents and R sessions were not closed. The final app package passes strict signature verification. A temporary caffeinate assertion was enabled at the user’s request to prevent idle display/system sleep while working; password/lock settings were not changed.

## GitHub repository and upstream engine link — 23 September 2026

The Mac project is published at `iain-buchan/statsdirect-mac`, retaining the complete prototype history and the repository's MIT licence. `FullEngine/Upstream` is now a Git submodule of `iain-buchan/statsdirect`, pinned to `c56f888bd95604f9d656e90ad0236493a96f2ae7`. Explicit remote updates follow upstream `main`; normal builds keep the pinned revision. All 871 recorded source and asset hashes remain unchanged.

A fresh recursive clone fetched the engine from GitHub and completed `./build.sh`, including the original operation tests, paired/agreement checks, every menu entry point, 121 completed analysis/data/graphics cases, 14 R comparisons and six interleaved forms. The resulting Apple Silicon app passed `codesign --verify --strict`. All 23 grid model tests also passed. No calculation code was changed; the project disables automatic Windows resource and unrelated grammar discovery when compiling the full upstream checkout.

## Analysis defaults and selected R data — 24 September 2026

Analysis → Options presents all six original Windows analysis defaults on one form, with group-identifier selection explicitly disabled until supported. The initial confidence level remains **95%**. A saved default is used without another prompt only when the original confidence parameter permits defaulting. Native UserDefaults persists the settings; each new analysis captures its own settings so open analyses cannot change underneath the user. Saving options creates no results report.

`test_analysis_defaults.py` passes: all six fields match the Windows XML; invalid/cancelled changes are atomic; an alternative saved 90% level is applied and recorded automatically while an already-open 95% analysis is unchanged; turning defaulting off restores the prompt; non-defaultable confidence still prompts; and restored native settings work in a fresh engine process. The original 121 analysis/data/graphics cases, 14 R comparisons and six interleaved-form checks also pass. There are now 26 passing grid tests. All 38 mapped R scripts pass, including selected-block and missing-cell alignment checks.

Native UI verification used a separate app identifier. Saved standard defaults (95%, statistics 6 decimals, P values 4 decimals) were present in its preferences after quitting. After restarting, a worksheet with four pairs alongside a 100-observation unrelated column selected only rows 2–5 for the pair. Continue went directly to Agreement analysis without a confidence form. The report showed n = 4, a 95% CI of 0.290019 to 8.709981 and two-sided P = 0.0424. Continue in R produced only the two four-value columns and ran successfully, matching the confidence interval and P value. Missing rows remain aligned; the input history references the data instead of duplicating it.


## Options layout and reusable tab numbers — 24 September 2026

The native app now chooses analysis titles from currently open forms instead of a lifetime counter. Verified in the packaged viewer: open Analysis options and Analysis options · 2; close · 2; reopen and obtain · 2 again; close both and reopen to obtain the unnumbered Analysis options. Existing open tab names stay unchanged.

Analysis Options uses one scrollable body for all six defaults, with Save defaults and Cancel in a fixed action bar. Saving does not display an input-step history. In the packaged app, all six fields appeared together at 95%, one Save action completed successfully, and Edit defaults restored all six saved values. The generated web bundle was also checked at an 850 × 412 content viewport: scrolling reached the final P-value option while both action buttons stayed visible. No numerical engine changes. The native build, 26 grid checks, defaults integration tests and app signature verification passed.


## Report footer and inline R plots — 24 September 2026

Continue in R is a small link beside method help below the analysis results, in both general operation reports and the dedicated contingency-table report. Mapping scope remains in the tooltip and generated script comments. Native verification used the bundled test.xlsx PEFR example: the footer link opened and ran the paired/95% agreement script and its agreement.pdf appeared as an image in the R output.

The R session bootstrap now supplies a headless PDF device for ordinary plotting and flushes graphics devices opened by each submitted script, even after errors. The native output embeds every page of new/updated PDFs and supported bitmap files in the session directory. Images fit the output pane, with links to the original files, and unchanged plots are not duplicated on text-only runs. The initial editor/output split leaves room for charts. A final native check ran a plain plot call without an explicit device and visually confirmed the complete chart, title and axes in the output pane.

`Tests/r-pane-driver.swift` runs the actual persistent RPane host: two default plots in one run, multiple explicitly closed/reopened devices, an error after plotting, persistent variables, the generated paired agreement recipe, replacement of agreement.pdf on a second run, no duplicate plots on text-only runs, and narrow-column attachment sizing. All checks passed. Compile Sources/RPane.swift, Sources/RScriptGenerator.swift and this driver with Cocoa and PDFKit; pass the absolute Content directory to the executable. The complete Swift app compiles and the packaged app passes strict signature verification.

## Learning, tutor course packs and original Windows symbol — 25 September 2026

Version 0.3.0 adds a closable Learning document, full scrolling Learning Options, five learner pathways, seven worked lessons and 30 original draft questions. Every pathway includes epidemiology and causal inference. Exam sources and access limitations are recorded in `Docs/Learn/EXAM-SOURCES.md`. Tutor packs accept searchable PDF, UTF-8 text/Markdown and schema-checked JSON; relevant excerpts are selected locally for the OpenAI request. The original Windows icon supplies the app, About and learning artwork. No upstream engine files or submodule revision changed.

Six JavaScript tests pass, covering question/help/operation mappings, withheld independent-practice keys, first-answer scoring and assistance, record export and reopen, malformed nested records, frozen question versions, saved learning goals, and all seven bundled R examples with plots. The Swift learning-client checks pass for the fixed API endpoint, credentials excluded from the request body, `store:false`, role filtering, response extraction, incomplete responses, six HTTP error cases, and course-pack validation/retrieval/persistence. `test_learning_examples.py` runs the exact paired, descriptive and regression fixtures through the real engine; the paired fixture agrees with R (mean difference 5.25, t 5.3712631000277415, df 7, two-sided P 0.0010400979673, 95% CI 2.93876015–7.56123985).

The complete engine build and regression suite passed, including 1,552 upstream tests and the existing Mac host/default/R comparisons. The final native app compiles and passes strict ad-hoc signature verification. Native UI checks verified Learning/Options menus, secure API-key entry (cancelled without a key), JSON course-pack import, the paired analysis form with exactly eight selected fictional rows, and its bundled R script producing text output and an embedded plot. Browser checks verified saved goal restoration, supported-practice hints and feedback, first-answer locking, independent-practice tutor restrictions, and reopening saved attempts.

Live OpenAI conversation and teaching quality remain untested because no API key was provided. Email attachment preparation is implemented with macOS sharing; no email was sent and external delivery/review/accreditation is not claimed. Pack retrieval is a bounded keyword search, not model fine-tuning or an exhaustive course-content guarantee.

## Managed tutor without learner API keys — 25 September 2026

Version 0.3.1 removes provider-key and model entry from the Mac. The publisher supplies a public HTTPS service address, and the native host automatically obtains a limited service session on the first question. Its token stays in service-scoped Keychain storage; an expired token is renewed once transparently. The server owns the OpenAI credential, model and teaching policy. Until a service is deployed, the learning window explicitly shows that activation is pending. Existing course packs, learning records, practice and engine/R examples remain available.

The new ASP.NET Core 10 service builds and publishes without warnings or third-party packages. Six HTTP integration tests pass against a loopback synthetic provider: automatic sessions and server-owned credentials/instructions; rejected schema/authentication/model overrides; persistent daily quotas across restart and spoofed forwarding; registration caps, revocation and safe provider errors; missing administrator credential; and production HTTPS enforcement. The service reserves allowances durably before paid requests and retains only token/address hashes, expiry and counters. Deployment is limited to one instance with persistent private storage; anonymous sessions do not verify learner identity or provide university SSO.

Swift checks pass for HTTPS-only configuration, session parsing, bounded context, credential separation and safe errors. `Tests/managed-tutor-driver.swift` exercises the **same asynchronous function used by the Mac host** against the real local service: automatic session creation, saving its token, receiving an answer and replacing an expired token without learner input. All six learning/quiz/R tests still pass. The complete native app compiles; the packaged 0.3.1 build passes strict ad-hoc signature verification. On-screen verification was blocked by the Mac being locked. No live OpenAI calls, public deployment, provider charges or email submissions occurred. Hosting and one administrator-managed provider credential remain necessary for live shared conversation.

## Selected tables, instant results, active reports and update checks — 26 September 2026

Version 0.3.2 copies compatible highlighted worksheet rectangles into screen-entry grids, including chi-square 2×2 and R×C. Position, zero and missing-cell handling are covered; oversized/mismatched selections are not cropped, unsafe formula caches and Excel errors are rejected, and edited/rejected answers override the original snapshot. All 30 grid tests pass, TypeScript checks pass, and the full native app compiles. `test_selected_table.py` sends the real grid helper's C5:D6 payload through the original Chi2by2 engine and compares the statistic/P value with base R. It also verifies the instant-method flag against every Windows operation definition. The calculation engine and its pinned commit are unchanged.

The 45 self-suggesting Windows operations use instant-result previews; the dedicated R×C screen follows the same workflow. Completed results appear above retained data/parameters, with Recalculate and Add to report. Edited inputs are replayed through the engine's normal validation; newly applicable questions still prompt. Ordinary results append automatically to the active report. File → New Report is the explicit way to start a separate report, and selecting a generated report changes the destination. Each saved result owns its immutable R script and help links; repeat Add messages cannot duplicate the same snapshot. Full report PDF/Print include accumulated results.

Native verification in an isolated app: paste [12,3;8,17] into a blank sheet, highlight exactly A1:B2, choose Analysis → Chi-square Tests → 2 by 2, and see all four counts prefilled. The completed form displays chi-square 8.64 without creating a report tab. Add to report creates Report 1. Editing the first count to −1 and recalculating invokes the original validation and retains the rejected value; correcting it to 13 resumes the remaining parameters automatically and yields 9.471244. Adding this result appends to Report 1 while preserving the earlier 8.64 result. The earlier result's Continue in R link opens its original [12,3;8,17] snapshot, not the edited counts. A paired test also appends automatically to Report 1. Creating Report 2 explicitly and keeping a selected-cell R×C calculation adds it to Report 2. The synthetic test app was then closed.

Help offers Check for Updates and an initially enabled automatic-check toggle. Automatic checks occur at most once daily, including during a long-running app session, and notify once per newer stable version. View Update opens the repository release/download page; installation remains manual. `update-service-test.swift` passes numeric version ordering, same/older releases, absent releases, draft/prerelease exclusion, HTTP failures, malformed responses and trusted GitHub release URLs. Both the real endpoint and the native menu reported no published release correctly. No release has been published as part of this change. Both packaged application paths pass deep, strict ad-hoc signature verification.

## 2026-09-26 — 0.3.3: Use my ChatGPT

- Built the native Mac shell successfully; the Windows calculation engine is unchanged.
- Bundled OpenAI Codex App Server 0.157.1 from its official Apple-silicon release. Archive SHA-256 verified (`9a6033c9fe30260e71d784d003ad1e2de2a55c93e24a24856e8433029a3f811a`). The build script pins this artifact, includes upstream licence/notice and signs nested executables.
- Real runtime probes passed initialization, signed-out account state, browser login URL creation, login cancellation, ephemeral thread creation with no selected environment, turn validation, interruption and unsubscribe. No existing Codex credentials were used and no live model answer was requested with a signed-in account.
- Swift protocol fixture passed completed OAuth notification/account refresh, split JSON frames, unrelated-thread rejection, bounded/role-filtered context, successful answer delivery, safe usage-limit errors, cancellation before the turn-start response, subsequent reply, logout, child-process disconnection and restart. Synthetic inherited API keys/server overrides were excluded from the child environment.
- All six existing Learning tests passed, including independent practice, 30-question bank validation, learner-option persistence and executable R examples. Native managed-service/core course-pack tests also passed.
- Native UI verified with a separate bundle ID and portfolio: **Use my ChatGPT** in Learning, no API-key field, browser opened to OpenAI's sign-in page, pending/reopen/cancel controls, and a complete draft preserved across a connection check. Status changes now update their own elements rather than rebuilding the learner's form. Temporary sign-in cancelled and its browser page closed; test app quit.
- `StatsDirect 0.3.3.app` and canonical `StatsDirect Viewer.app` passed deep/strict signature verification. These are ad-hoc signed prototypes, not notarised distribution builds.
- Remaining: learner completes browser login to verify a live teaching response and account-specific access/limits. The existing 0.3.2 session was not closed by this work. After it was no longer running, the finished 0.3.3 build was opened to Learning.

## 2026-09-26 — 0.3.4: Tutor application context and engine tools

- Built the native Mac shell and both web bundles. The bundled Windows engine is byte-for-byte identical to 0.3.3 (`dcc2af8f0ec5`, version 5.0.8); no statistical routines were changed.
- 28 Learning, worksheet extraction, operation-data and workbook tests pass. Coverage includes exact rectangles/column order, nine PEFR pairs without blank sheet padding, internal missing positions, hidden/oversized data rejection, formula/error flags, portfolio provenance, independent practice and executable lesson R examples.
- The actual engine ran all ten direct tutor methods through `TutorTools.run`: paired/unpaired t, univariate/quick summaries, chi-square 2×2, Fisher, Wilcoxon signed ranks, Spearman, agreement and normality. The host preserves row positions and requires an explicit chi-square study design; it refuses an oversized screen table rather than cropping it.
- The nine-pair example gives mean before-minus-after 56.111111, 95% CI 29.842662–82.379560 and two-sided P 0.001155573. Its generated R script has nine rows and agrees with engine mean/CI/P to the test tolerances (1e-10 / 1e-9 / 1e-12). The engine report contains an SVG agreement chart. With the third before value missing, the native helper retains row alignment: n=8, mean=49.625 and eight plotted points.
- Swift protocol tests pass tool round-trip JSON, registered-tool restrictions, wrong-thread/turn rejection, duplicate call suppression and cancellation of a running tool, alongside the existing login, answer, usage-limit, retry and disconnect checks. The pinned real App Server 0.157.1 accepts the dynamic tool definition with no selected computer environment; the probe remained signed out.
- `Scripts/test-learning-workspace.sh` compiled a separate native test app with its own bundle ID and portfolio. It opened the real bundled test.xlsx through the Excel host, located the PEFR columns, read their nine pairs from WKWebView, ran the engine, appended one report with SVG/R link, and verified repeat-result reuse. It also verified stale worksheet rejection, per-question document scope, cancellation, Lessons only, bundled help, actual rendered report reading, R script/output reading and draft preservation through context/account updates.
- Native UI checked the context choices and Lessons-only status; the typed draft remained intact. Tool-source references are escaped in the conversation and exported in the record. The isolated test app was closed.
- `StatsDirect 0.3.4.app` and canonical `StatsDirect Viewer.app` pass deep/strict code-signature verification. Packaged executable UUID matches the new native build. They remain ad-hoc signed prototypes.
- A live model/tool conversation was not sent from the user's signed-in account in this verification. Transport and host integration were exercised separately with the protocol fixture and the real native/engine harness. The user's running 0.3.3 session, including its open analysis form, worksheet and saved learning conversation, was left intact; opening 0.3.4 after closing that session is required to use the new native tools.

Additional reproducible checks:

```sh
node --test Learn/learning.test.mjs Grid/tutor-data.test.mjs Grid/operation-data.test.mjs Grid/workbook.test.mjs
swiftc Sources/ChatGPTTutor.swift Sources/TutorTools.swift Sources/RScriptGenerator.swift Tests/tutor-engine-driver.swift -o .build/tutor-engine-test
.build/tutor-engine-test "$PWD"
Scripts/test-learning-workspace.sh "$PWD/StatsDirect Viewer.app"
```

## 2026-09-26 — 0.3.5: Keep study-guide prompts with their lessons

- Confirmed the clinic-diagnosis question belongs to the epidemiology lesson. The shared conversation previously displayed all lesson prompts with the same generic label, making earlier questions look like part of the currently selected lesson.
- Guide prompts now carry their lesson title; prompts from other lessons or older wording are collapsed as earlier study guides. Exact-text matching labels legacy entries without rewriting or deleting the conversation. Reopening a lesson supplies its current prompt when needed; re-rendering does not duplicate it. Lesson titles are retained in exports and sent with model conversation context.
- The paired lesson explicitly establishes repeated observations on the same people or matched pairs and contrasts these with different unmatched patients in two periods. The teaching instructions likewise require actual pairing before selecting a paired method.
- All ten Learning/lesson-context tests pass, including legacy-record migration, lesson switching, duplicate prevention, draft/history preservation, export attribution and the seven executable R lesson examples.
- Built and verified ad-hoc signatures for 0.3.5 and the canonical app. Engine bytes and native executable UUID are unchanged from 0.3.4. No calculations or runtime protocols changed.
- Opened 0.3.5 after confirming the older window contained only an empty worksheet. In the restored real Learning record, the paired heading and revised prompt are correct, both earlier prompts are collapsed with their original lesson names, ChatGPT remains connected, and the complete prior learner/tutor conversation is retained. No question was sent to the live tutor during this verification.

## 2026-09-26 — 0.3.6: More room for the tutor conversation

- Moved Tutor context out of the chat header into a compact strip at the bottom of the Learning window, retaining the document selector, Refresh and current-source status. Long status text has a tooltip.
- The conversation now fills the available height instead of being capped at 160 pixels. The composer stays visible; lesson notes and the worked example are expandable. Other Learning pages retain their normal scrolling layout and hide the context strip.
- Built the learning bundle and visually checked the native layout in an isolated app with synthetic conversation history and a draft. Visiting Learning options and returning preserved the draft and restored the context strip. The isolated app was closed.
- Opened the finished 0.3.6 application to Learning and verified the bottom strip, expanded conversation area, fully visible composer, collapsed notes and restored real conversation. No live tutor question was sent.
- Both packaged application paths pass deep/strict ad-hoc signature verification. Native executable UUID and calculation-engine bytes are unchanged from 0.3.5; this is a web layout change.

## 2026-09-26 — 0.3.7: Download and install missing R

- Added shared R setup for new sessions, report/learning scripts and RData/RDS open/save. Missing R presents Download and Install R, progress, cancellation and retry. The R menu also exposes setup and recognises an existing installation. Repeated requests share one setup window.
- The package is pinned to official CRAN R 4.6.1 for Apple Silicon/macOS 14+, SHA-256 `67f6eea4ced4ce48f0a0d4fa3a1cac43d1859a05a88993ee3dff7c52e7edbc4b`. The actual URLSession download passed checksum verification, `pkgutil` verification of Developer ID Installer Simon Urbanek (`VZLD955F6P`) and macOS installer assessment. Downloads cannot redirect to another URL, exceed their size bound or open before verification. Cancellation/failure cleans the staging directory.
- Core tests cover runtime discovery, unsuccessful runtime probes, empty/oversized/wrong-checksum files, a matching-checksum unsigned file, changed URLs, HTTP errors and unexpected content lengths. Local HTTP fixtures exercise the real download path for 404, forbidden redirects, oversized/corrupt/unsigned payloads and cancellation; all pass.
- An isolated native UI fixture simulated missing R without removing or reinstalling the existing runtime. Verified download failure/retry, cancellation with script preservation, installer handoff state, rejection of an unfinished installation, and successful resumption of the original script with its plot after R became available. The fixture deliberately does not launch macOS Installer. It was then closed.
- Existing native RPane tests pass persistent variables, default plots, multiple devices, error-after-plot handling, agreement PDF replacement, attachment links and resizing. Real RData/RDS/CSV round trips also pass, including types, missing values, factors, edits, invalid input and atomic-save protection.
- Compiled the full native app; both 0.3.7 and the canonical bundle pass deep/strict ad-hoc signature verification. Calculation-engine bytes are unchanged from 0.3.6. Opened 0.3.7, verified R Is Installed in the menu, and opened a ready R session directly.
- The actual privileged installation on a clean Mac still needs colleague testing. StatsDirect opens the standard macOS Installer; it does not bypass its installation steps, administrator approval or managed-device restrictions. Returning to StatsDirect runs a real Rscript readiness probe before resuming the pending action.

Reproduce core/download and existing-R checks:

```sh
swiftc Sources/RInstallation.swift Tests/r-installation-test.swift -o .build/r-installation-test
.build/r-installation-test --fetch
python3 Tests/test_r_install_download.py .build/r-installation-test
swiftc Sources/RInstallation.swift Sources/RInstaller.swift Sources/RPane.swift Sources/RScriptGenerator.swift Tests/r-pane-driver.swift -o .build/r-pane-test -framework Cocoa -framework PDFKit
.build/r-pane-test "$PWD/Content"
swiftc Sources/RInstallation.swift Sources/RDataFileIO.swift Sources/CSVFileIO.swift Tests/data-file-driver.swift -o .build/data-file-driver
python3 Tests/test_data_files.py .build/data-file-driver /path/to/node
```

`Tests/r-installation-ui.swift` can be compiled with RInstallation, RInstaller and RPane into an isolated app containing `Content/R/session.R`. Its first download fails deliberately; subsequent downloads simulate progress without installing software. Creating `~/Library/Application Support/com.statsdirect.r-setup-ui/ready` after the simulated installer handoff lets Check Again use the existing local R and resume the retained script. Launching the fixture resets only this marker.

## 2026-09-26 — 0.3.8: Update checks when GitHub API DNS fails

- Reproduced the reported error on this Mac: both curl and native URLSession failed to resolve `api.github.com` (NSURLErrorCannotFindHost, -1003). `github.com` resolved and its repository `/releases/latest` address redirected successfully to the release list. No network or DNS settings were changed.
- The checker now falls back from a failed GitHub API request to GitHub's documented latest-release web address. It validates the final HTTPS host, repository path and numeric tag rather than scraping HTML. A successful redirect to the release list reports no published release. An unrelated/login page, invalid tag, HTTP failure or failure of both hosts remains an error.
- Manual connection errors have specific DNS/offline/timeout/TLS explanations and Try Again, Open Downloads and Cancel. The current-version message also handles local builds newer than the latest published version correctly.
- Unit/URLSession fixtures pass API-only success, DNS/rate-limit/server-error fallback, newer/current versions, missing releases, invalid URLs, failure of both hosts and cancellation without fallback. The live check succeeds on the affected Mac and reports no published release.
- Built and ad-hoc signature-verified 0.3.8 and the canonical bundle; calculation-engine bytes are unchanged. Opened 0.3.8 and selected Help → Check for Updates: the native dialog correctly says No published update is available and identifies version 0.3.8. No GitHub release or installer was published by this fix.

```sh
swiftc Sources/UpdateService.swift Tests/update-service-test.swift -o .build/update-service-test
.build/update-service-test --live
```

## 2026-09-26 — 0.3.11: Report export and Excel paste

- Save Report (⌘S) offers HTML, PDF and DOCX in a native format chooser; changing formats changes the filename extension. Verified the actual dialog through a successful DOCX save. File → Export provides direct entries too. The complete active report is exported.
- `Scripts/test-report-export.sh` ran the unchanged 5.0.8 engine for paired t/agreement and chi-square 2×2, appended a 65-row synthetic table with merged headings, and exported/reopened the combined report. All native assertions pass: portable HTML, five A4 PDF pages including the last result, SVG charts, and a reopened HTML-to-DOCX round trip. App-only controls/scripts and local help paths are absent from saved HTML.
- DOCX package checks verified three editable tables, all 65 observations, horizontal/vertical merges, two repeated heading rows, superscripts/subscripts, external help relationships, and SVG plus PNG chart media. Both the PDF and the four-page DOCX rendering were visually checked. Word uses semantic document formatting; PDF follows WebKit pagination (table headings do not reliably repeat there).
- Actual Microsoft Excel for Mac ⌘C/⌘V testing exposed chart-axis text leaking into cells, text-label and scientific-number formatting issues, and pictures covering later results. Corrected the report clipboard HTML and retested in a new synthetic worksheet. All 65 labels, decimals, negatives and scientific P values are present; numeric cells remain numeric, both header merges survive, and the picture ends before the next analysis. No Excel error cells occur. Excel retains destination column widths; wrapped labels remain visible and AutoFit gives more room.
- Native clipboard tests pass whole-report selection, a single selected table row with restored table structure, and empty selection; the plain-text fallback contains tab-separated cells and excludes chart-axis clutter. Node tests cover percentages, Unicode minus, identifiers, Excel's 15-digit precision bound, formula-like labels and nonnumeric values. No calculation code changed.
- The versioned and canonical 0.3.11 app bundles pass deep/strict ad-hoc signature verification. The calculation-engine binary is byte-for-byte identical to 0.3.10. The downloadable ZIP is 153,476,978 bytes; SHA-256 `77d0e0c8898463e77b0d1ad52f08996fb75e0cafd9361cab7fecc55891b0c5d1`.

```sh
node --test Report/clipboard.test.mjs
Scripts/test-report-export.sh "$PWD/StatsDirect Viewer.app"
```

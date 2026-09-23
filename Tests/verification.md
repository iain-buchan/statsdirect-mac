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

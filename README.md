# StatsDirect for Mac

Native macOS prototype in [iain-buchan/statsdirect-mac](https://github.com/iain-buchan/statsdirect-mac), using the calculation engine from [iain-buchan/statsdirect](https://github.com/iain-buchan/statsdirect). The engine repository's primary branch is **main**. `FullEngine/Upstream` is a Git submodule pinned to a tested commit; builds compile that source directly. Mac hosting and rendering adaptations remain in this repository. Engine updates are explicit and do not happen automatically during a build.

Open **StatsDirect Viewer.app**. It starts with one blank worksheet. **File → New Worksheet** (⌘N) creates another independent document; **File → Open…** (⌘O) accepts Excel, CSV, R data and HTML reports. Choose a function from **Analysis** to open its first input step immediately. Results open in separate report tabs, preserving earlier results.

**StatsDirect → About StatsDirect** opens the native About panel, showing the Mac prototype version and calculation-engine version. The same command is available under **Help**. Worked data are available under **Help → Examples → StatsDirect Example Workbook**; no example data or test-specific controls are loaded into a new worksheet.

The window uses the native macOS red, amber and green controls. Drag the title bar to move it or its edges to resize it. Document tabs have their own **×** buttons; the duplicate top-right frame buttons have been removed.

Reports, help, analysis forms, worksheets and R sessions stay open as separate documents in one native Mac window. **File, Edit, Data, Analysis, Graphics, R, Help and Window** dropdowns contain commands. A compact row of document tabs beneath them lets you switch directly and close any document with its **×** button. **Window** also lists the documents; **⌘W** closes the current one. Closing an active analysis cancels only that form. Unsaved worksheet and R script changes still prompt before being discarded. The same commands are available in the macOS menu bar. The Help library contains 400 topics from the supplied statisticalhelp repository. Printing and PDF export use WebKit.

## Data grid

**File → New Worksheet** (⌘N) opens a blank 100-row, eight-column worksheet. Double-click to edit, or use the selected-cell value field. Return saves the value and selects the cell below. Arrow keys save an edit and move one cell in the indicated direction. These controls also work in analysis input grids and stop at table edges. Small analysis grids fit their dimensions, so a 2 × 2 count table displays only four entry cells plus headings.

The worksheet toolbar contains Undo/Redo, Copy/Paste, Clear cells and extra rows/columns. The Edit menu and standard keyboard shortcuts also operate on worksheet cells while retaining normal text editing inside fields. File commands stay in **File**: **⌘S** saves the selected document in its current format, and **Export** offers Excel, current-sheet CSV/RDS, all-sheet RData and report SVG charts. Each save opens a destination dialog.

Analyses use a snapshot of the most recently selected worksheet. Choose **Analysis → Parametric → Paired t** (⌘T), select the required columns in its form and continue through the engine's questions. A selected cell rectangle supplies its exact rows and columns; column selections default to the last occupied row in those columns, rather than the height of unrelated worksheet data. Missing cells inside the selected range retain their positions. Incomplete pairs are omitted and nonnumeric values produce a validation error.

**Analysis → Options** shows all six Windows Analysis Options together: automatic confidence, the default confidence level (95% initially), group selection mode, decimal places for statistics and P values, and scientific notation for small P values. Save them once to retain them across app restarts. Group-identifier selection is shown disabled because it is not implemented on Mac; separate columns remain available. New analyses automatically use the saved confidence level whenever the Windows operation permits it. Turn off automatic confidence to choose it each time. Methods that explicitly prohibit defaulting still ask. Already-open analyses keep their original settings.

This is an editable grid prototype. Save your data before closing; Excel and RData retain all worksheets, while CSV and RDS save the current worksheet. Live formula editing and large-sheet performance work remain. Implementation, build instructions and limits are in [Grid/README.md](Grid/README.md).

## Windows Data, Analysis and Graphics menus

The menus follow the Windows `menu.xml`: 224 commands covering 208 distinct operations, each linked to its offline method help. Selecting a command opens its first input form automatically. Several forms, including multiple copies of the same method, can remain open with independent inputs, progress and reports. **Continue** advances that form's original engine operation; **Cancel analysis** or the tab's **×** stops only that operation. Calculations are serialized between input boundaries to protect the engine's shared caches; waiting forms do not block other forms. The original definitions drive questions, defaults, conditional steps and validation.

For data, choose columns from a snapshot of the most recently selected worksheet, in the required order, and review the first/last row. Or enter/paste data into the embedded Glide table. Use **Refresh worksheet** after changing data or switching worksheets. Numeric categorical predictors offer the engine's reference-category choices. Grouped observations currently use separate columns; identifier-based selection/pivoting is not implemented. The ANOVA repeated/nested forms request each repeat or group in turn, and covariance requests each predictor/outcome series.

Reports and SVG charts open in their own tabs. Analyses that output data also open new editable grid tabs, which can be saved to Excel. The dedicated chi-square screen form remains available. In the general paired-test form, **Agreement analysis** is an explicit follow-up question.

LOESS and method-comparison regression are visible with help, but their engine R/Windows-graphics bridge is explicitly marked unavailable. Independent R sessions are available through **R → New R Session**. All other 206 operations reach their first input. There are 121 end-to-end analysis/data/graphics cases, 14 independent R comparisons, and additional checks of six interleaved forms against serial results. This is prototype coverage, not certification of every option or chart.

Some Windows UI commands have Mac host equivalents: basic Search and Replace uses the advanced engine form; the screen unit converter uses an entered-data grid and original conversion choices. Sort-in-place and Filter currently produce new result worksheets, leaving their source worksheet intact. Categorisation accepts explicit boundaries, and Graphics Options exposes colour and boxed axes; the full Windows editing controls remain to be ported.

## Chi-square screen-data form

Choose **Analysis → Chi-square Tests → R by C → Screen Data** (⌘4). The form embeds Glide in place of the Windows form's SpreadsheetGear control and runs the original `ExactChiRbyCScreen` operation. Resize the table, edit counts, or paste a rectangle without headings/totals. Enter zero explicitly; blank, negative and fractional counts are rejected. Undo/Redo retains table dimensions, counts and category labels. **Save Table…** exports the labelled count table as CSV, not analysis settings.

**Load help example** fills the 4 × 3 grief/support table (66 observations) and enables expected counts and cell contributions. **Run analysis** opens a new report tab while retaining the form. The original engine provides Pearson and G tests, exact testing, percentages, expected counts, cell chi-square, trend scores and optional Monte Carlo simulation. Custom scores are supplied through the engine's existing amendment prompt. A fixed simulation seed reproduces results. Method help opens separately.

The prototype accepts 2–200 categories on each axis, at most 2,500 cells and a total count up to one billion; every row and column needs a positive total. Simulation accepts up to ten million iterations and five million observations. The original engine skips exact testing above 100,000 observations. Cancellation takes effect at engine checkpoints; an exact-test step must finish first. Cancelled calculations never publish partial reports.

## Paired agreement chart

Choose **Analysis → Parametric → Paired t**, select columns and answer **Yes** to **Agreement analysis** when prompted. The report includes the original engine's limits of agreement and its `TiesChartRenderer` SVG plot: paired means on the horizontal axis, differences on the vertical axis, the mean-difference line and both limits. **File → Export → Chart as SVG…** exports the vector chart from the selected report; PDF/Print retain it in the report. The verified example is `Content/Examples/paired-agreement.svg`.

## Excel workbooks

**File → Open…** (⌘O) opens an `.xlsx` workbook in a new data tab. The buttons above the grid select its worksheets. **Help → Examples → StatsDirect Example Workbook** loads the bundled StatsDirect example with all 11 worksheets. Its original filename is `test.xlsx`, not `text.xlsx`.

**Save Excel…** (⌘S in an Excel tab) writes every worksheet to an `.xlsx` file. The default filename ends in `-edited.xlsx`; the original is untouched unless you explicitly select it in the save dialog. Numbers, text identifiers, dates and booleans retain their types. Existing workbook cell styles, formulas and other untouched package content are preserved; the grid itself uses a simple, consistent display. **File → Export → Current Worksheet as CSV…** exports only the current worksheet and does not mark an Excel workbook as saved.

Imported rows retain their Excel row numbers. **First row has column names** is detected from text headers and can be toggled. When checked, analysis skips that row. The paired test on the Parametric sheet's first two columns reproduces the PEFR example.

Formula cells show saved results and are read-only. After an edit, analysis involving formula cells is blocked until the file is recalculated and reopened. Export refreshes supported formula results and requests full recalculation when Excel opens the file; unsupported results are left uncached and reported. There is no live Excel formula engine in the grid.

This first implementation supports `.xlsx` only, up to 50 MB compressed, 256 MB expanded, 128 sheets and 500,000 populated cells. Legacy `.xls`, `.xlsb`, macros, password-protected files and full Excel visual rendering are not implemented. Excel itself is not required for basic import/export. The full test workbook round trip is verified; this is not a general Excel conformance or million-row performance claim.

## CSV files

Choose **File → Open…** (⌘O) to open a file in a new data tab. **File → Export → Current Worksheet as CSV…** writes the current worksheet; **⌘S** also saves CSV when working in a CSV document. Quoted commas, doubled quotes, embedded line breaks, Unicode, whitespace, identifiers such as `0012`, empty fields and trailing blank rows are preserved. Short CSV records are padded to the table width. Text beginning with `=` is treated as data.

The first row is detected as column names when it contains text; toggle **First row has column names** if needed. This changes analysis labels, without removing the source row. Import accepts UTF-8 (with or without BOM), BOM-marked UTF-16 and Windows-1252; output is comma-delimited UTF-8 with a BOM and CRLF records for Excel compatibility. Files are limited to 50 MB and 500,000 rectangular cells. Semicolon/tab-separated files are not covered by this CSV importer; tab-separated clipboard paste remains available. Invalid quoting fails explicitly.

## R data files

**File → Open…** reads `.rds`, `.RData` and `.rda`. Each supported data frame or numeric, logical or character matrix appears as a worksheet. **File → Export → Current Worksheet as RDS…** writes one R object; **All Worksheets as RData…** writes all worksheets as named objects. **⌘S** uses the opened R format. Format choices are grouped under File → Export.

The installed R runtime reads and writes the actual R formats without additional R packages. Supported columns retain integer/double/character/logical types, factor levels and ordering, Date/POSIXct values, time zones, row names, NA, NaN and infinities. Missing R values appear as blank cells. An unchanged empty character string remains distinct from NA. New factor labels are appended to the existing levels; invalid edits to typed columns fail before replacing an existing destination. New grid tables become base R data frames; an imported matrix retains its matrix shape.

This is table interchange, not a full R workspace editor. Other objects and unsupported columns (such as nested lists or custom classes) are reported as not imported, and are not written by Save RData. Extra application-specific attributes and data-frame subclasses are not retained. Import is limited to 50 MB, 128 tables and 500,000 cells. Conversion runs separately from any open R script sessions, which keep their own variables. R must be installed on the Mac.

## R sessions

Choose **R → New R Session** or **File → New R Session** (⌘R) to start a session. Use **Window** to switch between sessions and other documents. Each tab starts a separate persistent session using the R installation on this Mac. Edit the script and click **Run script**, or press **⌘Return**. The script editor starts empty. The console displays output, warnings and errors; variables remain available between runs.

**Stop / Reset** terminates that session and clears its variables. The next run starts a new session. **Save script…** (⌘S when the R tab is selected) saves an `.R` file. Closing a tab or quitting warns about unsaved edits or running scripts. Session objects are not restored after closing.

R-created files are retained in `~/Library/Application Support/StatsDirect Viewer/R Sessions/<session-id>`, shown in the console. This first version provides a script editor and text output; it does not embed an R graphics device or support interactive console input such as `readline()`. The R tab is separate from the calculation engine's R-operation integration. R is installed separately and is not bundled with this app.

## Continue a completed analysis in R

Completed analysis reports include **Continue in R**, also available as **R → Continue Report in R**. Clicking it opens an independent R tab with a generated script and runs it once. The editor remains editable; use Run Script to rerun it or Save Script to keep a standalone `.R` file. Generated scripts are treated as unsaved until saved.

The script contains the completed run's recorded inputs, normalized confidence levels, parameter choices, original scalar results and any output tables. It does not reread the live worksheet, so editing or closing the source form cannot change an earlier report's R analysis. Named `data_frames`, `parameters`, `original_results`, `input_history` and `result_tables` objects remain available for exploration. The R data contain only the selected worksheet block, retaining internal missing cells; `input_history` refers to that block rather than repeating the entire data. R must be installed; no R packages are installed automatically.

There are currently 38 method mappings, all using base R: paired/single/unpaired t tests (including summary-statistic forms), sign and single-proportion binomial tests, Poisson rate intervals, Pearson/G/Fisher contingency tests, McNemar, Spearman/Kendall, Wilcoxon/Mann–Whitney/Smirnov/Kruskal, one-way ANOVA, simple linear regression, variance ratio, core univariate summaries, Shapiro–Wilk and eight distribution calculators. Paired t retains the selected confidence level and optional agreement analysis, including a vector PDF plot in the R session directory. The existing StatsDirect report retains its SVG chart.

**R script coverage** describes each mapping's scope. Main statistical equivalents do not imply identical output for every supplementary estimate: exact-test conventions, ties, continuity corrections, centiles and simulation streams can differ. Trend/risk extensions and some supplementary outputs are not reproduced. Unmapped functions instead display **Open data and settings in R**, with an explicit starter-script notice; these include their captured data and results but do not claim an equivalent calculation. The scripts and scope notes are in `Content/R/recipes` and `Content/R/analysis-recipes.json`.

The mappings follow the [R stats reference](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/00Index.html), including its [t-test](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/t.test.html) and [rank-test](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/wilcox.test.html) conventions. The statistical engine remains unchanged; the host's input history now records stable parameter names, kinds and acquisition modes alongside the original answers.

## Engine

The app now embeds the **full StatsDirect 5.0.5 headless calculation build**, replacing the earlier extracted paired routine. It loads 284 operation definitions. The paired menu action runs the original `TPaired` definition through `TemplateProcessor` and displays HTML from the original report renderer. Calculations and C#/VB scripts run in the same process as the Mac window, using a bundled .NET runtime.

The shell is Swift/AppKit with WKWebView. This establishes a native Mac prototype and reusable HTML content; it is not yet the proposed Avalonia shell or a completed replacement for the Windows application.

See [FullEngine/README.md](FullEngine/README.md) for provenance and exact platform adaptations, and [Tests/verification.md](Tests/verification.md) for verification.

## Scope

The Windows Data, Analysis and Graphics menus are populated. The general host supports numeric/boolean/choice questions, data frames, count tables, repeated/nested data, covariance, validation and cancellation. Engine R integration, identifier-based pivoting, suggested post-analysis commands, advanced chart controls and RTF/Office export remain. This is an ad-hoc signed local prototype, not a notarized distribution.

## Build

Clone this repository with its engine:

```sh
git clone --recurse-submodules https://github.com/iain-buchan/statsdirect-mac.git
cd statsdirect-mac
./build.sh
```

For an existing clone, run `git submodule update --init --recursive` first. Downloading a GitHub source ZIP does not include the engine submodule.

Run `./build.sh` on an Apple Silicon Mac with Xcode command line tools, Python 3 and .NET 10 SDK installed. Set `DOTNET` to the SDK executable if necessary. Build caches default to the ignored `.build` directory; set `STATSDIRECT_BUILD_WORK` to use another location. The generated `.app`, runtime, caches and compiler outputs are excluded from Git. The prebuilt offline grid and help are included; Node.js/pnpm is needed only when rebuilding the grid.

See [Updating the calculation engine](FullEngine/README.md#updating-the-calculation-engine) for the controlled update procedure. The Git submodule link and `FullEngine/upstream-manifest.json` identify the exact engine revision used by this Mac version.

To refresh the menu and its help mapping, run `python3 import_analysis.py /path/to/statsdirect /path/to/statisticalhelp`. To refresh help, run `python3 import_help.py /path/to/statisticalhelp`. Engine refresh instructions are in FullEngine/README.md. Source revisions and hashes are recorded in the provenance manifests. No changes have been pushed to either upstream repository.

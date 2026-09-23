# StatsDirect Mac viewer prototype

Open **StatsDirect Viewer.app**. The **Data grid · PEFR** tab now opens by default. Choose **Analysis → Parametric methods → Paired t test — PEFR example** (⌘T), or click **Run paired t test**. Each run creates a new report tab. Edit the paired observations in the grid and run again to produce a separate report. Earlier reports retain their original results and input snapshots.

The window frame has explicit **Close**, **Minimise**, **Resize / Restore** and **Move** controls. Drag Move to reposition the window; Resize / Restore toggles the window size, and the native edges support custom resizing.

Reports and help occupy separate tabs in one native Mac window. The Help library contains 400 topics from the supplied statisticalhelp repository, including the worked paired t example. Help links open within help tabs. The Window menu lists open documents; ⌘W closes the selected tab. Printing and PDF export use WebKit.

## Data grid

The **Data grid** toolbar button or **File → Data Grid** (⌘3) opens the Glide worksheet. Double-click to edit cells, or use the selected-cell value field and press Return. Use **Paste from clipboard** for tab-delimited data and **Copy selection** to copy a block. Undo/Redo, extra rows/columns and **Save CSV…** are available in the grid.

For a paired test, select two column headers or a two-column range; otherwise the two column selectors are used. Blank pairs are omitted and nonnumeric cells produce a validation error. The original engine generates a report in a separate tab, with the selected column names. The top Analysis menu uses the most recently selected grid or example-data form.

This is an editable grid prototype. Save Excel before closing to retain all worksheet edits. Live formula editing and large-sheet performance work remain. Implementation, build instructions and limits are in [Grid/README.md](Grid/README.md).

## Excel workbooks

**Open Excel…** (File menu, ⌘O) opens an `.xlsx` workbook in a new data tab. The buttons above the grid select its worksheets. **Open test.xlsx** loads the bundled StatsDirect example with all 11 worksheets. Its original filename is `test.xlsx`, not `text.xlsx`.

**Save Excel…** (⌘S in a data tab) writes every worksheet to an `.xlsx` file. The default filename ends in `-edited.xlsx`; the original is untouched unless you explicitly select it in the save dialog. Numbers, text identifiers, dates and booleans retain their types. Existing workbook cell styles, formulas and other untouched package content are preserved; the grid itself uses a simple, consistent display. **Export CSV…** exports only the current worksheet and does not mark the whole workbook as saved.

Imported rows retain their Excel row numbers. **First row has column names** is detected from text headers and can be toggled. When checked, analysis skips that row. The paired test on the Parametric sheet's first two columns reproduces the PEFR example.

Formula cells show saved results and are read-only. After an edit, analysis involving formula cells is blocked until the file is recalculated and reopened. Export refreshes supported formula results and requests full recalculation when Excel opens the file; unsupported results are left uncached and reported. There is no live Excel formula engine in the grid.

This first implementation supports `.xlsx` only, up to 50 MB compressed, 256 MB expanded, 128 sheets and 500,000 populated cells. Legacy `.xls`, `.xlsb`, macros, password-protected files and full Excel visual rendering are not implemented. Excel itself is not required for basic import/export. The full test workbook round trip is verified; this is not a general Excel conformance or million-row performance claim.

## R tabs

Click the permanent **+ R session** tab to start a new R session. It stays at the end of the tab strip so you can start more sessions at any time. **File → New R Tab** and **R → New R Tab** (⌘R) are also available. Each tab starts a separate persistent session using the R installation on this Mac. Edit the script and click **Run script**, or press **⌘Return**. The initial script runs the paired t-test example in base R. The console displays output, warnings and errors; variables remain available between runs.

**Stop / Reset** terminates that session and clears its variables. The next run starts a new session. **Save script…** (⌘S when the R tab is selected) saves an `.R` file. Closing a tab or quitting warns about unsaved edits or running scripts. Session objects are not restored after closing.

R-created files are retained in `~/Library/Application Support/StatsDirect Viewer/R Sessions/<session-id>`, shown in the console. This first version provides a script editor and text output; it does not embed an R graphics device or support interactive console input such as `readline()`. The R tab is separate from the calculation engine's R-operation integration. R is installed separately and is not bundled with this app.

## Engine

The app now embeds the **full StatsDirect 5.0.5 headless calculation build**, replacing the earlier extracted paired routine. It loads 284 operation definitions. The paired menu action runs the original `TPaired` definition through `TemplateProcessor` and displays HTML from the original report renderer. Calculations and C#/VB scripts run in the same process as the Mac window, using a bundled .NET runtime.

The shell is Swift/AppKit with WKWebView. This establishes a native Mac prototype and reusable HTML content; it is not yet the proposed Avalonia shell or a completed replacement for the Windows application.

See [FullEngine/README.md](FullEngine/README.md) for provenance and exact platform adaptations, and [Tests/verification.md](Tests/verification.md) for verification.

## Scope

The visible analysis menu currently runs the paired t test only. The complete numerical source is built, but only the two populated upstream operation tests and the paired viewer path have been exercised. Chart rendering, Windows file dialogs, the engine’s R-operation integration and RTF/Office export still need Mac host work. This is an ad-hoc signed local prototype, not a notarized distribution.

## Build

Run `./build.sh` on an Apple Silicon Mac with Xcode command line tools, Python 3 and .NET 10 SDK installed. Set `DOTNET` to the SDK executable if necessary. The script also recognizes the SDK downloaded in this workspace's `work/dotnet` directory. Build caches are kept outside the deliverable by default.

To refresh help, run `python3 import_help.py /path/to/statisticalhelp`. Engine refresh instructions are in FullEngine/README.md. Source revisions and hashes are recorded in the provenance manifests. No changes have been pushed to either upstream repository.

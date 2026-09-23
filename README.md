# StatsDirect Mac viewer prototype

Open **StatsDirect Viewer.app**. Choose **Analysis → Parametric methods → Paired t test — PEFR example** (⌘T), or click **Run paired t test**. Each run creates a new report tab. Edit the nine paired observations in the data tab and run again to produce a separate report. Earlier reports retain their original results and input snapshots.

The window frame has explicit **Close**, **Minimise**, **Resize / Restore** and **Move** controls. Drag Move to reposition the window; Resize / Restore toggles the window size, and the native edges support custom resizing.

Reports and help occupy separate tabs in one native Mac window. The Help library contains 400 topics from the supplied statisticalhelp repository, including the worked paired t example. Help links open within help tabs. The Window menu lists open documents; ⌘W closes the selected tab. Printing and PDF export use WebKit.

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

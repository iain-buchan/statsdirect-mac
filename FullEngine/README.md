# Full headless calculation engine

This project compiles the StatsDirect 5.0.5 calculation source, rather than extracting a single procedure. `Upstream` contains the source from the commit recorded in `upstream-manifest.json`: all Builtins (apart from the dialog-dependent ImportExport implementation), Numerics, Data, Templates, expression parsers, template processing, chart definitions/renderers, utilities, configuration, CSV and R support. All 284 operation definitions and their report templates are included. Numerical algorithms are unchanged.

The original `OperationTestHost` and `OperationsTester` are compiled unchanged. This source revision contains **two populated operation tests**, covering paired t and exact sign, plus one empty test. Both populated tests pass, checking 26 expected outputs in total. Loading 284 definitions does not mean all 284 procedures have been exercised.

## In-process Mac hosting

`bridge.cpp` hosts the bundled .NET 10 runtime using hostfxr. It loads the entire managed assembly into the Swift application's process. There is no engine subprocess. The regular managed runtime also supports the engine's Roslyn C#/VB script compilation; NativeAOT was inappropriate for that path.

`Exports.Paired` supplies the editable data to a host based on `OperationTestHost`, then executes `TPaired` through `ITemplateProcessor`. `ViewerHost` captures report output with the existing `HtmlRenderer`. The Swift shell retrieves UTF-8 HTML and adds the document header, input snapshot and help link. The viewer passes the optional agreement flag to the original operation; when selected, the original Ties chart renderer produces embedded SVG. `AnalysisIO` also supplies the original ExactChiRbyCScreen operation, including custom scores and simulation, and provides cancellation without publishing partial results.

The host-facing C functions are intentionally small; they are not a replacement calculation layer. Calls are serialized by the viewer. The report buffer is the last completed calculation, and must be retrieved before another calculation starts.

## Explicit platform boundaries

- `Nonparametric.cs`: full original file with two unused DevExpress namespace imports removed.
- `Settings.cs`: original defaults, a local window-state enum instead of WinForms, and no engine-side persistence. Preferences belong to the host.
- `PlatformHost.cs`: registry/preferences initialization and an opaque window token. Windows file-picker builtins fail explicitly until supplied by the Mac host.
- `SvgCanvas.cs`: original SVG drawing commands with CoreText text measurement and Arial for Mac SVG labels. `MacText.cs` and the small `TextMetrics.cpp` library supply native font metrics. `CanvasTextFormat.cs` supplies alignment values without allocating a GDI StringFormat. Host copies of `TalbotLinHanrahanAxisScaler` and `QuantitativeFormatter` replace Bitmap/Graphics/font-height calls with CoreText; the axis-selection algorithm is retained. The original Ties agreement renderer is unchanged and its SVG geometry is verified. Other chart types have not been validated; some still depend on Windows APIs.
- `RController.cs`: the Windows install dialog is replaced by an explicit exception. Windows R discovery and EMF chart import remain unported; the engine’s R-operation bridge is not supported on Mac yet (the native shell now has an independent R script tab).
- Windows EMF canvas and RTF report renderers are excluded. The RTF image converter remains compiled for existing type dependencies, but its Windows image path is not supported on Mac.
- `ViewerHost.cs` retains the quick paired and dedicated chi-square paths. `OperationSessions.cs`, `HostParameters.cs`, `HostComplexData.cs` and `HostAmendments.cs` supply the general interactive Analysis-menu host. They suspend the current operation at input boundaries, validate through the original engine and arrange worksheet data as the Windows host does. `OperationSessions` serializes generic analyses and rejects stale answer tokens. R-dependent LOESS and method-comparison regression are explicitly deferred. Suggested follow-on commands and identifier-based pivoting are not yet exposed.
- `Exports.cs` resolves engine types for dynamically compiled scripts when .NET is embedded in the native host.

These are hosting/rendering boundaries, not numerical rewrites. Do not interpret a successful build as certification of every procedure or export format.

## Rebuild

Run `../build.sh` to build, run the original operation tests, verify the live bridge, and package the app. Requirements: Apple Silicon Mac, Xcode command line tools, Python 3, .NET 10 SDK. The .NET runtime is bundled with the app, so the resulting app does not require a separate .NET installation.

`import_upstream.py /path/to/statsdirect` refreshes the vendored source and records file hashes. Platform copies must be reviewed against upstream when updating; this script does not silently reapply adaptations to a different revision.

## Analysis checks

`Tests/test_chi_square.py` exercises the native analysis bridge and compares the help table's Pearson, G and Fisher exact tests against R. It also checks custom scores, report options, seeded Monte Carlo, input validation and cancellation. Compile `Tests/analysis-driver.cpp`, then pass its path to the Python test; Rscript must be available at the configured Mac path.

`Tests/test_agreement.py` checks unchanged paired statistics, original agreement limits, the nine SVG marker coordinates, reference-line geometry, missing-pair handling, edited-data redraw and escaped labels. It writes the verified example SVG to Content/Examples. The native text metrics library is compiled and bundled by FullEngine/build.sh and requires CoreText/CoreFoundation.

## General Analysis menu checks

Build `Tests/operation-driver.cpp` with `clang++ -std=c++17 -arch arm64`, then run `python3 Tests/test_menu.py /path/to/operation-driver`. This checks every menu/help mapping, all 133 enabled entry points, explicit R deferrals, validation retries, stale answers, cancellation and 47 end-to-end analyses. `node --test Grid/*.test.mjs` includes column order, missing-row alignment, selected-formula safety and generated-table export.

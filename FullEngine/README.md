# Full headless calculation engine

This project compiles the StatsDirect 5.0.5 calculation source, rather than extracting a single procedure. `Upstream` is a Git submodule of [iain-buchan/statsdirect](https://github.com/iain-buchan/statsdirect), tracking its primary **main** branch for explicit updates and pinned to the tested commit recorded in `upstream-manifest.json`. The project compiles the calculation source directly from that checkout: all Builtins (apart from the dialog-dependent ImportExport implementation), Numerics, Data, Templates, expression parsers, template processing, chart definitions/renderers, utilities, configuration, CSV and R support. All 284 operation definitions and their report templates are included. Numerical algorithms are unchanged.

The original `OperationTestHost` and `OperationsTester` are compiled unchanged. This source revision contains **two populated operation tests**, covering paired t and exact sign, plus one empty test. Both populated tests pass, checking 26 expected outputs in total. Loading 284 definitions does not mean all 284 procedures have been exercised.

## In-process Mac hosting

`bridge.cpp` hosts the bundled .NET 10 runtime using hostfxr. It loads the entire managed assembly into the Swift application's process. There is no engine subprocess. The regular managed runtime also supports the engine's Roslyn C#/VB script compilation; NativeAOT was inappropriate for that path.

`Exports.Paired` supplies the editable data to a host based on `OperationTestHost`, then executes `TPaired` through `ITemplateProcessor`. `ViewerHost` captures report output with the existing `HtmlRenderer`. The Swift shell retrieves UTF-8 HTML and adds the document header, input snapshot and help link. The viewer passes the optional agreement flag to the original operation; when selected, the original Ties chart renderer produces embedded SVG. `AnalysisIO` also supplies the original ExactChiRbyCScreen operation, including custom scores and simulation, and provides cancellation without publishing partial results.

The host-facing C functions are intentionally small; they are not a replacement calculation layer. `EngineExecution` serializes calculation segments, releasing the engine at interactive host prompts so multiple independent forms can remain open. Each generic job owns its input history, parameter recall, output frames and report. Completed history records include stable parameter names, kinds and acquisition modes for generating R scripts from the original run. The quick paired path retains a last-report buffer, retrieved by the viewer before another quick paired calculation starts.

`AnalysisDefaults` snapshots the six Analysis Options for each new analysis. The native host persists them with `UserDefaults` and supplies them on startup requests. The Analysis Options form combines the original six parameter definitions, validates them as a group, and runs the original settings builtin. Confidence parameters use the saved level without asking only when `CanDefault` and `CanDefaultConfidenceInterval` are both true, matching Windows `ImmediateParameterFiller`. Automatic values are retained in the report history and generated R script. `Tests/test_analysis_defaults.py` checks this behaviour, cancellation, validation, non-defaultable inputs and independent settings for already-open forms.

## Explicit platform boundaries

- `Nonparametric.cs`: full original file with two unused DevExpress namespace imports removed.
- `Settings.cs`: original defaults, a local window-state enum instead of WinForms, and no engine-side persistence. Preferences belong to the host.
- `PlatformHost.cs`: registry/preferences initialization and an opaque window token. Windows file-picker builtins fail explicitly until supplied by the Mac host.
- `SvgCanvas.cs`: original SVG drawing commands with CoreText text measurement and Arial for Mac SVG labels. `MacText.cs` and the small `TextMetrics.cpp` library supply native font metrics. `CanvasTextFormat.cs` supplies alignment values without allocating a GDI StringFormat. Host copies of `TalbotLinHanrahanAxisScaler` and `QuantitativeFormatter` replace Bitmap/Graphics/font-height calls with CoreText; the axis-selection algorithm is retained. The original Ties agreement renderer is unchanged and its SVG geometry is verified. Data/Graphics checks now exercise SVG and text chart paths; this is not full chart or Office-export conformance.
- `RController.cs`: the Windows install dialog is replaced by an explicit exception. Windows R discovery and EMF chart import remain unported; the engine’s R-operation bridge is not supported on Mac yet (the native shell now has an independent R script tab).
- Windows EMF canvas and RTF report renderers are excluded. The RTF image converter remains compiled for existing type dependencies, but its Windows image path is not supported on Mac.
- The project lists its compiled sources and ANTLR grammars explicitly. Default embedded-resource and grammar discovery are disabled so the full upstream checkout does not pull in Windows forms or the separate Windows RTF-converter project.
- `ViewerHost.cs` retains the quick paired and dedicated chi-square paths. `OperationSessions.cs`, `HostParameters.cs`, `HostComplexData.cs`, `HostDataForms.cs` and `HostAmendments.cs` supply the general interactive Data/Analysis/Graphics host. They suspend the current operation at input boundaries, validate through the original engine and arrange worksheet data as the Windows host does. `OperationSessions` preserves each suspended operation stack, uses per-form parameter caches and rejects stale answer tokens. Cancellation clears the pending prompt before publishing its state. `EngineExecution` also protects the quick paired and dedicated chi-square execution paths. R-dependent LOESS and method-comparison regression are explicitly deferred. Suggested follow-on commands and identifier-based pivoting are not yet exposed.
- `Exports.cs` resolves engine types for dynamically compiled scripts when .NET is embedded in the native host.

These are hosting/rendering boundaries, not numerical rewrites. Do not interpret a successful build as certification of every procedure or export format.

## Rebuild

Run `../build.sh` to build, run the original operation tests, verify the live bridge, and package the app. Requirements: Apple Silicon Mac, Xcode command line tools, Python 3, .NET 10 SDK. The .NET runtime is bundled with the app, so the resulting app does not require a separate .NET installation.

An existing clone needs `git submodule update --init --recursive`. The build verifies the submodule revision and all 871 recorded source/asset hashes before compiling. It does not fetch a newer engine during a build.

## Updating the calculation engine

Run these commands from the Mac repository root:

```sh
git submodule update --init --recursive
git submodule update --remote FullEngine/Upstream
git diff --submodule=log -- FullEngine/Upstream
```

Review the upstream changes against the Mac platform copies listed above, especially `Nonparametric.cs`, `Settings.cs`, `SvgCanvas.cs`, the axis scaler and formatter. Resolve any changes in the host without editing numerical algorithms. Then record the reviewed revision, refresh menus if their definitions changed, and rebuild:

```sh
python3 FullEngine/import_upstream.py
# If Windows menu/help definitions changed, with a statisticalhelp checkout:
python3 import_analysis.py FullEngine/Upstream /path/to/statisticalhelp
./build.sh
git add FullEngine/Upstream FullEngine/upstream-manifest.json
# Also stage reviewed host adaptations and generated menu changes, then commit.
```

`import_upstream.py` records provenance only; it neither copies engine files nor reapplies platform adaptations. `--check` verifies the revision and hashes without writing. Commit the submodule pointer, provenance and any reviewed host changes together after the regression checks pass. Push the Mac repository to `iain-buchan/statsdirect-mac`; ordinary Mac work does not require pushing to or changing `iain-buchan/statsdirect`.

## Analysis checks

`Tests/test_chi_square.py` exercises the native analysis bridge and compares the help table's Pearson, G and Fisher exact tests against R. It also checks custom scores, report options, seeded Monte Carlo, input validation and cancellation. Compile `Tests/analysis-driver.cpp`, then pass its path to the Python test; Rscript must be available at the configured Mac path.

`Tests/test_agreement.py` checks unchanged paired statistics, original agreement limits, the nine SVG marker coordinates, reference-line geometry, missing-pair handling, edited-data redraw and escaped labels. It writes the verified example SVG to Content/Examples. The native text metrics library is compiled and bundled by FullEngine/build.sh and requires CoreText/CoreFoundation.

## General menu and multiple-form checks

Build `Tests/operation-driver.cpp` with `clang++ -std=c++17 -arch arm64`, then run `python3 Tests/test_menu.py /path/to/operation-driver`. This checks every menu/help mapping, all 206 enabled entry points, explicit R deferrals, validation retries, stale answers, cancellation and 47 end-to-end analyses. `Tests/test_data_graphics.py` adds 74 data/graphics cases, including SVG output and expected transformed data. `Tests/test_sessions.py` interleaves six open forms, including duplicate methods and agreement charts, compares their outputs with serial runs, and checks independent cancellation and stale input rejection. `node --test Grid/*.test.mjs` includes column order, missing-row alignment, selected-formula safety and generated-table export.

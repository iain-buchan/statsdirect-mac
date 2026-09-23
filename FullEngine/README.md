# Full headless calculation engine

This project compiles the StatsDirect 5.0.5 calculation source, rather than extracting a single procedure. `Upstream` contains the source from the commit recorded in `upstream-manifest.json`: all Builtins (apart from the dialog-dependent ImportExport implementation), Numerics, Data, Templates, expression parsers, template processing, chart definitions/renderers, utilities, configuration, CSV and R support. All 284 operation definitions and their report templates are included. Numerical algorithms are unchanged.

The original `OperationTestHost` and `OperationsTester` are compiled unchanged. This source revision contains **two populated operation tests**, covering paired t and exact sign, plus one empty test. Both populated tests pass, checking 26 expected outputs in total. Loading 284 definitions does not mean all 284 procedures have been exercised.

## In-process Mac hosting

`bridge.cpp` hosts the bundled .NET 10 runtime using hostfxr. It loads the entire managed assembly into the Swift application's process. There is no engine subprocess. The regular managed runtime also supports the engine's Roslyn C#/VB script compilation; NativeAOT was inappropriate for that path.

`Exports.Paired` supplies the editable data to a host based on `OperationTestHost`, then executes `TPaired` through `ITemplateProcessor`. `ViewerHost` captures report output with the existing `HtmlRenderer`. The Swift shell retrieves UTF-8 HTML and adds the document header, input snapshot and help link. The optional agreement analysis is off in the viewer.

The host-facing C functions are intentionally small; they are not a replacement calculation layer. Calls are serialized by the viewer. The report buffer is the last completed calculation, and must be retrieved before another calculation starts.

## Explicit platform boundaries

- `Nonparametric.cs`: full original file with two unused DevExpress namespace imports removed.
- `Settings.cs`: original defaults, a local window-state enum instead of WinForms, and no engine-side persistence. Preferences belong to the host.
- `PlatformHost.cs`: registry/preferences initialization and an opaque window token. Windows file-picker builtins fail explicitly until supplied by the Mac host.
- `SvgCanvas.cs`: original SVG canvas with Windows text measurement replaced by an explicit unsupported-platform exception. Full chart rendering is **not yet ported**. Other chart code still contains System.Drawing dependencies; the original HTML renderer reports chart failures in the report.
- `RController.cs`: the Windows install dialog is replaced by an explicit exception. Windows R discovery and EMF chart import remain unported; external R scripts are not supported on Mac yet.
- Windows EMF canvas and RTF report renderers are excluded. The RTF image converter remains compiled for existing type dependencies, but its Windows image path is not supported on Mac.
- `ViewerHost.cs` supplies only the parameter/output capabilities needed by this viewer. Other operations may require further host implementations even though their calculations compile.
- `Exports.cs` resolves engine types for dynamically compiled scripts when .NET is embedded in the native host.

These are hosting/rendering boundaries, not numerical rewrites. Do not interpret a successful build as certification of every procedure or export format.

## Rebuild

Run `../build.sh` to build, run the original operation tests, verify the live bridge, and package the app. Requirements: Apple Silicon Mac, Xcode command line tools, Python 3, .NET 10 SDK. The .NET runtime is bundled with the app, so the resulting app does not require a separate .NET installation.

`import_upstream.py /path/to/statsdirect` refreshes the vendored source and records file hashes. Platform copies must be reviewed against upstream when updating; this script does not silently reapply adaptations to a different revision.

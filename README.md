# StatsDirect report and help viewer — first prototype

Open **StatsDirect Viewer.app** on this Mac. It contains a documented report example and the original StatsDirect HTML help collection, with a searchable index of 400 topics. Use Open HTML to display a saved report; use Reload after replacing that report with new engine output.

## What this establishes

A small native macOS host displays HTML tables, SVG and existing help using WKWebView. The interface provides back/forward navigation, copy/select-all, printing and PDF export. External web links open in the default browser. Local help works offline. The HTML content is independent of the host and can be reused by a C# application.

The report table is copied verbatim from the repository's Michelson help example. Its SVG confidence interval graphic is an explicitly labelled rendering fixture. No statistics are calculated by this prototype.

## Scope and limitations

- This is a Swift/AppKit feasibility host, not the proposed Avalonia/C# application. Swift was available locally; a .NET executable was not found on PATH.
- The calculation engine is **not connected**. The existing engine and renderer are still compiled into a Windows-targeted project with commercial UI dependencies. Engine extraction is a separate step.
- Original help pages and assets are bundled unchanged. The title/category filter is a new index, not full-text search. Existing help instructions describe the Windows product.
- Open HTML grants local resource access to the selected file's containing directory. For multi-folder help, use the bundled help library. HTML/MHT are not interchangeable: MHT/MHTML import is not implemented.
- Save PDF uses WKWebView's document capture. For paper sizes, margins and paginated output, use File → Print → PDF.
- Copy uses macOS WebKit's standard selection support. Fidelity when pasting tables or charts into Microsoft Word remains to be checked manually.
- Built for Apple Silicon on this Mac. Ad-hoc code signed for local testing; not Developer ID signed or notarized for distribution.
- Open trusted HTML only. No privileged JavaScript-to-native engine bridge is exposed, but the viewer is not a general-purpose untrusted-document sandbox.

## Source and integration point

Source: https://github.com/iain-buchan/statsdirect

Inspected commit: `c56f888bd95604f9d656e90ad0236493a96f2ae7` (StatsDirectUI project version 5.0.5).

The existing Windows report window obtains HTML with `new HtmlRenderer(host).Render(renderable)`, wraps the fragment in a `statsDirectResults` element with operation/help metadata, and appends it to the document. `HtmlImageRenderer` uses `SvgCanvasFactory` and returns inline SVG. This is the appropriate boundary for a future C# viewer; calculation code should not move into JavaScript.

Relevant repository paths:

- `StatsDirectUI/TemplateProcessing/HtmlRenderer.cs`
- `StatsDirectUI/TemplateProcessing/CreoleHtmlReportRenderer.cs`
- `StatsDirectUI/TemplateProcessing/HtmlImageRenderer.cs`
- `StatsDirectUI/UI/frmReportDotNetBrowser.cs`
- `StatsDirectUI/Assets/WebHelp/`

Next integration step: separate enough of the existing renderer/engine to run a genuine univariate operation on macOS, feed its rendered output to the viewer, and compare against a captured Windows result. No engine equivalence is claimed by this prototype.

## Rebuild and test

Run `./build.sh` with Apple Command Line Tools installed. No external Swift packages are required. Build output is placed beside this README.

For the WKWebView smoke test, set `VIEWER_TEST_DIR` to an existing writable directory, then run `StatsDirect Viewer.app/Contents/MacOS/StatsDirectViewer --self-test`. The test validates the saved table and SVG, exports a PDF, follows the help link, checks help image loading, then follows a reference link. It saves screenshots and `result.txt`.

StatsDirect's MIT notice is retained in STATSDIRECT-LICENSE.txt. Bundled help assets retain their existing notices.

## Verification performed on 23 September 2026

Built successfully with the installed Swift compiler. Launched using the desktop app tools and visually verified the report table, inline SVG, original help text/equation rendering, navigation to the references page, and filtering the help index for Kaplan–Meier. Saved a PDF successfully; the native print dialog generated a two-page preview. No physical printing was performed. Clipboard-to-Office and live engine output remain untested. The optional automated smoke-test launch was blocked by the shell's GUI environment before app startup; the checks above were performed through the running desktop app instead.

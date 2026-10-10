# StatsDirect for Mac

A native macOS preview of StatsDirect, using the [Windows calculation engine](https://github.com/iain-buchan/statsdirect) with tabbed worksheets, analyses, reports and R sessions, plus offline help that docks beside your work or opens in its own window.

## Download

**[Download the latest Mac release](https://github.com/iain-buchan/statsdirect-mac/releases/latest)** — Apple Silicon, macOS 14 or later.

Expand the application ZIP and move **StatsDirect.app** to Applications. This preview is not yet Apple Developer ID signed or notarised; see the release notes for installation details. **Help → Check for Updates** finds new releases; installation is currently manual.

Upgrading from 0.3.18 or earlier: after saving work and quitting the old app, remove **StatsDirect Viewer.app** from Applications to avoid keeping both names. Your existing settings and learning records are retained.

## Get started

Open your data with **File → Open**, or choose **Help → Example workbook**, then select a method from **Analysis**.

- Open Excel workbooks (`.xlsx`, `.xls`, `.xlsb`, `.xlsm` and templates), including password-protected files. Save data as `.xlsx`, CSV or R files.
- Keep results together in an editable report with SVG charts; open legacy RTF reports and save as HTML, PDF or Word documents.
- Continue supported analyses in editable R sessions; install R through the app if needed.
- Use **Help → Learning** for biostatistics, epidemiology, practice questions and a tutor connected to your open work. **Use my ChatGPT** signs in through your browser; your account’s Codex access and usage allowance apply.

## Build

Requires an Apple Silicon Mac, Xcode command line tools, Python 3 and either the .NET 10 SDK or Docker Desktop.

```sh
git clone --recurse-submodules https://github.com/iain-buchan/statsdirect-mac.git
cd statsdirect-mac
./build.sh
```

For Docker, run `./docker-build.sh` instead. The build restores missing submodules at their pinned revision. Prebuilt web content is included; R is not needed to build or run StatsDirect.

`./build.sh` defaults to an optimised Release build of the Swift shell and native bridges, retaining runtime safety checks. Matching crash-debugging symbols are saved under `.build/symbols/Release`, outside the app. Use `STATSDIRECT_CONFIGURATION=Debug ./build.sh` for an unoptimised native build; the managed calculation engine uses its existing Release configuration.

Run `./test.sh` for engine and R comparison tests (requires R; `RSCRIPT` can select its executable).

Offline help is imported independently of the engine pin: fetch `FullEngine/Upstream`, then run `python3 Scripts/import-desktop-help.py <published-statsdirect-commit>`. This copies the complete Windows DesktopHelp bundle without changing its files. Run `python3 Tests/test_desktop_help.py` and `Scripts/test-help-pane.sh` to verify it.

Every push to `main` and every pull request runs `.github/workflows/ci.yml` on a GitHub-hosted Apple Silicon runner: the build, `test.sh`, the JavaScript tests, the Excel and data-file tests, the report export and the WebKit integration driver, and a check that the committed `Content` bundles match their sources.

## Documentation

[Reports](Report/README.md) · [Data grid](Grid/README.md) · [Learning](Learn/README.md) · [Engine and updates](FullEngine/README.md) · [Verification and limitations](Tests/verification.md)

# StatsDirect for Mac

A native macOS preview of StatsDirect, using the [Windows calculation engine](https://github.com/iain-buchan/statsdirect) with tabbed worksheets, analyses, reports and R sessions, plus offline help that docks beside your work or opens in its own window.

## Download

**[Download the latest Mac release](https://www.statsdirect.com/download.aspx)** — Apple Silicon, macOS 14 or later.

Expand the application ZIP and move **StatsDirect.app** to Applications. From version 1.1.2, StatsDirect checks for a stable release at each launch when **Automatic Update Checks** is enabled. **Install Now** verifies the update and uses the normal quit flow before restarting StatsDirect. You can also check from **Help → Check for Updates** or download an update through your browser.

Upgrading from 0.3.18 or earlier: after saving work and quitting the old app, remove **StatsDirect Viewer.app** from Applications to avoid keeping both names. Your existing settings and learning records are retained.

## Get started

Open your data with **File → Open**, or choose **Help → Example workbook**, then select a method from **Analysis**.

- Open Excel workbooks (`.xlsx`, `.xls`, `.xlsb`, `.xlsm` and templates), including password-protected files. Save data as `.xlsx`, CSV or R files.
- Keep results together in an editable report with SVG charts; open legacy RTF reports and save as HTML, PDF or Word documents.
- Source builds can export reports as Jupyter notebooks and reopen StatsDirect notebooks into new report, data and R script tabs. Imported R code runs only when requested.
- Choose **Continue in R** from a report's toolbar or context menu to open and run its editable script, or **File → New Script** to start your own. Script and Console views share an interactive workspace, with SVG charts and guided R setup. **Open in R (R+)** opens the script in RStudio or R.app.
- The script toolbar's **AI** icon opens a conversation beside your code, using your ChatGPT connection. Choose whether to share the script/output and a workbook, and check for person identifiers before sending.
- Open **Analysis → Calculator** for the StatsDirect expression calculator. It docks below your work or pops out, with wrapping input and saved calculations for the current session.
- Use **Help → Learning** for biostatistics, epidemiology, practice questions and a tutor connected to your open work. **Use my ChatGPT** downloads its connection component once (about 94 MB, no administrator password), then signs in through your browser; your account’s Codex access and usage allowance apply.

## Build

Requires an Apple Silicon Mac, Xcode command line tools, Python 3, Node.js 24 with pnpm, native Apple Silicon R (for the console headers), and either the .NET 10 SDK or Docker Desktop.

```sh
git clone --recurse-submodules https://github.com/iain-buchan/statsdirect-mac.git
cd statsdirect-mac
corepack enable
for dir in Grid Report Learn; do (cd "$dir" && pnpm install --frozen-lockfile); done
./build.sh
```

For Docker, run `./docker-build.sh` instead. The build restores missing submodules at their pinned revision. It resolves the latest published help/tutor snapshot from `statisticalhelp` once and incorporates that pinned content into the app. Installed apps use their bundled content. Use `STATSDIRECT_CONTENT_MODE=offline ./build.sh` to rebuild committed inputs without fetching content; [content build modes](Docs/help-editor-content.md) also cover explicit pins. R is only needed by users when starting an R session.

`./build.sh` defaults to an optimised Release build of the Swift shell and native bridges, retaining runtime safety checks. Matching crash-debugging symbols are saved under `.build/symbols/Release`, outside the app. Use `STATSDIRECT_CONFIGURATION=Debug ./build.sh` for an unoptimised native build; the managed calculation engine uses its existing Release configuration.

Set `STATSDIRECT_APP_OUTPUT="$PWD/.build/ready/StatsDirect.app"` to build separately while an existing copy is running.

Run `./test.sh` for engine and R comparison tests (requires R; `RSCRIPT` can select its executable). The app uses the newest R it finds (CRAN's framework versions, then Homebrew); the script pane runs any R, and the interactive console needs an Apple Silicon R 4.2 or later.

A release is signed and notarised from a tested build by the steps in [SIGNING.md](SIGNING.md), with `Scripts/sign-app.sh` and the entitlements in `StatsDirect.entitlements`.

Help and tutor publications are independent of the engine pin. Their receipts, complete file hashes and shared revision are validated before each app build; [the content contract](Docs/help-editor-content.md) describes explicit refresh and offline verification.

Every push to `main` and every pull request runs `.github/workflows/ci.yml` on a GitHub-hosted Apple Silicon runner: the build, `test.sh`, the JavaScript tests, the Excel and data-file tests, the report export and the WebKit integration driver, and a check that the committed `Content` bundles match their sources.

## Documentation

[Reports](Report/README.md) · [Data grid](Grid/README.md) · [Learning](Learn/README.md) · [Engine and updates](FullEngine/README.md) · [Verification and limitations](Tests/verification.md)

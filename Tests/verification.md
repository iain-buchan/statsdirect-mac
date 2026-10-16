# Unreleased — Help menu command parity — 14 October 2026

Compared the actual Windows menu construction in `frmMain.Designer.cs` and
`LearningCommands.cs` at Windows main `76911c12`. Mac Help now has the same seven
commands: Learning, Learning Options, Contents and Index, Method Selection,
Example workbook, Check for Updates, and About StatsDirect. Labels match after
normalising Windows accelerator marks and ellipses. Mac retains the user's
requested Example workbook section **before** updates and About last; Windows
currently puts updates before the example section. Windows source was not edited.

Method Selection opens offline context 1213, the same topic as Windows. F1 and
document-toolbar context help remain available. Back/Forward stay in the Help
viewer; the existing automatic-update toggle moves to the StatsDirect app menu,
retaining its saved preference. Both native and in-window menus use this definition.

Native Help checks passed (48 PASS groups), including actual Contents/Method Selection menu actions,
worksheet-selection preservation, offline search, navigation, docking, context help
and PDF output. All 982 help files match the source manifest; all 800 aliases and
167 engine help context IDs resolve. The native Script suite also passed (65 PASS
groups), including opening the example workbook and inspecting its PEFR data.
Logs: `.build/help-menu-native.log` and `.build/help-menu-script.log`.
The Release native build passes matching-symbol and strict signature verification
(`.build/help-menu-package.log`) and is available at
`.build/help-menu/StatsDirect.app`, reusing the previously verified engine/content.
Existing AI WebView/session-sharing work is preserved. No commit, push or release.

# Unreleased — AI WebView output and session sharing — 14 October 2026

Report and Script AI now use an isolated WKWebView for their conversation output,
reusing the existing Learning renderer without changing it. Headings, tables, lists,
maths and R code render as HTML. Selection, copying, scroll position and following
new replies are preserved during streaming. Renderer termination recreates the view
from native messages and the latest partial reply, without resending a question.
The page blocks external resources, frames, media and popups; code actions use the
native conversation/message checks and Open in R still opens unexecuted code.
The HTML Copy and Open in R buttons were exercised through their real native bridge;
the rendered table, equation and R code were inspected visually.

Sharing acceptance is kept in memory across Report, Script and Learning for the
whole app session. Switching between those windows or starting a new conversation
does not reset it. Restarting the app, selecting another workbook tab, or choosing
a different workbook in the AI context picker requires fresh confirmation. Context
choices remain visible and editable, and every question is scoped to its selected
documents. Edits invalidate a question's read snapshot, not session acceptance.
Learning continues to save a context record before granting access, now recording
whether app-session acceptance was reused. No acceptance is loaded from disk.

Passed locally: native Report AI, native Script AI (64 checks plus completion),
native Learning context/consent with the real example workbook and engine, session
consent boundary/approved-set checks, and
45 report/Learning/worksheet JavaScript tests. The Report suite includes an actual
isolated WebKit renderer termination, rich HTML/math assertions, blocked external
fetches, Report-to-Script and Report-to-Learning consent reuse, selected-data resets,
and new-app consent reset. The native Script suite verifies streamed Unicode
selection/copying, reading position, keyboard routing and original-data R replay.
AI protocol traffic is synthetic and local; no live user data or AI account is used.

The Release app build passed 1,552 distribution checks, matching debug symbols and
strict ad-hoc signature verification. Build: `.build/ai-webview/StatsDirect.app`.
Logs: `.build/ai-webview-{report,script,learning,js,build}.log`.
The user's running `.build/report-ai/StatsDirect.app` was not replaced.
Windows, engine and shared report-editor sources are unchanged. These changes have
not been committed, pushed or published.

# Unreleased — Report AI dock — 14 October 2026

The later WebView/session-sharing entry supersedes the per-question confirmation
and native NSTextView behavior described in this first implementation.

The Mac Report toolbar and right-click menu now open AI assistance in the same
right dock as Script. Each report has its own conversation and draft. The existing
ChatGPT account and first-use setup are reused, with report-specific instructions
for interpreting estimates, uncertainty, assumptions and statistical methods.

Sharing starts off. Each question with report context requires confirmation; the
assistant receives a fixed, bounded snapshot of displayed report text, method IDs
and chart labels. It never receives hidden run records or chart pixels. Workbook
sharing is separate. Read-only tools provide approved context and bundled method
help; suggested R code opens for review without running. See
`Docs/Learn/TutorPrivacy.md` for exact limits and lifecycle.

Verified locally:

- Native report AI: 32 checks plus completion, including real nine-pair PEFR
  paired t/agreement output, report-specific provider instructions, method-help
  round trip, question-only privacy, consent, unshared-document exclusion, fixed
  snapshots, large/empty reports, separate conversations, Help docking, cancellation,
  keyboard/close behaviour and institutional policy.
- Existing native Script AI suite, including streaming selection/copying,
  Command-Return, full R replay and source boundaries, passed. The test now waits
  for activation before restoring composer focus, avoiding a macOS focus race.
- 19 unified report/grid toolbar checks plus completion, including narrow layouts,
  More commands, formatting selection, Find, clipboard, undo and save/export.
- 45 report/Learning/worksheet-privacy JavaScript checks and the tutor protocol,
  privacy and policy suites passed.
- Release build with engine 5.2.0 passed all 1,552 distribution regression checks;
  the final native rebuild verifies signatures and matching debug symbols.
- Native report/dock layout inspected with paired results and the agreement chart.

AI integration tests use a local synthetic protocol fixture, with no live AI
account, external question or private user report. App build:
`.build/report-ai/StatsDirect.app`. Logs: `.build/report-ai-native.log`,
`.build/report-ai-script-regression.log`, `.build/report-ai-toolbars.log`,
`.build/report-ai-protocol.log`, `.build/report-ai-js.log` and
`.build/report-ai-build.log`.

No changes to the engine pin, Windows sources or shared `Report`/`Content/Report`
editor. No commit, push or release has been made for this feature.

# Unreleased — Creole report presentation — 12 October 2026

The Mac report host now loads `Content/Mac/report.css` in the page head, using
the Windows Creole defaults: Arial 10pt, underlined titles/subtitles, the seven
semantic result colours, Courier New preformatted text, and plain left-aligned
tables with underlined headers. Instant-answer previews and the isolated HTML
importer use the same defaults. Fresh engine output retains its own title without
an extra host heading or timestamp. Inline and custom stylesheet formatting
continues to override defaults. Charts remain centred for the shared resize
gesture, with intrinsic and edited widths preserved.

The full native report suite passed all 49 check groups, covering real paired-t,
agreement, chi-square and R-generated reports, all Creole tags, Windows HTML and
legacy RTF import, HTML/PDF/DOCX, clipboard/Excel number formats, custom fonts and
borders, editing, deletion, drag/move, chart sizing, undo and Continue in R.
Independent Word-package checks verify the colours, 10pt typography and tables.
The native paired-test screenshot was inspected. The Release build passed all
1,552 distribution checks and strict signature verification.

Local build: `.build/creole-styles/StatsDirect.app`. Logs:
`.build/creole-build.log` and `.build/creole-report-checks.log`.
No changes to the engine, Windows sources or shared `Report`/`Content/Report`
editor. These changes are not yet committed or published.

# Mac 0.3.29 — follow-on analysis validation — 12 October 2026

Fixed a Mac host issue where follow-on worksheet output could lose the parent's
input range, worksheet snapshot or entered-data flag. Follow-ons now retain those
properties from the completed parent fit, including after writing output. A
worksheet or workbook selected subsequently cannot become the output destination
by accident. Entered-data analyses continue to create separate output worksheets.
The calculation engine, Windows sources and shared report editor are unchanged.

Validation passed:

- `Tests/test_form_follow_ons.py` against the released 0.3.28 engine: all 67
  follow-on operations and 21 supporting parent calculations.
- `Tests/test_follow_on.py`: suggestion inventory, inherited data, chained
  post-hoc tests, regression plots, invalid parents and released sessions.
- `bash Scripts/test-follow-on-workflow.sh Releases/0.3.28/StatsDirect.app`:
  101 native parent/follow-on paths covering every one of the 67 operations.
  Parents are calculated through the real engine using recorded fixtures;
  follow-ons are launched by their WebKit buttons and submitted through their
  rendered Mac controls. Includes one-/two-way and replicated ANOVA comparisons,
  simple/multiple/polynomial/logistic/Poisson/Cox regression, nonparametric tests,
  PCA, chained post-hoc tests and follow-ons after polynomial refitting. Checks
  active-report reuse, inherited help and worksheet output. A separate case
  switches both worksheet and workbook before Cox baseline export and verifies
  the original worksheet/range receives the output with unrelated data preserved.
- `Tests/test_follow_on_numerics.py`: Tukey critical value and pooled SD agree
  with independent R; chained Bonferroni matches direct use. Quadratic and refitted
  cubic predictions, confidence limits and prediction limits agree with R.
  Retained original and unrelated fits remain independent.
- `Tests/test_run_record.py`: 113 checks passed, including the 59 follow-ons with
  inherited R recipes, 142 inherited frames, and the four worksheet-only routes
  that correctly leave no report-step record. All 158 documented R scripts ran.
- Release build passed, including 1,552 distribution checks and matching native
  debug symbols. Local app: `.build/follow-on-app/StatsDirect.app`.

The new native suite is included in build CI and is available as the `follow-ons`
packaged-runtime workflow choice. Numerical/isolation checks are in `test.sh`.
These fixes are packaged as 0.3.29, retaining the tested 5.1.0 engine from 0.3.28.

# Mac 0.3.28 — report and Script toolbars, Open in R — 12 October 2026

Mac reports now expose Cut, Copy and Paste alongside their existing Undo/Redo
and formatting controls. The Script toolbar adds Undo, Redo, Cut, Copy and Paste;
Copy also works on selected output. Cut/Paste in read-only output cannot alter
an old selection in the script. These changes use the Mac host's existing native
clipboard and undo paths; Windows and the shared editor are unchanged.

Open in R now runs the saved script in a fresh R.app process through a private
startup profile, retaining the results, variables, editor and Quartz charts.
An existing R session and the user's startup profile are left intact. RStudio,
when installed, still opens the script in its editor, matching Windows.

The Release build, 1,552 distribution checks, native R integration, paired
workflow, script AI dock and report transfer/export suites passed. New checks
exercise the toolbar buttons, formatting/tables/SVG with undo, read-only output,
real R startup, once-only execution, quoted Unicode paths and agreement-chart
creation. The real desktop workflow using test.xlsx's nine PEFR pairs also
passed: select A/B, paired t with agreement, Run, report context-menu Continue in
R, then Open in R. R.app's console showed t = 4.925774 and the agreement limits
-10.868665 to 123.090887, with the Quartz chart visible.

This maintenance release retains 0.3.27's tested engine 5.1.0 pin at `3cc4cbc9`;
newer engine/help changes on main are outside its scope. The package copies the
tested app, changing its version, restoring the normal bundle identifier used
before side-by-side testing, and renewing its outer ad-hoc signature. Apple
Developer ID signing and notarisation remain outstanding.

# Mac 0.3.27 release verification — 11 October 2026

The tested AI-dock build at `2de31e4` is packaged as 0.3.27, retaining engine 5.1.0
at `3cc4cbc9`. Only its version and outer ad-hoc signature differ. Release preparation
fixes timing in the paired-selection and workbook-notice test fixtures, and includes
the report-toolbar/write-back fixture fixes from `3519ba3`; application, engine and
shared-editor source are unchanged.

The extracted package passed local native regression and Office-format checks, strict
signatures, matching archived symbols, all 982 Help hashes and version checks. The
complete GitHub build/regression suite and the separate macOS 15 packaged integration
suite passed. [Checksums, exact scope and run links](../Docs/Validation/Beta-0.3.27/README.md).
Apple Developer ID signing/notarisation remain outstanding.

# Verified engine and AI dock integration — 11 October 2026

The AI dock/interaction work from `3278ad2` is integrated with Mac main through `b5e0baa`.
The user authorised the verified engine update, superseding the earlier hold. The engine
is now 5.1.0 at `3cc4cbc92ab779880d7fc8f04d1a94ee47e2b620`, with 872 source/asset hashes
verified. No upstream numerical source or Windows repository file was changed. All 22
shared editor modules/bundles are byte-identical to incoming main and the released editor
pin. The 158 R recipe files and their 227-operation manifest match the engine exactly.

Continue in R retains the shared run-record writer and opens the normal Mac script tab
with the AI dock, method help and protection for subsequent edits. Incoming Find/Replace,
R-generated SVG, output-file links and Open in R remain available. The Mac-only toolbar,
editable reports and combined analysis forms are retained. Grouped history uses the same
parameter-kind mapping as the sequential host. The R integration fixture now quotes paths
without JSON's optional escaped slashes; the imported report tests exercise contextual
R toolbar actions instead of the removed top-level R menu. Native form fixtures follow
automatic data selection, preserve the Cuzick prepared-score checks, and explicitly use
the saved group-identifier layout for long data. The native control suite caught and
fixed a Mac input-resolution bug: JavaScript arrays have a `values()` iterator, which
must not be mistaken for a combined form's `values` object. List answers now stay arrays.

Completed checks on `.build/engine-ai-integration/StatsDirect.app`:

- Release build, 1,552 distribution checks, matching native debug symbols and strict deep
  ad-hoc signature verification; no compiler warnings. Bundled content matches the rebuilt
  Grid, Learn, Report, Mac and R sources.
- Full `test.sh`: all 208 menu hosts and offline links; help replay, numerical/R comparisons,
  concurrent forms and cancellation; 66 grouped workflows with matching results, active
  recorded inputs and settings; 113 run-record checks; all 227 recipe/help comparisons;
  109 JavaScript tests. Explicit nondefault confidence checks include the corrected Poisson
  and conditional-logistic 99% limits and a predictor named “Smoking status”.
- Native R integration (37 checks), AI dock/sharing (30), paired workflow (36), other analysis
  workflows (17), offline Help (41), and column selection gestures (18). Native Cuzick
  prepared scores/rejected edits, selected Woolf/Mantel–Haenszel tables and all 12 shared
  control variants also pass after the list-answer fix.
- Full native beta suite: learning/provider controls and privacy, report editing/transfer/
  deletion/undo, HTML/PDF/DOCX and legacy RTF, Windows report reopen and run records,
  relocated/changed/unavailable worksheet data, Find/Replace, million-row embedded input,
  grouped layouts, and automatic worksheet write-back/undo. Independent DOCX/clipboard
  package checks confirm styles, borders, tables, SVG/PNG sizes and Excel numeric formats.
- Excel import/export, edge cases, insertion/structural edits and compatibility; CSV/R data
  round trips and numeric formatting (46 checks); calculator engine (29 cases). Offline
  help provenance passes for 982 files, 800 aliases and 167 context mappings.

The grouped-run comparison permits only the shared processor's unused iteration, seed
and confidence defaults when a simulation control is false; active inputs and results
must still match exactly. No shared engine change was made to suppress those defaults.
AI tests use local protocol fixtures and fictional data; no live AI prompt or email was
sent. The candidate was built separately from the user's running app. This is a source
integration and local build, not a new installer release or Apple notarisation.

# Mac analysis and report interaction — 11 October 2026

Reports open as one editable area. Mac-only controls provide contextual Help and Continue in R in the toolbar and native context menu; Edit/Add text buttons, separate Report notes, engine-credit footer and visible input-history code are removed. Blank reports accept typing with undo/redo. Shared editor sources and rebuilt bundles are byte-identical to `4e9f9d10a7dbf795c28fc3dc3e5924476a3bc1d6`, the revision already released by Windows. No Windows source or engine pin was changed.

Compatible highlighted worksheet data is used automatically by the general forms. Engine parameter groups share Run, with conditional previews, original validation and saved confidence defaults. Dedicated weight/role selections remain separate; over-wide selections are not cropped. All 207 commands open and 66 grouped cases match sequential numeric/frame output. The complete `test.sh` suite (including 107 JavaScript tests), native analysis/paired/R suites, report editing/clipboard/export/import suite and Word package checks passed. Release build, TypeScript and signature/debug-symbol checks passed. [Implementation and release-boundary note](../Docs/mac-interaction-update-2026-10-11.md).

# Paired t-test click parity with Windows — 11 October 2026

Selecting the measurement columns and choosing Analysis → Parametric → Paired t now opens one form with the selected column names/range, an Agreement analysis checkbox and Run. The optional Change data button reveals the existing data-entry and group-layout controls. Both answers still pass through the original engine's validation; the saved confidence default is used without a separate step. One differences column disables agreement, and a selection wider than two columns is not silently cropped.

`Scripts/test-paired-workflow.sh` passed 35 native integration assertions through the actual worksheet, Parametric menu, WebKit message bridge, engine and active report. Checks include a single heading drag followed by checkbox/Run, the nine PEFR pairs (despite an unrelated longer column), the Windows mean and 95% confidence limits, all nine SVG markers, unchecked agreement, one differences column, optional data changes, cancellation, a saved 99% confidence level and the explicit-confidence preference. All 72 grid model tests, TypeScript checking, regenerated bundle and app signature verification passed. The suite is included in CI. The calculation engine and its pin were unchanged.

The updated local app was opened on its bundled test.xlsx PEFR selection; the selected rows 2–10, Agreement checkbox and Run were also verified visually. The source changes are not yet committed or published.

# Dragging to select worksheet columns — 11 October 2026

Column headings now support dragging to select adjacent whole columns, with horizontal edge scrolling. Shift/Command clicks, cell rectangles and edge resizing retain their existing behavior. Selection uses compact column ranges, including on sparse worksheets with Excel's maximum dimensions. Worksheet changes, mouse release, loss of focus and Escape cancel the drag.

Validation: all 72 grid model tests and the TypeScript check passed. `Scripts/test-grid-selection.sh` passed 18 assertions in actual WKWebView: both drag directions, starting on selected headings, clipboard column order, modifier clicks, cell selection, release outside the grid, focus loss, resizing, edge scrolling, pre-scrolled sheets, worksheet reload and Excel dimensions. The suite is included in CI. Desktop automation only clicked at the drag start for both the new column gesture and the existing cell gesture, so a physical-mouse check remains. Removed an obsolete width-reset call when switching worksheet tabs; widths already belong to their worksheet's column objects.
# Run record and R scripts from the engine — 11 October 2026

The record of a run and the R script written from it are the engine's own (`RunRecord`, `OperationRun`, `RScriptWriter`, `RRecipes` in the pinned Windows source, compiled into the Mac headless engine), so the record's fields, hashes and the script's text are the same as on Windows by construction. The Mac supplies what the engine cannot know: `OperationHost` adds the source Document's workbook name and saved path to a worksheet frame's answer (`worksheet.workbook`/`workbookPath`; the tutor's `TutorTools.frame` does the same), from which `HostParameters.ReadFrame` attaches `WorksheetOrigin` to the frame's variables; the completed snapshot carries the record as `record` (JSON text) and `recipe` (whether `Content/R/analysis-recipes.json` covers the operation), which `ReportEntry` keeps and `data-r` and the context menu (Continue in R / Open Data and Settings in R) follow. Continue in R (`Sources/ReportRHost.swift`, `Sources/RunRecordR.swift`) reads the columns a record points to and does not hold — from the open grid showing the workbook (by path, then by name) through `columnValues` with the cells' kinds, else from the file through the engine's workbook open and the typed snapshots, else it passes the Windows FrameReader's reason — and asks the engine's `statsdirect_r_script` entry for the script, which re-reads the texts under the recorded acquisition mode so unchanged cells give no NOTE and a changed cell exactly one; the text opens in a new R pane with the Windows status lines. A saved HTML report carries `<meta name="statsdirect-report-format" content="1">` and the `statsdirect-report-data` block (each result's id, title, operation, help and record, the engine's text verbatim, `<` escaped) as the Windows report writes it; reopening converts each saved result on its own (the page with only that result's block, or the block's markup for a Windows-saved report), validates the records (version 1, an operation name, columns 1…16,384, rows 1…1,048,576, 16-hex hashes, bounded text, no control character in any string or key — the writer puts the title, file, sheet, column titles and parameter names into the script's comment lines as they are, so a line feed would leave R to run — and ISO 8601 `run` and `source.modified` times) and restores them, so Continue in R works after reopening; a live record holding a control character (a worksheet title typed with a line break) is not written as a script either, until the shared writer neutralises them (raised with Windows). A frame pointing at more than 2,000,000 cells (its distinct columns over the rows they span), or taking the record's frames past 5,000,000, is left unread with the reason rather than asked of the grid or the engine. A closed workbook whose formula cells have no saved results (this program's own streaming save leaves formulas so, for Excel to recalculate) is reported as unreadable, as the grid refuses to analyse such cells, instead of being hashed as blanks and noted as changed. The saved page's metadata block carries each result's `html` as its block's markup in the exported page, with the presentation resolved, as the Windows report saves each `.report-body` and rebuilds the result from it. The Distributions form records the calculator's boxes as Windows does (`ctlPDF.Fill`): every shown box as an input under the calculator's names with the number the box shows (a probability to 15 decimal places), the report line its only output, so the record and the script are the Windows text; the forward fixtures and the normality checks take the tails from the report line. Save As of a workbook renames the Document (name, path, title) and asks the grid to follow (`renameWorkbook`). The Swift record builder and script generator (`RunRecord.swift`, `RScriptGenerator.swift`, their unit test and driver, `test_r_scripts.py`) are gone.

Checks: `Tests/test_run_record.py` (in `test.sh`, through `Tests/operation-driver` and `Tests/engine-driver`, mirroring tests/RScript on Windows check for check): the pointer record of a TPaired run from the example workbook (file, path, modified, prompt order and kinds, mode, columns, rows [1, 21] with the title row, hashes as defined, no values on a pointer, the settings and results, the kept data), rows [3, 22] without a title, an unsaved workbook, an entered frame, the 5,000-value threshold, a long layout as entered, a 2 by 2 table, a distribution calculation's boxes (value, lower, upper and two_sided to the 15 decimal places the boxes show, asked, and the report line as the only result); the script entry: the recipe's head and vectors, run in R against the engine's t, P and interval, the record's own title, no Data line for entered data, the re-read with no NOTE and with exactly one NOTE after one changed cell, the unreadable and mismatched cases, the matrix with its dimnames named by what the dialog's rows and columns stand for and R's chi-square against the engine's, a record without a recipe, malformed requests, the normal distribution's tails; that `Content/R` holds the pinned engine's 134 recipes and 142-operation manifest unchanged beside `session.R` and `data-files.R`, and that every setting and kind of data a recipe takes is what its operation asks for (Windows's `CheckRecipes`). Then the recipes against the help (Windows's `Recipes.cs`): for each of the 142 operations the record a run on the help's example would leave (`Tests/RScriptExamples`, the same files as Windows's `tests/RScript/examples`) goes through `statsdirect_r_script`, the text is compared line by line with an independent Python rendering of `RScriptWriter.cs`'s rules (head, column lines with by-name and list bindings, matrix, table with dimnames, settings, body; numbers in C# round-trip form), run in R and its figures compared with the help's own script: 142 of 142 agree. The same example inputs are then run through the engine as entered frames (139 operations; the three follow-ons start from a parent result): 120 leave a record at their report step (the 18 random number generators and the worksheet-only summary have no report step, and the quick summary reports through its builtin, so those leave none, as on Windows), each checked against the definition (entered columns with the example's values, the settings as proportions, a typed 2 by 2 with its counts and what its rows and columns stand for, scalar results), its script rendered by the engine and compared line by line with the writer's rules (120 of 120), run in R and compared with the help: 113 of 120 agree, the seven differences being the dialog's rather than the writer's (`Crosstabs`'s recipe takes `ci`, asked only with Monte Carlo; the Mac's rank correlation calculators have no statistic box; `LogRank`'s group identifier is recorded as text labels; `MiscRelRisk`'s help labels carry digits; `SizePaired`/`SizeUnPaired` write `sd` back as a result) and listed in the test so a change in either direction is noticed. The 15 inverse records of the Distributions calculator (`Inverse.cs`) print figures the help's scripts print. The native report-export suite (`Scripts/test-report-export.sh`, also run by `Tests/run_beta_feedback.py`) runs real TPaired and Chi2by2 engine sessions, takes the record and recipe flag from their output and carries the entries through the pane, HTML (with the metadata block), PDF, DOCX, the clipboard and reopening; its new `runRecords` stage drives the real TPaired form on the example workbook's Parametric sheet (the record's source file, path, sheet, columns 1 and 2, rows [1, 10], each hash the SHA-256 of the grid's texts; `data-r="recipe"`), Continue in R opening the pane with the script headed `# Paired Student t test, from StatsDirect, `, a 2 × 2,600 worksheet typed in and run over the threshold (read back from the open grid with no NOTE, exactly one NOTE for the one column edited through `setCellText`, none after undo), Save As through `saveExcel(_:to:)` (the Document, its path, the grid's name and the next record's `source.modified`), the closed grid (the saved file read through the engine with its snapshots cleaned up; the unsaved record and a record pointing at `/no/such/renamed.xlsx` reported as not found with the Windows status line), the context and R menus for results with and without a recipe, and `Tests/Fixtures/Reports/windows-report.html` (the Windows shape: `helpContextId`, no `helpPath`) reopening with its valid record kept verbatim and Continue in R working from its kept values, the invalid record (version 2, a 17-character hash, column 0) dropped with an import note; records refused for a control character in a title, a key, a column title, a value or a file name, or for a run or modification time that is not a timestamp (timestamps with and without a fraction, in Z or with an offset accepted), and a live record with a line feed in its title refused Continue in R with the status line; a record pointing at 500 whole columns (and five frames of one whole column, the fifth past the bound) left unread with the reason and its script still opening; and `Tests/Fixtures/Excel/formula-column.xlsx` (2,600 rows, column y formulas with saved results, written by `Tests/make-formula-workbook.py`) run through the form, read back from the open grid, saved in place through the streaming patcher (its worksheet extension routes it there, as Excel for Mac's workbooks are), the grid closed and Continue in R reporting the file unreadable because its formula cells have no saved results, with no NOTE. The export stage checks that each result's `html` in the metadata block equals its exported block's inner markup with the presentation resolved. `Tests/test_distribution_menu.py` checks, for each of its 1,133 completed calculator cases, that the record holds exactly the boxes the Windows calculator records for that distribution, each within one unit of the last place the box shows of the mirrored rounding (5,519 boxes); `Tests/test_run_record.py`'s real runs of the rank correlation calculators now print the help's figures, since the score is recorded as `df2`. Windows's `Stop` check (`RController.RunScriptCapturingOutput`) has no Mac counterpart; the RPane's stop is covered by `Tests/r-pane-driver.swift`. The engine submodule is at Windows main `b46f5f04` (the writer's by-name bindings for the 142 recipes; the LOESS chart square since `40dd1e1d`), the published engine rebuilt from it with the 1,552 distribution regression checks passing.

# One editable report region — 11 October 2026

On Iain's instruction (relayed by the Windows session, which shares the editor): the report is one contenteditable region with results as identified blocks (`article.report-entry[data-result-id]`, with `data-help` and `data-r` for the host's menus); no help, width, Fit or notes controls sit in the report; the selection, formatting, deletion, clipboard and drag cross result boundaries; Clear formatting clears the paragraph at a caret or every block a selection touches, keeping headings and passing over charts; the toolbar shows a chart's width and Fit while one is selected and the Mac's context menu offers Method Help, Continue in R, Select Result, Select All Results, Fit Chart to Width and Chart Width…. Edits are attributed to blocks by comparing each block with its last reported markup; content WebKit lifts out of a block or splits off returns to its block (`Report/editor.mjs` absorbStrays). The editor also carries the hooks the Windows host needs (`extend`, `reveal`, `selectResult`, `selectAll`, `contextTarget`, `clampSelection`, `start({post})`, platform key labels), and the Office clipboard no longer adds line breaks after a picture. Verified by the native report suite (`Scripts/test-report-export.sh`): the new `singleRegion` checks plus the existing editing, sizing (now through the toolbar and the context menu's commands), transfer, deletion (earlier notes carried into the result), legacy, semantic-container, stylesheet and presentation checks.

# R charts as SVG — 10 October 2026

On Iain's decision that every chart in a report is a vector picture, the engine (Windows main `41518ad6`) draws its R charts with R's svg device and carries them as `ReportVectorPicture`, inlined by the HTML renderer. The Mac pins that commit (867 files). Its R host substitutes the svglite package for R's svg device, since CRAN's R for the Mac needs XQuartz for its own, and its copy of the results parser reads the .svg file by the same rules as Windows (markup from the svg element on; size from width and height in points, or the viewBox; either quote style). `Tests/test_r_operations.py` checks the LOESS chart arrives inline at 432 by 288 points with its points, fit and band; the native report-export driver carries it through the pane, HTML, PDF, DOCX and the clipboard, and the Word-package check finds it at 576 by 384 beside the resized engine chart.

# Engine 5.1.0 — 10 October 2026

The engine submodule moves to Windows main `44203cc8` (StatsDirect 5.1.0: HTML reports with WebView2 editing, dockable help and the calculator on Windows; the RTF and EMF renderers removed). The Mac now uses the engine's `ReportPicture` for R charts and shows the R script as text, as Windows does, so `ReportFragments.cs` and the Mac copy of `Nonparametric.cs` are gone; the manifest records 866 files. The chart's size in the report comes from the PNG's recorded resolution. Build, `test.sh` and the native WebKit driver suite pass on this build.

# LOESS curve fitting through R on the Mac — 9 October 2026

The engine's R script steps now run on the Mac: `FullEngine/RController.cs` finds Rscript, runs each operation's script in its own folder under Application Support, shims the Windows metafile device to R's quartz PNG device and returns the chart and the script to the HTML report as fragments (`ReportFragments.cs`). LOESS curve fitting is enabled in the analysis menu; method comparison regression stays deferred until its `mcr` package path is verified. `Tests/test_r_operations.py` (in `test.sh`) checks the help example's four printed figures and the fits and standard errors written back against R called directly on the same data, rows with missing values, two predictors, an error inside R, R not installed and cancelling while R runs. The help replay baseline includes the LOESS page; the menu test counts 207 input hosts and one R deferral.

# Advanced Excel structural edits — 9 October 2026

See [0.3.24 validation](../Docs/Validation/Beta-0.3.24/README.md) for feature coverage, Excel checks and the remaining genuine structural constraints. This replaces the earlier blanket exclusions for tables, merges, pivots, slicers, controls and worksheet extensions.

# Extended Mac validation — 9 October 2026

See [0.3.23 validation](../Docs/Validation/Beta-0.3.23/README.md) for the latest checks, host fixes, native Office results, fresh-profile boundaries and remaining limits. The historical entries below describe earlier builds.

# Two-dimensional grouping and tutor privacy — 8 October 2026

Integrated GitHub main `871e6ee` and independently checked nested and replicated two-way
ANOVA in long and wide layouts. Found a valid nested design rejected when parent groups
had distinct subgroup labels: global subgroup positions introduced null holes. The Mac
host now compacts subgroups within each parent. Nested ANOVA and its means follow-on match
the wide-layout reports, including this case. R snapshots preserve numeric-looking group
labels as text, and entered/lesson data can return to separate-column layout without
filling a throwaway table. No upstream engine source or submodule pin changed.

Tutor safeguards now implemented:

- Every Learning window starts in Lessons only, ignoring old sharing preferences.
- Choosing one document limits access to that document; all-open-document sharing is explicit.
- A native, unchecked confirmation is required for each question using document context,
  before names, headings or contents can be sent. It lists the documents and asks the learner
  to confirm they contain no person identifiers. Cancellation sends nothing; Lessons Only
  continues without new document context.
- Confirmation, timestamp, question ID, statement and document revisions are written to the
  local learning record before access is granted, and retained in review/export formats.
  Unavailable record storage prevents access. Closed/new documents and changed worksheets
  cannot silently enter the confirmed scope.
- Likely identifier headings are withheld from metadata and their columns cannot be read,
  including reads beyond the 128-column metadata preview. This is a conservative backstop,
  not anonymisation; previously shared conversation content is not removed by Lessons only.
- `DisableOnlineTutor` prevents connection startup, sign-in, questions and tool access. A
  detected policy change stops an active connection/reply. Local learning and practice remain
  available. See [deployment and limits](../Docs/Learn/TutorPrivacy.md); an enforced deployment
  requires forced macOS managed preferences, not an ordinary user-editable defaults entry.

Verification: `./build.sh` (including 1,552 distribution checks), the complete `./test.sh`
engine/R regression suite, all 82 JavaScript tests, Swift application compilation with
`-warnings-as-errors`, local mock tutor protocol tests, and the policy startup/in-flight
cancellation test passed. The native WKWebView suite passed confirmation and record tests,
fail-closed checks, offline UI under policy, provider-course requests with no document
metadata in lessons-only mode, nested grouping/fallback/R labels, report exports and clipboard,
10,000 × 10 worksheet paste, 1,048,576-row entered summary, and 500,001 × 2 prefill.

No live AI requests, Keychain authentication, email or release publication were part of
these checks. Engine remains 5.0.14 (`b10edfefa54b`). The local app is rebuilt; a new
versioned installer has not been published. Grouped-covariance identifier input, Apple
Developer ID signing/notarisation and CI remain separate outstanding work. Heading checks
and self-confirmation do not establish institutional approval for patient-level data.

Focused checks: `python3 Tests/run_beta_feedback.py --privacy-only` and `--groups-only`.
Run the standalone policy fixture with:

```sh
swiftc -warnings-as-errors Sources/ChatGPTTutor.swift Tests/tutor-policy-driver.swift -o .build/tutor-policy-test
.build/tutor-policy-test
```

# Groups by identifier handover — 8 October 2026

Incorporated `ab9a6c1` from GitHub main (handover 2), retaining the typed entry tables and
Excel actor-isolation fix. Independent checks found and fixed four integration defects:

- Balanced treatment/block totals could conceal duplicate combinations. Two-way ANOVA and
  Friedman then overwrote observations and analysed only the surviving complete blocks.
  The Mac host now rejects duplicate combinations, including explicitly missing observations.
  The pinned Windows selection code uses the same assignment pattern; the upstream core
  remains unchanged and this validation is in the Mac host.
- The first layout switch could save only `selectGroupsByIdentifier`, causing subsequent
  analyses to fail on missing preference keys. Saved keys now overlay the existing defaults;
  the default CI remains 95% and complete Analysis Options forms are still validated.
- Rejecting a long-data answer reset a custom row range to the worksheet selection. A native
  reproduction changed rows 2–5 to 1–12. Retries now retain the submitted range.
- Declining the unequal-group warning replaced the saved data answer with a Boolean. Answers
  are now restored by parameter, preserving the original roles and range for correction.

The complete engine/R regression suite and all 79 JavaScript tests passed. Native WKWebView
checks cover role selection, rejected and corrected ranges, first-use preference persistence,
ANOVA history and its R script, and declining the unequal-group warning. The existing native
workbook, tutor (mock), report/export, clipboard and million-row entry tests also passed.
`./build.sh`, 1,552 distribution checks, Swift with `-warnings-as-errors`, and the rebuilt
app's deep, strict local signature check passed. Engine pin: 5.0.14, `b10edfefa54b`.
Run `python3 Tests/run_beta_feedback.py --groups-only` for the focused native checks.

Remaining handover items: long-format acquisition for two-dimensional and grouped covariance
frames; tutor-sharing controls and recorded consent; institution-level tutor policy; Apple
Developer signing/notarisation and release CI. The existing tutor already explains what Send
shares, says “Avoid identifiers”, and offers “Lessons only”; it does not record the proposed
per-worksheet confirmation. Account-side contractual, training and residency claims in the
handover are not established by inspecting this code. No tutor-sharing policy, upstream
calculation source or published installer version changed in this integration.

# Embedded entry tables and Excel host — 8 October 2026

The general analysis entry forms now use the typed worksheet store, without a one-million-cell
limit. Large selected rectangles load through the existing column bridge when the form needs
them. Excel dimensions and method-specific restrictions remain; the separate exact r × c
prototype retains its existing 2,500-cell restriction. The calculation engine remains 5.0.14.

Verified locally:

- Full engine/R regression suite, all 77 JavaScript tests and the selected 2 × 2 table → engine
  comparison against R passed. Entry tests include 1,048,576 × 2 populated cells, 16,384 columns,
  exact quoted text, blank-column removal, and overflow rejection without partial writes.
- Native WKWebView integration pasted 1,048,576 alternating 1/3 observations into the actual
  univariate summary form: n = 1,048,576, mean = 2, sum = 2,097,152. A highlighted 500,001 × 2
  rectangle also prefilled through the application bridge. Existing workbook, tutor, report,
  export and clipboard checks passed using the mock tutor.
- The Excel queue's stateless FFI helper is explicitly nonisolated. Swift compilation with
  `-warnings-as-errors`, the complete app rebuild (including 1,552 distribution checks),
  and deep, strict local signature verification passed.

The rebuilt local app contains these changes. This verification does not create a new release
or change the published installer version.

# Mac beta feedback fixes — 6 October 2026

Local build 0.3.17 includes the enriched learning library and fixes described in [the feedback validation record](../Docs/Validation/Beta-0.3.17/README.md). The full engine/R regression suite and 63 JavaScript tests passed. Native checks verified options, course flows, safe Markdown/math/R rendering, per-lesson conversations, report editing, clipboard tables and all learning/report export formats. A live ChatGPT session read nine PEFR pairs from the native worksheet, ran the unchanged engine, produced an SVG agreement chart and streamed the correct result with equivalent R.

The engine remains pinned to 5.0.14. The .NET build path passed; Docker scripts were syntax checked but Docker is unavailable on this Mac. No assessment email was sent. This entry describes local verification, not a published GitHub release.

# Simplified Learning Options — 1 October 2026

Mac 0.3.16 uses two main form sections, adds statistical skill level and assessment type, groups course-pack controls with the training provider, and removes the learner web-resource list. Optional preferences and provider conditions remain expandable. Existing records, custom recipients and immutable submissions are retained. The default assessment email is support@statisticalhelp.org.

All 19 learning tests, the native provider/tutor-context workflow and Swift compatibility checks passed. Native visual inspection confirmed the new layout and CPD selector. Retired web caches are preserved but excluded from new tutor requests. No live AI assessment or email submission was made. The extracted release is locally signed and retains byte-identical core 5.0.14 engine files; numerical suites were not repeated. See [validation](../Docs/Validation/Learning-0.3.16/README.md).

# Provider courses and learning resources — 30 September 2026

Mac 0.3.15 adds a configurable learning URL list, provider course packs, practical submissions, report/R text evidence, provider-addressed review drafts and returned assessment records. The six starter links cover OpenLearn, CDC, Penn State, OpenIntro and Hernán/Robins. A three-lesson provider example and author/response templates are included. See the [feature validation](../Docs/Validation/Learning-0.3.15/README.md) and [author guide](../Docs/Learn/CoursePack/README.md).

Seventeen learning tests, native resource/parser tests, real downloads of all six pages and both linked PDFs, provider WKWebView integration, existing workspace integration and the normal engine build checks passed. The native tutor request was verified with a local protocol fixture; no live AI reply or assessment email was sent. Native UI inspection confirmed the source list, and the packaged app successfully loaded all six pages. The engine stays at 5.0.14.

The release ZIP contains the verified 0.3.15 bundle, with matching tested executable, engine and content. Deep, strict local signature verification passed after extraction. ZIP size: 153759575 bytes; SHA-256: `2e24566a89bb8b8d8ffadc9d412591ce553dd3bc77e1efda8b605cdb171521c5`. This remains an ad-hoc-signed, non-notarised Apple Silicon beta. Provider review, not StatsDirect, determines any CPD award.

# Published Mac update — 26 September 2026

Published [v0.3.10](https://github.com/iain-buchan/statsdirect-mac/releases/tag/v0.3.10), targeting commit `36bc277e5b9f0500e859e83ef7c3c5fa12f68c3f`, with the Apple Silicon application ZIP and SHA256SUMS.txt. Both assets were uploaded and verified before the draft was made public and latest. The ZIP is 153,314,538 bytes; SHA-256 `7484d55956fc7b8cda5d3f63abaf28339e221ee404ec1571a2db3f3e5739cd48`, also confirmed by GitHub asset metadata. Archive integrity and the extracted app’s deep, strict local signature verification passed. The release notes identify its ad-hoc signing/notarisation limitation and manual installation.

The real public update endpoint and website latest-release redirect both resolve to v0.3.10. Existing update-service tests passed. An isolated copy of the actual 0.3.9 app displayed “StatsDirect v0.3.10 is available” both automatically and when selecting Help → Check for Updates; its dialog correctly stated “You are using 0.3.9.” No updater code change was required: prior source pushes had not created a GitHub release.

# Example workbook menu — 26 September 2026

Mac build 0.3.10 replaces Help → Examples → StatsDirect Example Workbook with the direct Help → Example workbook command. Native UI verification in an isolated app confirmed the shortened entry and that selecting it opens test.xlsx with all 11 worksheets. The shared menu definition also supplies the macOS menu bar. Swift compilation and deep, strict signature verification passed for both packaged app paths. The calculation engine and workbook are unchanged.

# Teaching content audit — 26 September 2026

Mac build 0.3.9 incorporates the [educational-content audit](../Docs/Learn/CONTENT-AUDIT-2026-09-26.md): all seven lessons, 30 fixed questions, both tutor policies, the sample course pack, archived teaching content and R handoff explanations. Fourteen question wordings were revised; all answer keys remain unchanged.

The 16 learning/history/archive tests passed, including seven executed R examples and plots, independent numerical choices, preserved historical scoring and correct lesson attribution. All seven lesson workflows were exercised through the unchanged engine. All 37 generated-R operation fixtures and the existing data/setting handoff cases passed. Swift compilation, 0.3.9 packaging and strict local signature verification passed. Native UI checks in an isolated app confirmed the paired question and risk/NNT corrections without replacing the user’s open documents. The 5.0.8 engine binary is unchanged.

# Windows 5.0.8 core validation and Mac integration — 25 September 2026

The accepted core is `dcc2af8f0ec55d736a98acac029297510195e2df` (5.0.8). Before accepting it, the unchanged Windows numerical files were compiled independently of the Mac host and compared with 5.0.7 and R 4.6.1. The candidate completed 4,902 cases without a fault or timeout. All 322 candidate/R discrepancies passed independent high-precision checks under the documented tolerances; ten representative cases were repeated at 100 digits. The 400 ordinary seeded cases agree with R in both versions. Full inputs, raw outputs, source hashes, criteria and limitations are retained in the [numerical audit](../Docs/Validation/Core-5.0.8/README.md).

The Mac build imports all five new beta/special-function source files without modifying numerical algorithms. It verifies 879 source/asset hashes. The Mac distribution forms now request both tails directly from the new APIs; their old subtraction lost a t lower tail of 5e-41 as zero. Windows-only installer changes remain outside the Mac host. Existing platform copies, operation definitions, menus, workbook and imported help did not change in this core revision.

Validation passed:

- The upstream distribution suite: 1,552 checks, now included in normal builds.
- Original operation fixtures; paired analysis and SVG agreement geometry; all 224 menu commands and 206 enabled entry points; 47 analysis/calculator and 74 Data/Graphics cases; 14 R comparisons.
- Six interleaved forms, cancellation/validation and the complete saved-confidence/defaults suite.
- Existing normality/extreme-scale checks, plus new tiny t/F/chi-square tails, seven worksheet expressions using the updated SDMath functions, and the corrected 99.8% rate-ratio interval through the real report path. Reference calculations use stable R identities/forward-tail inversion where direct R quantiles are inaccurate.
- Dedicated chi-square tests, including independent R calculations, simulation and cancellation; all generated R-script checks and numerical comparisons.
- Full Swift build and package; strict local code-signature verification; packaged engine DLL and version metadata match the tested build byte-for-byte.
- Native About displays **StatsDirect 5.0.8**. Selecting Student's t from the menu opens its input form immediately. Entering t = −1e20 and 2 df produces a separate report showing lower tail `4.99999999999998E-41` and two-sided P `9.99999999999996E-41`, with the 5.0.8 footer and help/R links.

This remains a locally signed development build. The earlier help-suite and unsupported R-operation limitations below are unchanged; this does not certify every statistical procedure or Windows UI feature.

# Upstream refresh — 25 September 2026

The Mac build now uses Windows StatsDirect **5.0.7**, pinned to `c956b122c9b77683f58c4d10c221390183968cd3`, and statisticalhelp `d02543897aac61eb0a98e2c708628655c9e48072`. All 874 recorded engine source/asset hashes and 978 imported help-file hashes were verified. The bundled example workbook is byte-identical to the upstream workbook. The menu/help catalogue was regenerated; corrected operation titles are included.

The two changed Mac platform copies were reconciled with upstream: permutation-count formatting in Nonparametric and the zero-range axis message. The Mac distribution host also adopts the Windows normal-tail fix and the Kendall minimum of two observations. Numerical algorithms remain in the pinned upstream engine. About and report footers now read the imported version metadata.

Checks completed successfully:

- Full engine build and the original two populated operation tests (26 expected outputs; one empty test skipped).
- All 224 menu commands, 208 help links and 206 enabled input hosts; the two pre-existing R-dependent deferrals remain explicit.
- 47 completed analysis/calculator cases, 74 Data/Graphics cases and 14 independent R numerical comparisons.
- Paired-test output, original SVG agreement geometry, dedicated chi-square calculations against R, custom scores, seeded simulation, validation and cancellation.
- Six interleaved forms and the complete Analysis Options/default-confidence suite.
- New 5.0.7 regression checks: normality statistics under scaling by 1e300 and 1e-300 and translation by 1e12; Shapiro-Wilk against R; constant/two-value sample messages; tiny normal/F/Poisson tails against R; signed Kendall tau and the minimum sample size.
- All Mac-generated R-script checks and engine comparisons.
- Updated workbook round trip: 11 sheets, 14,363 populated cells, 22 formulas, cached results, types and styles; formula-input recalculation and invalid-file handling.
- Swift compilation; native About shows 5.0.7; the bundled workbook opens; the paired example runs with automatic 95% confidence and produces the expected report and SVG agreement chart. Its help link opens the refreshed offline topic, and the new R-code section expands correctly.
- Final app packaged with the rebuilt engine and content, verified byte-for-byte against the source build; local ad-hoc code signing and strict signature verification passed. This is still a development build, not a notarized installer.

The help repository's separate `RCode/check-rcode.R` suite passed **132 of 135** examples on the installed R. Three upstream reference checks remain unresolved; the imported help was kept unchanged:

- `agreement/mcr`: the optional `mcr` package is not installed, so this script could not run.
- `basic_descriptive_statistics/univariate_summary`: R prints the sum as `29985.239999999991`, while the literal expected fragment is `29985.24`.
- `regression_and_correlation/multiple_linear`: the Longley intercept and year coefficient differ in the final printed digit (`-3482258.63459583` versus `-3482258.63459582`, and `1829.15146461356` versus `1829.15146461355`).

At extreme numeric scales or very large offsets, normality statistics complete correctly but the existing chart axis renderer can report that the chart cannot be drawn. These tests do not claim complete Windows UI parity or coverage of every statistical procedure. The active user session was preserved; reopening the packaged app loads the updated engine.

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

## Analysis defaults and selected R data — 24 September 2026

Analysis → Options presents all six original Windows analysis defaults on one form, with group-identifier selection explicitly disabled until supported. The initial confidence level remains **95%**. A saved default is used without another prompt only when the original confidence parameter permits defaulting. Native UserDefaults persists the settings; each new analysis captures its own settings so open analyses cannot change underneath the user. Saving options creates no results report.

`test_analysis_defaults.py` passes: all six fields match the Windows XML; invalid/cancelled changes are atomic; an alternative saved 90% level is applied and recorded automatically while an already-open 95% analysis is unchanged; turning defaulting off restores the prompt; non-defaultable confidence still prompts; and restored native settings work in a fresh engine process. The original 121 analysis/data/graphics cases, 14 R comparisons and six interleaved-form checks also pass. There are now 26 passing grid tests. All 38 mapped R scripts pass, including selected-block and missing-cell alignment checks.

Native UI verification used a separate app identifier. Saved standard defaults (95%, statistics 6 decimals, P values 4 decimals) were present in its preferences after quitting. After restarting, a worksheet with four pairs alongside a 100-observation unrelated column selected only rows 2–5 for the pair. Continue went directly to Agreement analysis without a confidence form. The report showed n = 4, a 95% CI of 0.290019 to 8.709981 and two-sided P = 0.0424. Continue in R produced only the two four-value columns and ran successfully, matching the confidence interval and P value. Missing rows remain aligned; the input history references the data instead of duplicating it.


## Options layout and reusable tab numbers — 24 September 2026

The native app now chooses analysis titles from currently open forms instead of a lifetime counter. Verified in the packaged viewer: open Analysis options and Analysis options · 2; close · 2; reopen and obtain · 2 again; close both and reopen to obtain the unnumbered Analysis options. Existing open tab names stay unchanged.

Analysis Options uses one scrollable body for all six defaults, with Save defaults and Cancel in a fixed action bar. Saving does not display an input-step history. In the packaged app, all six fields appeared together at 95%, one Save action completed successfully, and Edit defaults restored all six saved values. The generated web bundle was also checked at an 850 × 412 content viewport: scrolling reached the final P-value option while both action buttons stayed visible. No numerical engine changes. The native build, 26 grid checks, defaults integration tests and app signature verification passed.


## Report footer and inline R plots — 24 September 2026

Continue in R is a small link beside method help below the analysis results, in both general operation reports and the dedicated contingency-table report. Mapping scope remains in the tooltip and generated script comments. Native verification used the bundled test.xlsx PEFR example: the footer link opened and ran the paired/95% agreement script and its agreement.pdf appeared as an image in the R output.

The R session bootstrap now supplies a headless PDF device for ordinary plotting and flushes graphics devices opened by each submitted script, even after errors. The native output embeds every page of new/updated PDFs and supported bitmap files in the session directory. Images fit the output pane, with links to the original files, and unchanged plots are not duplicated on text-only runs. The initial editor/output split leaves room for charts. A final native check ran a plain plot call without an explicit device and visually confirmed the complete chart, title and axes in the output pane.

`Tests/r-pane-driver.swift` runs the actual persistent RPane host: two default plots in one run, multiple explicitly closed/reopened devices, an error after plotting, persistent variables, the generated paired agreement recipe, replacement of agreement.pdf on a second run, no duplicate plots on text-only runs, and narrow-column attachment sizing. All checks passed. Compile Sources/RPane.swift, Sources/DocumentToolbar.swift, Sources/RScriptGenerator.swift and this driver with Cocoa and PDFKit; pass the absolute Content directory to the executable. The complete Swift app compiles and the packaged app passes strict signature verification.

## Learning, tutor course packs and original Windows symbol — 25 September 2026

Version 0.3.0 adds a closable Learning document, full scrolling Learning Options, five learner pathways, seven worked lessons and 30 original draft questions. Every pathway includes epidemiology and causal inference. Exam sources and access limitations are recorded in `Docs/Learn/EXAM-SOURCES.md`. Tutor packs accept searchable PDF, UTF-8 text/Markdown and schema-checked JSON; relevant excerpts are selected locally for the OpenAI request. The original Windows icon supplies the app, About and learning artwork. No upstream engine files or submodule revision changed.

Six JavaScript tests pass, covering question/help/operation mappings, withheld independent-practice keys, first-answer scoring and assistance, record export and reopen, malformed nested records, frozen question versions, saved learning goals, and all seven bundled R examples with plots. The Swift learning-client checks pass for the fixed API endpoint, credentials excluded from the request body, `store:false`, role filtering, response extraction, incomplete responses, six HTTP error cases, and course-pack validation/retrieval/persistence. `test_learning_examples.py` runs the exact paired, descriptive and regression fixtures through the real engine; the paired fixture agrees with R (mean difference 5.25, t 5.3712631000277415, df 7, two-sided P 0.0010400979673, 95% CI 2.93876015–7.56123985).

The complete engine build and regression suite passed, including 1,552 upstream tests and the existing Mac host/default/R comparisons. The final native app compiles and passes strict ad-hoc signature verification. Native UI checks verified Learning/Options menus, secure API-key entry (cancelled without a key), JSON course-pack import, the paired analysis form with exactly eight selected fictional rows, and its bundled R script producing text output and an embedded plot. Browser checks verified saved goal restoration, supported-practice hints and feedback, first-answer locking, independent-practice tutor restrictions, and reopening saved attempts.

Live OpenAI conversation and teaching quality remain untested because no API key was provided. Email attachment preparation is implemented with macOS sharing; no email was sent and external delivery/review/accreditation is not claimed. Pack retrieval is a bounded keyword search, not model fine-tuning or an exhaustive course-content guarantee.

## Managed tutor without learner API keys — 25 September 2026

Version 0.3.1 removes provider-key and model entry from the Mac. The publisher supplies a public HTTPS service address, and the native host automatically obtains a limited service session on the first question. Its token stays in service-scoped Keychain storage; an expired token is renewed once transparently. The server owns the OpenAI credential, model and teaching policy. Until a service is deployed, the learning window explicitly shows that activation is pending. Existing course packs, learning records, practice and engine/R examples remain available.

The new ASP.NET Core 10 service builds and publishes without warnings or third-party packages. Six HTTP integration tests pass against a loopback synthetic provider: automatic sessions and server-owned credentials/instructions; rejected schema/authentication/model overrides; persistent daily quotas across restart and spoofed forwarding; registration caps, revocation and safe provider errors; missing administrator credential; and production HTTPS enforcement. The service reserves allowances durably before paid requests and retains only token/address hashes, expiry and counters. Deployment is limited to one instance with persistent private storage; anonymous sessions do not verify learner identity or provide university SSO.

Swift checks pass for HTTPS-only configuration, session parsing, bounded context, credential separation and safe errors. `Tests/managed-tutor-driver.swift` exercises the **same asynchronous function used by the Mac host** against the real local service: automatic session creation, saving its token, receiving an answer and replacing an expired token without learner input. All six learning/quiz/R tests still pass. The complete native app compiles; the packaged 0.3.1 build passes strict ad-hoc signature verification. On-screen verification was blocked by the Mac being locked. No live OpenAI calls, public deployment, provider charges or email submissions occurred. Hosting and one administrator-managed provider credential remain necessary for live shared conversation.

## Selected tables, instant results, active reports and update checks — 26 September 2026

Version 0.3.2 copies compatible highlighted worksheet rectangles into screen-entry grids, including chi-square 2×2 and R×C. Position, zero and missing-cell handling are covered; oversized/mismatched selections are not cropped, unsafe formula caches and Excel errors are rejected, and edited/rejected answers override the original snapshot. All 30 grid tests pass, TypeScript checks pass, and the full native app compiles. `test_selected_table.py` sends the real grid helper's C5:D6 payload through the original Chi2by2 engine and compares the statistic/P value with base R. It also verifies the instant-method flag against every Windows operation definition. The calculation engine and its pinned commit are unchanged.

The 45 self-suggesting Windows operations use instant-result previews; the dedicated R×C screen follows the same workflow. Completed results appear above retained data/parameters, with Recalculate and Add to report. Edited inputs are replayed through the engine's normal validation; newly applicable questions still prompt. Ordinary results append automatically to the active report. File → New Report is the explicit way to start a separate report, and selecting a generated report changes the destination. Each saved result owns its immutable R script and help links; repeat Add messages cannot duplicate the same snapshot. Full report PDF/Print include accumulated results.

Native verification in an isolated app: paste [12,3;8,17] into a blank sheet, highlight exactly A1:B2, choose Analysis → Chi-square Tests → 2 by 2, and see all four counts prefilled. The completed form displays chi-square 8.64 without creating a report tab. Add to report creates Report 1. Editing the first count to −1 and recalculating invokes the original validation and retains the rejected value; correcting it to 13 resumes the remaining parameters automatically and yields 9.471244. Adding this result appends to Report 1 while preserving the earlier 8.64 result. The earlier result's Continue in R link opens its original [12,3;8,17] snapshot, not the edited counts. A paired test also appends automatically to Report 1. Creating Report 2 explicitly and keeping a selected-cell R×C calculation adds it to Report 2. The synthetic test app was then closed.

Help offers Check for Updates and an initially enabled automatic-check toggle. Automatic checks occur at most once daily, including during a long-running app session, and notify once per newer stable version. View Update opens the repository release/download page; installation remains manual. `update-service-test.swift` passes numeric version ordering, same/older releases, absent releases, draft/prerelease exclusion, HTTP failures, malformed responses and trusted GitHub release URLs. Both the real endpoint and the native menu reported no published release correctly. No release has been published as part of this change. Both packaged application paths pass deep, strict ad-hoc signature verification.

## 2026-09-26 — 0.3.3: Use my ChatGPT

- Built the native Mac shell successfully; the Windows calculation engine is unchanged.
- Bundled OpenAI Codex App Server 0.157.1 from its official Apple-silicon release. Archive SHA-256 verified (`9a6033c9fe30260e71d784d003ad1e2de2a55c93e24a24856e8433029a3f811a`). The build script pins this artifact, includes upstream licence/notice and signs nested executables.
- Real runtime probes passed initialization, signed-out account state, browser login URL creation, login cancellation, ephemeral thread creation with no selected environment, turn validation, interruption and unsubscribe. No existing Codex credentials were used and no live model answer was requested with a signed-in account.
- Swift protocol fixture passed completed OAuth notification/account refresh, split JSON frames, unrelated-thread rejection, bounded/role-filtered context, successful answer delivery, safe usage-limit errors, cancellation before the turn-start response, subsequent reply, logout, child-process disconnection and restart. Synthetic inherited API keys/server overrides were excluded from the child environment.
- All six existing Learning tests passed, including independent practice, 30-question bank validation, learner-option persistence and executable R examples. Native managed-service/core course-pack tests also passed.
- Native UI verified with a separate bundle ID and portfolio: **Use my ChatGPT** in Learning, no API-key field, browser opened to OpenAI's sign-in page, pending/reopen/cancel controls, and a complete draft preserved across a connection check. Status changes now update their own elements rather than rebuilding the learner's form. Temporary sign-in cancelled and its browser page closed; test app quit.
- `StatsDirect 0.3.3.app` and canonical `StatsDirect Viewer.app` passed deep/strict signature verification. These are ad-hoc signed prototypes, not notarised distribution builds.
- Remaining: learner completes browser login to verify a live teaching response and account-specific access/limits. The existing 0.3.2 session was not closed by this work. After it was no longer running, the finished 0.3.3 build was opened to Learning.

## 2026-09-26 — 0.3.4: Tutor application context and engine tools

- Built the native Mac shell and both web bundles. The bundled Windows engine is byte-for-byte identical to 0.3.3 (`dcc2af8f0ec5`, version 5.0.8); no statistical routines were changed.
- 28 Learning, worksheet extraction, operation-data and workbook tests pass. Coverage includes exact rectangles/column order, nine PEFR pairs without blank sheet padding, internal missing positions, hidden/oversized data rejection, formula/error flags, portfolio provenance, independent practice and executable lesson R examples.
- The actual engine ran all ten direct tutor methods through `TutorTools.run`: paired/unpaired t, univariate/quick summaries, chi-square 2×2, Fisher, Wilcoxon signed ranks, Spearman, agreement and normality. The host preserves row positions and requires an explicit chi-square study design; it refuses an oversized screen table rather than cropping it.
- The nine-pair example gives mean before-minus-after 56.111111, 95% CI 29.842662–82.379560 and two-sided P 0.001155573. Its generated R script has nine rows and agrees with engine mean/CI/P to the test tolerances (1e-10 / 1e-9 / 1e-12). The engine report contains an SVG agreement chart. With the third before value missing, the native helper retains row alignment: n=8, mean=49.625 and eight plotted points.
- Swift protocol tests pass tool round-trip JSON, registered-tool restrictions, wrong-thread/turn rejection, duplicate call suppression and cancellation of a running tool, alongside the existing login, answer, usage-limit, retry and disconnect checks. The pinned real App Server 0.157.1 accepts the dynamic tool definition with no selected computer environment; the probe remained signed out.
- `Scripts/test-learning-workspace.sh` compiled a separate native test app with its own bundle ID and portfolio. It opened the real bundled test.xlsx through the Excel host, located the PEFR columns, read their nine pairs from WKWebView, ran the engine, appended one report with SVG/R link, and verified repeat-result reuse. It also verified stale worksheet rejection, per-question document scope, cancellation, Lessons only, bundled help, actual rendered report reading, R script/output reading and draft preservation through context/account updates.
- Native UI checked the context choices and Lessons-only status; the typed draft remained intact. Tool-source references are escaped in the conversation and exported in the record. The isolated test app was closed.
- `StatsDirect 0.3.4.app` and canonical `StatsDirect Viewer.app` pass deep/strict code-signature verification. Packaged executable UUID matches the new native build. They remain ad-hoc signed prototypes.
- A live model/tool conversation was not sent from the user's signed-in account in this verification. Transport and host integration were exercised separately with the protocol fixture and the real native/engine harness. The user's running 0.3.3 session, including its open analysis form, worksheet and saved learning conversation, was left intact; opening 0.3.4 after closing that session is required to use the new native tools.

Additional reproducible checks:

```sh
node --test Learn/learning.test.mjs Grid/tutor-data.test.mjs Grid/operation-data.test.mjs Grid/workbook.test.mjs
swiftc Sources/ChatGPTTutor.swift Sources/TutorTools.swift Sources/RScriptGenerator.swift Tests/tutor-engine-driver.swift -o .build/tutor-engine-test
.build/tutor-engine-test "$PWD"
Scripts/test-learning-workspace.sh "$PWD/StatsDirect Viewer.app"
```

## 2026-09-26 — 0.3.5: Keep study-guide prompts with their lessons

- Confirmed the clinic-diagnosis question belongs to the epidemiology lesson. The shared conversation previously displayed all lesson prompts with the same generic label, making earlier questions look like part of the currently selected lesson.
- Guide prompts now carry their lesson title; prompts from other lessons or older wording are collapsed as earlier study guides. Exact-text matching labels legacy entries without rewriting or deleting the conversation. Reopening a lesson supplies its current prompt when needed; re-rendering does not duplicate it. Lesson titles are retained in exports and sent with model conversation context.
- The paired lesson explicitly establishes repeated observations on the same people or matched pairs and contrasts these with different unmatched patients in two periods. The teaching instructions likewise require actual pairing before selecting a paired method.
- All ten Learning/lesson-context tests pass, including legacy-record migration, lesson switching, duplicate prevention, draft/history preservation, export attribution and the seven executable R lesson examples.
- Built and verified ad-hoc signatures for 0.3.5 and the canonical app. Engine bytes and native executable UUID are unchanged from 0.3.4. No calculations or runtime protocols changed.
- Opened 0.3.5 after confirming the older window contained only an empty worksheet. In the restored real Learning record, the paired heading and revised prompt are correct, both earlier prompts are collapsed with their original lesson names, ChatGPT remains connected, and the complete prior learner/tutor conversation is retained. No question was sent to the live tutor during this verification.

## 2026-09-26 — 0.3.6: More room for the tutor conversation

- Moved Tutor context out of the chat header into a compact strip at the bottom of the Learning window, retaining the document selector, Refresh and current-source status. Long status text has a tooltip.
- The conversation now fills the available height instead of being capped at 160 pixels. The composer stays visible; lesson notes and the worked example are expandable. Other Learning pages retain their normal scrolling layout and hide the context strip.
- Built the learning bundle and visually checked the native layout in an isolated app with synthetic conversation history and a draft. Visiting Learning options and returning preserved the draft and restored the context strip. The isolated app was closed.
- Opened the finished 0.3.6 application to Learning and verified the bottom strip, expanded conversation area, fully visible composer, collapsed notes and restored real conversation. No live tutor question was sent.
- Both packaged application paths pass deep/strict ad-hoc signature verification. Native executable UUID and calculation-engine bytes are unchanged from 0.3.5; this is a web layout change.

## 2026-09-26 — 0.3.7: Download and install missing R

- Added shared R setup for new sessions, report/learning scripts and RData/RDS open/save. Missing R presents Download and Install R, progress, cancellation and retry. The R menu also exposes setup and recognises an existing installation. Repeated requests share one setup window.
- The package is pinned to official CRAN R 4.6.1 for Apple Silicon/macOS 14+, SHA-256 `67f6eea4ced4ce48f0a0d4fa3a1cac43d1859a05a88993ee3dff7c52e7edbc4b`. The actual URLSession download passed checksum verification, `pkgutil` verification of Developer ID Installer Simon Urbanek (`VZLD955F6P`) and macOS installer assessment. Downloads cannot redirect to another URL, exceed their size bound or open before verification. Cancellation/failure cleans the staging directory.
- Core tests cover runtime discovery, unsuccessful runtime probes, empty/oversized/wrong-checksum files, a matching-checksum unsigned file, changed URLs, HTTP errors and unexpected content lengths. Local HTTP fixtures exercise the real download path for 404, forbidden redirects, oversized/corrupt/unsigned payloads and cancellation; all pass.
- An isolated native UI fixture simulated missing R without removing or reinstalling the existing runtime. Verified download failure/retry, cancellation with script preservation, installer handoff state, rejection of an unfinished installation, and successful resumption of the original script with its plot after R became available. The fixture deliberately does not launch macOS Installer. It was then closed.
- Existing native RPane tests pass persistent variables, default plots, multiple devices, error-after-plot handling, agreement PDF replacement, attachment links and resizing. Real RData/RDS/CSV round trips also pass, including types, missing values, factors, edits, invalid input and atomic-save protection.
- Compiled the full native app; both 0.3.7 and the canonical bundle pass deep/strict ad-hoc signature verification. Calculation-engine bytes are unchanged from 0.3.6. Opened 0.3.7, verified R Is Installed in the menu, and opened a ready R session directly.
- The actual privileged installation on a clean Mac still needs colleague testing. StatsDirect opens the standard macOS Installer; it does not bypass its installation steps, administrator approval or managed-device restrictions. Returning to StatsDirect runs a real Rscript readiness probe before resuming the pending action.

Reproduce core/download and existing-R checks:

```sh
swiftc Sources/RInstallation.swift Tests/r-installation-test.swift -o .build/r-installation-test
.build/r-installation-test --fetch
python3 Tests/test_r_install_download.py .build/r-installation-test
swiftc Sources/RInstallation.swift Sources/RInstaller.swift Sources/DocumentToolbar.swift Sources/RPane.swift Sources/RScriptGenerator.swift Tests/r-pane-driver.swift -o .build/r-pane-test -framework Cocoa -framework PDFKit
.build/r-pane-test "$PWD/Content"
swiftc Sources/RInstallation.swift Sources/RDataFileIO.swift Sources/CSVFileIO.swift Sources/Snapshot.swift Tests/data-file-driver.swift -o .build/data-file-driver
python3 Tests/test_data_files.py .build/data-file-driver /path/to/node
```

`Tests/r-installation-ui.swift` can be compiled with RInstallation, RInstaller and RPane into an isolated app containing `Content/R/session.R`. Its first download fails deliberately; subsequent downloads simulate progress without installing software. Creating `~/Library/Application Support/com.statsdirect.r-setup-ui/ready` after the simulated installer handoff lets Check Again use the existing local R and resume the retained script. Launching the fixture resets only this marker.

## 2026-09-26 — 0.3.8: Update checks when GitHub API DNS fails

- Reproduced the reported error on this Mac: both curl and native URLSession failed to resolve `api.github.com` (NSURLErrorCannotFindHost, -1003). `github.com` resolved and its repository `/releases/latest` address redirected successfully to the release list. No network or DNS settings were changed.
- The checker now falls back from a failed GitHub API request to GitHub's documented latest-release web address. It validates the final HTTPS host, repository path and numeric tag rather than scraping HTML. A successful redirect to the release list reports no published release. An unrelated/login page, invalid tag, HTTP failure or failure of both hosts remains an error.
- Manual connection errors have specific DNS/offline/timeout/TLS explanations and Try Again, Open Downloads and Cancel. The current-version message also handles local builds newer than the latest published version correctly.
- Unit/URLSession fixtures pass API-only success, DNS/rate-limit/server-error fallback, newer/current versions, missing releases, invalid URLs, failure of both hosts and cancellation without fallback. The live check succeeds on the affected Mac and reports no published release.
- Built and ad-hoc signature-verified 0.3.8 and the canonical bundle; calculation-engine bytes are unchanged. Opened 0.3.8 and selected Help → Check for Updates: the native dialog correctly says No published update is available and identifies version 0.3.8. No GitHub release or installer was published by this fix.

```sh
swiftc Sources/UpdateService.swift Tests/update-service-test.swift -o .build/update-service-test
.build/update-service-test --live
```

## 2026-09-26 — 0.3.11: Report export and Excel paste

- Save Report (⌘S) offers HTML, PDF and DOCX in a native format chooser; changing formats changes the filename extension. Verified the actual dialog through a successful DOCX save. File → Export provides direct entries too. The complete active report is exported.
- `Scripts/test-report-export.sh` ran the unchanged 5.0.8 engine for paired t/agreement and chi-square 2×2, appended a 65-row synthetic table with merged headings, and exported/reopened the combined report. All native assertions pass: portable HTML, five A4 PDF pages including the last result, SVG charts, and a reopened HTML-to-DOCX round trip. App-only controls/scripts and local help paths are absent from saved HTML.
- DOCX package checks verified three editable tables, all 65 observations, horizontal/vertical merges, two repeated heading rows, superscripts/subscripts, external help relationships, and SVG plus PNG chart media. Both the PDF and the four-page DOCX rendering were visually checked. Word uses semantic document formatting; PDF follows WebKit pagination (table headings do not reliably repeat there).
- Actual Microsoft Excel for Mac ⌘C/⌘V testing exposed chart-axis text leaking into cells, text-label and scientific-number formatting issues, and pictures covering later results. Corrected the report clipboard HTML and retested in a new synthetic worksheet. All 65 labels, decimals, negatives and scientific P values are present; numeric cells remain numeric, both header merges survive, and the picture ends before the next analysis. No Excel error cells occur. Excel retains destination column widths; wrapped labels remain visible and AutoFit gives more room.
- Native clipboard tests pass whole-report selection, a single selected table row with restored table structure, and empty selection; the plain-text fallback contains tab-separated cells and excludes chart-axis clutter. Node tests cover percentages, Unicode minus, identifiers, Excel's 15-digit precision bound, formula-like labels and nonnumeric values. No calculation code changed.
- The versioned and canonical 0.3.11 app bundles pass deep/strict ad-hoc signature verification. The calculation-engine binary is byte-for-byte identical to 0.3.10. The downloadable ZIP is 153,476,978 bytes; SHA-256 `77d0e0c8898463e77b0d1ad52f08996fb75e0cafd9361cab7fecc55891b0c5d1`.

```sh
node --test Report/clipboard.test.mjs
Scripts/test-report-export.sh "$PWD/StatsDirect Viewer.app"
```

## 2026-09-29 — 0.3.12: Engine 5.0.13 and matching help

- Advanced the pinned core from 5.0.8 to 5.0.13 (`30fa75dc342d`), imported 881 verified source/asset hashes and 399 help topics (`5d78253cb44b`). Reviewed every changed Mac platform copy; refreshed Nonparametric with only its two unused DevExpress imports removed. Calculation algorithms are the Windows source.
- Full Mac build and regression tests pass. Thirteen additional upstream suites pass on Mac, including 61,076 numbered checks plus GLM fitting. The Frequencies suite exercises the actual Mac worksheet converter; the single Windows-only DataGridView test block is explicitly omitted. The 4,902-case distribution results and all 322 previously adjudicated R discrepancies are unchanged. Fresh R noncentral-t and rates references also pass.
- New native bridge checks verify rate-difference confidence limits against R, valid direct-standardisation input with more events than person-time, matching screen/worksheet results, updated Cox precision and removal of the splitting-ratio prompt, Cox results against R survival, and integer-count validation in the single-proportion form.
- Packaged-app HTML/PDF/DOCX, report clipboard and tutor/workbook-context tests pass with the new engine. About visibly reports Mac 0.3.12 and calculation engine 5.0.13. Detailed scope, provenance, references and raw suite logs are in [the integration audit](../Docs/Validation/Core-5.0.13/README.md).

- Canonical, versioned and re-extracted ZIP applications pass deep/strict ad-hoc signature verification. Release ZIP: 153,622,445 bytes; SHA-256 `dc611d30b51d44a514ecc41e1226b2e8c9a4d65a9aa7e533dad907cc71f09b1f`. The extracted assembly is byte-identical to the tested engine.


## 2026-09-30 — 0.3.13: Latest core revision 176eef77b986

- Updated from engine commit `30fa75dc342d` to `176eef77b986`, retaining the upstream 5.0.13 version label. Imported 882 verified engine source/assets and matching help `9894a2641329` (399 topics, 979 assets). About visibly reports Mac 0.3.13 and the new engine revision.
- Refreshed the Mac Nonparametric copy directly from upstream, excluding only its two unused DevExpress imports. Updated Mac calculator hosting for small noncentral-t upper tails, Spearman limits, safe Kendall score validation and fractional t degrees of freedom. Original Windows numerical algorithms are retained.
- All 21 upstream suites pass, including eight newly added menu suites. Fresh R references for clinical epidemiology, parametric methods, nonparametric methods, descriptive statistics, ANOVA and sample size are regenerated and checked. Five agree directly; all 19 descriptive skewness discrepancies are independently proved to be R rounding residuals on exactly symmetric inputs (maximum 2.6e-17). The raw failing log and exact-arithmetic adjudication are preserved, without relaxing tolerances. The 4,902-case distribution audit reproduces its previously adjudicated output exactly.
- The normal Mac build now checks 1,156 supported forward-calculator/invalid-input cases with 2,327 probability comparisons, plus one-value summaries, large-offset ANOVA against R, very small signed ranks, and repeatable Gini/diversity bootstrap seeds. Unsupported Windows inverse/rank-score input routes are explicitly counted; details and raw logs are in [the integration audit](../Docs/Validation/Core-176eef7/README.md).
- Packaged-app HTML/PDF/DOCX, report clipboard and tutor/workbook-context regressions pass. Versioned, canonical and re-extracted applications pass deep/strict ad-hoc signature checks. ZIP: 153,631,867 bytes; SHA-256 `e8d0926d09cb564b2aded4989e5f8c42116a29430dc427ce52c9356ec0aaf690`. The packaged engine assembly matches the tested build byte for byte.


## 2026-09-30 — 0.3.14: Official engine 5.0.14 tag

- Pinned official `v5.0.14` at `b10edfefa54b`. Only the upstream Windows version metadata and changelog differ from the previously incorporated `176eef77b986`; all calculation code, fixtures, operation/report definitions and help are unchanged.
- Normal Mac build and all its regression checks pass, including 1,552 distribution checks and 1,156 Mac calculator cases. The previous 21-suite/R audit is retained as evidence for the unchanged source, not claimed as newly rerun. Details and full build output are in [the release audit](../Docs/Validation/Core-5.0.14/README.md).
- Canonical, versioned and re-extracted apps show Mac 0.3.14 and engine 5.0.14 metadata, have identical engine bytes, and pass deep/strict ad-hoc signature verification. ZIP: 153,631,869 bytes; SHA-256 `234051b29f0de0530432843b897e5a638666ced29fb00bdc7e84d4e95c9634c5`.
- Opened the new version and verified the actual About dialog: Mac 0.3.14, calculation engine 5.0.14, revision b10edfefa54b.

## 2026-10-09 — Engine pinned to upstream 85057e43

- The engine submodule moves from the `v5.0.14` tag (`b10edfef`) to `85057e43`, six commits later on the Windows `main` branch, still reporting version 5.0.14. `upstream-manifest.json` and `Content/engine-info.json` were regenerated: 873 hashed files, down from 886.
- The six commits fix group selection by identifier on Windows (a blank identifier keeps its row as a missing identifier, a value without an identifier and a group without numeric values are refused, and the two frequency commands no longer offer identifiers), retire the seven operations that no menu reached and no help topic described (GroupedOneWay, GroupedTwoWay, SortByExpression, StackedBarPlot, StackedBar100PercentPlot, ExploreContinuousDistributions, TransformZECDF, with their templates, registry entries and the code only they called), and delete the superseded `Assets/WebHelp` copy, which the Mac never used: `Content/Help` is the statisticalhelp `Docs/` build and is unchanged.
- Expectations updated: 277 operation definitions, of which 275 are reachable (208 menu commands, 67 follow-ons; only ImportWorksheet and ExportWorksheet are neither), and 36 frames that offer group identifiers (40 before: the two frequency commands and the two retired grouped analyses).
- On this engine the full build passes, `test.sh` reports 177 checks, the Node suites 82 tests, and the report export and the WebKit integration driver pass.

## 2026-10-09 — Engine pinned to upstream cd022814

- The engine submodule moves from `85057e43` to `cd022814`, three commits later on the Windows `main` branch (version still 5.0.14). They make the Windows grouped covariance selection refuse a value whose group identifier is blank, by row, through a `RowWithoutIdentifier` rule shared with the one-way selection, with the identifiers asked for again after a refusal; the other two commits add five checks of the rule to the Windows `tests/DataSelection` project and a changelog entry. Only `UI/GridSelectionProcessor.cs`, which the Mac host does not compile, changed, so the regenerated `upstream-manifest.json` lists the same 873 files with new provenance.
- Full build, `test.sh` (177 checks), the Node suites (82 tests), the report export and the WebKit integration driver pass on this engine.

## 2026-10-09 — Grouped covariance by identifier

- The analysis of covariance takes long data, as the Windows routine Gidxyr: `HostComplexData.GroupedCovariance` asks how the groups are laid out (each group's predictor series in its own column, or one X column and Y column(s) with group identifier columns), then `GroupedCovarianceFromIdentifiers` builds `GroupedCovarianceData` from the X column, the Y replicate columns and up to ten identifier columns, groups in first-appearance order titled `identifiers_label`. A value beside a blank identifier is refused by row (each Y column, then X). A row whose X is missing is left out of its group and a missing Y replicate out of its X level, which matches the separate-column path after missing values are removed within each series; Windows instead keeps missing values in the arrays and sums them (reported to the Windows session). The form gained an outcomes role; an option prompt re-asked with an error now pre-selects the engine's default (this also corrects the two-dimensional layout prompt).
- `Tests/test_group_identifier.py` compares long and wide reports number for number for a single Y, Y replicates, a missing X row and a missing first and last replicate, and checks the option prompt, the refusals and the record; `Grid/operation-data.test.mjs` covers the roles; `Tests/group-identifier-driver.swift` drives the real form (layout choice, X, Y replicate and identifier roles, history and R script). Adversarial review: eight candidates, two confirmed (low), fixed. Full build, `test.sh` (177 checks), the Node suites (83 tests), the report export and the WebKit integration driver pass.

## 2026-10-09 — Engine pinned to upstream b02a1541; help at statisticalhelp 2000ba0

- The engine submodule moves from `cd022814` to `b02a1541` (version still 5.0.14): the Windows analysis of covariance by identifier now leaves missing values out as the separate-column layout does (`PlaceByGroup` in `GridSelectionProcessor.cs`, after this port reported that it summed them), with its checks and changelog, and the rebuilt CHM. Only Windows selection code, its tests and the CHM changed, so the regenerated `upstream-manifest.json` lists the same 873 files.
- `Content/Help` was re-imported with `import_help.py` from statisticalhelp `master` at `2000ba0` (Flare output `72c8dff`): the grouped covariance topic gains the sentence on blank cells in the identifier layout; the search index and equation images are Flare's rebuilt output. `Content/help-manifest.json` records the commit.

## 2026-10-09 — Worksheet write-back as on Windows

- An operation's output frames are written into the worksheet the analysis came from, as the Windows shell writes them (`SDApplication.OutputFrame`, `frmSpreadsheetGear.WriteDataFrame`): the start snapshot carries `writesWorksheet` and the definition's default placement (the first output step, nested steps included), each frame carries its placement, keep-selection, missing indicator, formula flag and variable lengths, the form offers "Write the results" (a new document, or the five Windows positions for a live worksheet, defaulting to the definition's), and `Grid/write-back.mjs` plans the edits: first free column after the used ones, titles in the title row, `*` for missing values, insertions moving the columns to the right along with their cell kinds (`GridStore.apply` takes an explicit kind per edit), replacement clearing the target columns, later frames chained by their own step. One undo step; the written range is selected; the form's snapshot is refreshed after the write. Values align to the analysis rows when the output has one value per input row. Refused with a message: insertion into a file-backed workbook (cell formats and formulas would not move) or into a sheet with formulas. Entered data and instant forms do not write back.
- `Grid/write-back.test.mjs`, `Tests/test_write_back.py` (in `test.sh`) and `Tests/write-back-driver.swift` (in the WebKit suite) cover the positions, chaining, kinds, alignment, refusals and undo. Adversarial review: 23 candidates, 15 confirmed and fixed before the commit. The grouped covariance long layout now keeps an X level whose replicates are all missing with a count of 0, as Windows and the separate-column path do. Driver checks end a failed run normally rather than trapping (no macOS crash dialog). Full build, `test.sh`, the Node suites (93 tests), the report export and the WebKit suite pass.

## 2026-10-09 — Engine pinned to upstream 2a55c5c4

- The Windows `main` head removes `Assets/menu-sd2.xml`, the second menu layout the program never loaded, with a changelog line. The asset was never in the provenance manifest, so the regenerated manifest lists the same 873 files and the engine is identical; the pin moves only to stay at the branch head.

## 2026-10-09 — Continuous integration

- `.github/workflows/ci.yml` runs on every push to `main`, every pull request and on request, on a GitHub-hosted `macos-15` (Apple Silicon) runner with the .NET 10 SDK, Node 24 with pnpm through corepack, R and openpyxl: `build.sh`, a check that `node Grid/build.mjs`, `Report/build.mjs` and `Learn/build.mjs` reproduce the committed `Content` bundles, `test.sh`, the Node suites, `Tests/test_excel.py`, `Tests/test_excel_edges.py` and `Tests/test_data_files.py` with their drivers, `Scripts/test-report-export.sh` and `Tests/run_beta_feedback.py`. NuGet packages and the pinned ChatGPT runtime archive are cached. Actions are pinned by commit, as the release workflow pins them.
- The first run of the CI job on GitHub-hosted hardware (commit `195036d`) completed successfully: build, bundle check, `test.sh`, the Node suites, the Excel and data-file tests, the report export and the WebKit integration driver all passed on the `macos-15` runner.

## 2026-10-09 — The help's worked examples replayed through the Mac engine

- `Tests/help_examples.py` reads every help page that uses the test workbook (89 pages; 68 print an example output under "For this example"), the columns it names, the operation it documents (from the analysis menu's help links) and the figures it prints. `Tests/test_help_examples.py --report` runs each example through the engine host at the prompt/answer boundary with the named columns from `Assets/Data/test.xlsx` (columns matched to prompts by the roles the page gives them, numbers, options, yes/no answers and skips taken from the page's own instructions, follow-ons the page names run on the result) and looks for every printed figure in the Mac report, at the page's precision. The survey is `Tests/help-examples-results.md`.
- Result (after the harness learnt to read column roles, options and follow-ons from the page): 27 pages reproduce every figure (one-way, two-way and nested ANOVA, the paired, unpaired and single-sample t tests, F, normality, Kendall, Spearman, Mann-Whitney, Wilcoxon, Smirnov, Kruskal-Wallis with its pairwise comparisons, Mantel-Haenszel, Peto, relative-risk, risk-difference and summary meta-analyses, grouped linearity, logistic and logit, simple, multiple and polynomial regression with their follow-ons, Cox regression with its hazard ratios and model analysis, Kaplan-Meier, the follow-up life table); 12 plot pages run and draw. The rest are limits of the harness, not of the engine, which is byte-identical to Windows: pages that enter data or name no workbook columns (5), optional frames and layouts the page describes in prose (5), four pages whose example data the harness reads wrongly (a date column, a stacked block, a censor column of the wrong rows), three methods with bootstrap or simulated figures, LOESS (R-based, not enabled), and six pages where a few figures are not found: figures quoted in prose, a second variant of the same analysis (a conservative interval, another weighting) or a second example on the page. All are listed in the survey with the missing figures.
- `test.sh` runs the reproducing pages as a regression check (`python3 Tests/test_help_examples.py`).
- Polish of 9 October (evening): the harness reads names in single or curly quotes, takes a page's columns from the one worksheet most of them share and, where a title recurs there, from the block whose rows match the page's other columns, uses a column's own title words as its role when the page gives none, matches roles by word stems and prefixes, picks the repeat digit for "T1 (rep 1)" patterns, tries each value of an option prompt and credits a page whose printed variants are covered across runs, follows a second example on the same page to its own operation, and takes a few columns and answers from a per-page table. 33 pages now reproduce every figure (adding the replicate two-way ANOVA, the meta-analyses of correlations, effect sizes and incidence rate differences, preference allocation and the unpaired z test) and one more across two runs (the quantile interval, conservative and not); 13 plot pages draw. Left as limits of the harness: pages whose example data are not in the workbook under the names given (Latin square, nonparametric regression, Poisson after dummy coding, grouped covariance replicates, crossover's second group, the survival plot's second group, Cuzick's scores), three with bootstrap or simulated figures, LOESS, and four with prose figures or a second variant not reachable in one run (reference range, single-sample z, log-rank weightings, conditional logistic's longer predictor block).
- Seen on the way: the engine's HTML report renderer writes a P value as `P < 0.0001` with a bare `<` inside the `pval` span. Browsers tolerate it, but the HTML is not well formed; reported upstream.

## 2026-10-09 — Engine pinned to upstream 00aa1ced

- The Windows `main` head encodes every substituted value in the engine's HTML report renderer (`CreoleHtmlReportRenderer.cs`), after this port reported the bare `<` in `P < 0.0001`; a title with an ampersand or angle brackets was affected too. The Mac shows the engine's HTML, so this is the pin that carries the fix: a P value below the threshold now renders as `P &lt; 0.0001`. The regenerated manifest lists the same 873 files with the renderer's new hash. Full build, `test.sh` (including the help-example baseline), the report export and the WebKit suite pass.

## 2026-10-09 — Chart geometry beyond the agreement plot

- `Tests/test_charts.py` (in `test.sh`) draws twelve chart types from small fixed data through the engine host and reads the marks back through each chart's own axis tick labels (a linear fit of value to pixel, exact to the pixel): scatter and line plots (every point on both scales, joined in order), bar and frequency bars (from the baseline to the value or count), the histogram (equal bins covering the data whose heights count every observation), box and whisker (quartile box, median marker, whiskers to the data, the outlier as a point), the normal scores plot (rank order on the value axis), error bars (each bar from the lower to the upper limit), spread and ladder plots (every value, each ladder pair joined), the control chart (mean and sigma limits where the data put them), the forest plot (each estimate, its interval and its label), the population pyramid (proportional bars either side of the centre to the stated scale), the ROC plot (inside the unit square, the diagonal, and an area equal to the one the report states) and the survival plot (a marker at each event, steps through censoring). Every coordinate must lie within the SVG's viewBox and no chart may report "Chart not drawn". The tutor consent step the Mac build added on 8 October was checked against the second handover's concerns and covers them all (Lessons-only on every open, a per-question confirmation recorded before any document metadata is sent, a heading screen, a managed preference to disable the online tutor).

## 2026-10-09 — Columns inserted into opened workbooks

- A write-back that inserts columns is no longer refused for a workbook opened from a file. The grid records each insertion ({col, count}, in the coordinates of the moment) on the undo step and in `store.inserts`; the Excel save sends them beside the snapshot (`inserts` in the save request), and the ClosedXML patch path applies them before the cell edits: ClosedXML inserts the columns in memory and re-references every formula in the workbook, and `PatchOriginal` moves the original package's cells to their new addresses (styles with them), shifts the `<cols>` width definitions, writes each formula as ClosedXML re-referenced it, and updates the dimension. Refused with a message rather than risked: a streaming save (workbooks over a million cells), worksheets with merged cells, conditional formatting, data validation, tables, autofilters, hyperlinks or protection, workbooks with defined names, and workbooks with shared or array formulas; in the grid, an insertion before formula cells, which cannot move there.
- `Tests/test_excel_inserts.py` (in CI with the other Excel tests) builds a workbook with openpyxl, inserts a column through the save and reads the result back: the output lands in the new column, the moved column keeps its percentage format and its width, formulas in the same sheet and in another sheet point at the moved cells, two successive insertions apply in order, and merged cells, shared formulas and streaming saves are refused. `Grid/write-back.test.mjs` covers the recorded insertion and its undo.


## 2026-10-09 — 0.3.20 release integration and native optimisation

- Integrated through `9e60f13`, retaining engine `00aa1ced` and help `2000ba0`. Added shared Release/Debug flags for the native shell, bridges and test hosts; Release preserves safety checks and emits separate, verified dSYM bundles.
- Local build, full engine/R suite, 94 JavaScript tests, 33 help examples, chart geometry, Excel insertion/edge tests, CSV/R-data tests and the optimised native host against the extracted release all pass. The actual executable reports StatsDirect 0.3.20 and the updated engine revision.
- The latest upstream CI had another native wait timeout; waits now report file/line and CI retries that timeout once, retaining hard failures for other errors and for a second timeout. Simulated failure and recovery cases verify pipeline exit-code propagation.
- [Package identities, detailed checks and remaining limits](../Docs/Validation/Beta-0.3.20/README.md). Apple signing/notarisation remain pending.


# Excel compatibility — Mac 0.3.21, 9 October 2026

Opening/reading and source-column insertion safeguards are now explicitly separate. XLS, XLSB, macro-enabled, template, Strict and password-protected workbooks use a compatibility reader with typed snapshots; ordinary XLSX retains its preserving editor. New tests cover values, types, hidden/complex sheets, out-of-order BIFF rows, passwords and source preservation, plus 1,048,577 populated cells through the last Excel row and column. [Implementation, evidence and limitations](../Docs/Validation/Beta-0.3.21/README.md).

## Report editing and legacy RTF import (10 October 2026, local development build)

- Native WebKit checks cover typing, bold/underline, headings, bullets and numbering, paragraph alignment, undo/redo, retaining edits when analyses are appended, removing/restoring plots, and reopening edited HTML. Existing full-report/partial-table/empty clipboard checks still pass.
- Original fixtures in `Tests/Fixtures/Reports` cover RTF tables, Greek and superscript text, hidden help metadata, hex and binary picture storage, alternative-picture de-duplication, placeable and standard WMF, EMF, PNG, malformed RTF, and visible failure messages for unreadable charts. The source RTF is byte-identical after import/export.
- HTML, paginated PDF and DOCX exports pass for both edited reports and imported RTF. `Tests/verify-report-documents.py` inspects actual Word XML for formatting, alignment, headings, lists, tables and SVG images with PNG fallbacks.
- Six report JavaScript tests pass, including physical RTF cell boundary mapping, font fallback handling and rejection of truncated metafiles and record-limit overflows. Import sanitization rejects active content, local/external image references and unsafe links. Dependency notices follow the installed production graph and include embedded converter notices.
- The Release build and its 1,552 distribution regression checks pass. A native visual check confirms the converted table, Greek text, WMF/EMF charts, editing toolbar and Command-Z restoration. This is not a full rerun of unrelated worksheet/analysis suites.
- A user-supplied Windows RTF report (kept outside the repository) imports all three tables and four EMF charts as SVG, exports to HTML/PDF/DOCX, and remains byte-identical. All 159 numerical tokens in the visible report text match the original after excluding hidden help identifiers and normalizing superscript text boundaries.
- The real report exposed a missing-font fallback: its EMF charts request Calibri, initially available only privately inside Word on the test Mac. Chart conversion and HTML reopening now preserve the requested face and add suitable sans-serif, serif or monospace fallbacks. Synthetic Calibri EMF coverage verifies the fallback through native WebKit import, HTML export and reopening; a unit test covers quoted/case-insensitive names and preservation of custom fonts. Exact Calibri rendering requires that font to be available to WebKit; proprietary fonts are not bundled with StatsDirect.
- SVG bounds expand when the rendered lettering exceeds the original Windows viewport, preserving the recorded drawing coordinates while preventing substituted fonts from clipping edge labels. Native checks verify all text bounds in the real report, plus a synthetic label extending across the right edge. PDF inspection confirms Arial regular/bold replacing the unintended Times fallback; DOCX retains all four SVGs with their fallback families and PNG alternatives.
- At the user's request, the test Mac's existing Office Calibri files were installed in that user's macOS Fonts folder (regular, bold, italic, bold italic, light and light italic). The real report was reimported and exported again in all three formats: PDF font resources now confirm Calibri and Calibri-Bold, all four SVG charts have complete label bounds, and the source RTF remains unchanged. This is local font availability, not redistribution in the application or repository; other Macs still need those fonts installed for an exact face match.
- RTF layout now uses 16px body and 14px table text, preserves relative sizes/emphasis, removes surplus blank paragraphs and restores spanning headers from the RTF cell boundaries. A fixture with repeated Word row definitions checks header spans, numeric alignment and matching column coordinates across rows; two successive HTML reopenings preserve text sizes. DOCX XML confirms the spanning header and 12pt/10.5pt body/table text. The real report's three heading rows now match the Mac engine's spans (1+5, 1+1+3 and 1+1+1+3).
- Remaining fidelity qualification: one real report plus synthetic fixtures does not represent the complete archive of Windows reports. Complex drawing effects, unavailable fonts and advanced RTF page layout can differ. RTF import is limited to 30 MB and 200 pictures; RTF writing is deliberately unavailable.


## Expanded report editor (10 October 2026, local development build)

- The native Format menu and report toolbar provide font family, exact point size, headings, bold/italic/underline/strike, super/subscript, text colour/highlight, bullets/numbering, indentation, four alignments, line spacing and clear formatting. Formatting is enabled for reports in edit mode; ordinary Edit menu commands remain available.
- Native WebKit integration tests exercise real control focus changes, an 18.5pt font selection, typing at a 20pt caret, undo/redo, native Format dispatch, protected SVG charts, paragraph indentation and nested lists. New analyses and removal undo retain edited content.
- HTML/PDF/DOCX export and HTML reopen checks pass, including a user-sized paragraph in a normalized legacy RTF report. Word XML verifies Times New Roman, exact half-point sizes, red text, yellow highlight, strike/italic, super/subscript, double spacing, paragraph indent and true nested list numbering.
- Native UI checks on a disposable copy of the real Windows/Mac comparison report verify the visible Format dropdown, font selection (Calibri), keyboard entry of 14pt and retained text selection. The original user report and workspace are unchanged.
- The six report JavaScript tests pass. The Release build completes with the engine's 1,552 distribution regressions and matching native debug symbols. The user's existing report workspace remains open during installation.


### Compact report toolbar (10 October 2026)

The report toolbar now places common commands on one compact row, using labelled tooltips for the formatting icons. Less-used controls are in a More popover; opening it does not displace report text, and Escape or clicking outside closes it. Disabled removal undo is hidden, and the report's top padding is reduced during editing. The full Format menu remains available. The existing native editing/undo/reopen and HTML/PDF/DOCX suite and six report JavaScript tests pass; chart protection checks explicitly target report SVGs, excluding the new toolbar icons.

### Chart resizing (10 October 2026)

Edit mode adds a corner handle, pixel width and Fit control for report SVGs and raster pictures. Dragging preserves proportions and creates one native undo entry; Escape restores the starting size without adding history. Arrow keys resize a focused handle. Width lives on the picture itself, while controls are excluded from persistence/export. Native WKWebView tests cover width entry, drag/cancel, keyboard resizing, Fit, undo/redo, narrow-window fitting, unchanged vector contents, retained sizing when later results are appended, HTML/PDF/DOCX export, clipboard and HTML reopen. Word package checks confirm the selected 320px SVG and 200×100px raster sizes, including after reopening HTML. Existing report import/export/editor tests and all six JavaScript tests pass.

Native UI checks on the user’s saved Windows/Mac comparison report confirm a 480px imported EMF/SVG chart can be dragged to 360px and restored with one Undo; invalid zero width is rejected. The saved report was reopened unchanged after testing. PDF object inspection confirms the selected SVG/raster width ratio and original aspect ratios survive native page fitting.

### Rich report cut, paste and move (10 October 2026)

- Native cut/copy/paste uses a private HTML clipboard representation for vector charts and report formatting, plus Office-compatible HTML with PNG chart fallbacks and plain text. Cut removes content only after the clipboard write succeeds; pending cuts/pastes validate their original content before editing. External HTML and RTF retain supported formatting after offline sanitization.
- Moving a selection between result sections records all affected sections in one undo transaction. Partial table cuts preserve unselected cells and merged headings; complete tables, lists and sized charts retain their structure. Pasted SVG identifiers are rebased so duplicated clip paths and gradients remain independent.
- Direct pointer handling avoids WebKit's hold delay for native selection dragging and supports SVG charts as drag sources. Option copies, Escape cancels, and an insertion marker and edge scrolling guide the destination. A chart grabbed inside a mixed selection moves the complete selection.
- The native WKWebView suite passes for styled cut/paste and undo/redo, partial and merged tables, lists, SVG clip references and widths, same-paragraph moves, moves/replacements across sections, native drag and direct pointer paths, Option-copy, cancellation, self-drop and stale-cut protection. Moved content exports to HTML/PDF/DOCX and reopens intact; Word XML confirms the font, spanning cells and 240px SVG. Existing report editing, chart resizing, RTF import, export and six JavaScript tests also pass.
- Manual native UI checks in a disposable report confirm Command-X/Command-V and context-menu Cut preserve the selected bold blue 18pt Times New Roman text. Direct mouse moves of that text and a 240px SVG both restore with one Command-Z. The live user workspace remained untouched during these checks.
- The Release build, 1,552 engine distribution regressions, matching debug symbols and bundle signature verification pass. The installed app was replaced atomically with the previous build retained, then relaunched after confirming the live workspace contained only an empty worksheet. No unrelated worksheet/analysis suite was rerun for this report-only change.

### Report editor integration with the latest engine and LOESS (10 October 2026)

- Incorporated upstream commits `74b54cf`, `3c7501a` and `1b68ee6` while preserving the report editor and RTF import work. The calculation engine is pinned to Windows `4ee43dc66c03` (version 5.0.14); LOESS runs through the new R route.
- Combined export testing found and corrected two chart issues: DOCX now honours a raster chart's declared display width, and imported HTML preserves SVG text alignment and local clip/paint references. Tests confirm the 504px R chart, selected 320px SVG and 200×100px picture survive export and reopening without changing the SVG viewBox or aspect ratio.
- The final Release build passes its 873-file provenance check and 1,552 distribution regressions, matching debug-symbol checks and deep/strict ad-hoc bundle signature verification. Grid, Report and Learn browser bundles reproduce byte for byte.
- The full `test.sh` suite passes, including 54 worked help examples, numerical comparisons with R, chart geometry, 207 menu and 67 follow-on operation form coverage, and all 105 JavaScript tests. LOESS checks cover the help example's reported figures, fits and standard errors against a separate R run, missing outcomes, two predictors, R errors, unavailable R and cancellation.
- All six Excel/data-file suites pass: ordinary and edge-case import/export, column insertion, advanced structural edits, compatibility formats, CSV and R data. This includes streaming insertion of 1,000,010 cells and compatibility imports through Excel's last row and column. The insertion suite was rerun with Node on PATH after the initial local invocation could not locate Node.
- The native report suite and Word XML checks pass for editing, chart resizing, rich clipboard transfer, drag-to-move with undo, legacy RTF import, sanitization and HTML/PDF/DOCX export/reopening, including the new LOESS report.
- The full native WebKit integration suite passes against the final app: Excel formats and password handling, offline tutor/provider context and exports, report editing/transfers, 10,000×10 worksheet paste, 1,048,576-row embedded entry and summary, selection of a 500,001×2 block, Cuzick prepared scores, all 12 shared control variants, grouped analyses and file-backed insertion/undo. The descriptor audit reports 1,009 passes, 15 explicit host routes and no failures. Live external AI services were not exercised in this integration run.

### Shared DOCX exporter: semantic containers (10 October 2026)

- The Windows WebView2 prototype reported tables/charts flattening to text inside `main`. Reproduced on Mac with nine wrappers (`main`, `header`, `footer`, `aside`, `nav`, `figure`, `figcaption`, `address` and a custom element): the original DOCX had zero real tables or drawings; reopening HTML retained only the custom wrapper's table/chart because import removed that unknown wrapper. Normal generated Mac reports use supported `article`/`div`/`section` wrappers, but imported HTML retains semantic containers, and import warnings use `aside`.
- The shared exporter now recurses through semantic containers and other elements containing supported block content. Equation trees remain atomic. No calculation or native host code changed; the browser export bundle was rebuilt.
- The full native report suite and six report JavaScript tests pass. The new Word-package assertions verify all nine real tables, horizontal and vertical merges, nine SVG charts with PNG fallbacks, headings, ordered lists, hyperlinks and content order, both directly and after HTML export/import. Native checks also verify HTML and PDF retain the fixture contents. Existing editing, rich transfer, resizing, legacy import and export tests remain passing. These results cover WKWebView; Chromium validation remains with the Windows session.

### Arial report defaults and stylesheet formatting (10 October 2026)

- New report content and annotations default to Arial, retaining the existing Mac text sizes. Existing explicit/imported font choices take precedence. The Mac SVG renderer and its CoreText measurement already use Arial; native checks now verify the real paired/agreement chart's text face.
- The shared `FontDescriptor.TryParse` defect is present in the pinned C# source: it cannot parse the `pt` suffix emitted by `ToString`. The Mac `Settings` implementation has no engine-side persistence or load, and the native preferences path does not set `TitleFont`/`LabelFont`, so the reported saved-font reset path is not exposed by the Mac UI. No private copy or submodule edit was made; the Windows correction can be incorporated with its next committed engine revision.
- Reproduced fresh DOCX export losing stylesheet-only colours. Word export now resolves presentation styles into its detached copy, excluding SVG and report controls. HTML/PDF keep their stylesheets; the live document and revision remain unchanged. Inherited/default Arial and explicit Georgia/Times New Roman point sizes are verified in Word XML.
- The reopening regression also exposed ancestor classes being removed before descendants' CSS was resolved. HTML import now computes all presentation styles before removing HTML classes/IDs, preserving descendant selectors while retaining SVG identifiers.
- The full native report suite, Word-package assertions and six report JavaScript tests pass. Tests cover CI/P-value/warning class colours on the first export and after HTML reopening, custom report/chart fonts, unchanged live content and revision, existing RTF/Calibri fidelity, editing/transfers, chart sizing and semantic containers. Browser bundles and notices reproduce byte for byte. These checks do not imply a release, installation or engine update.

### Report controls in reading mode (10 October 2026)

- Chart/picture sizing controls appear only in report edit mode. The main toolbar, report notes and import notices remain available. Hidden report controls explicitly stay hidden despite the base flex layout.
- Native UI checks in an isolated test app confirm Edit report reveals width/Fit and the resize handle; Done editing hides them again while retaining the toolbar, notes, table and chart. The former removal buttons are superseded by selection/Delete below. No user workspace or installed app was changed.


### Selection, Delete and unified report history (10 October 2026)

- Click a chart and press Backspace/Delete, or delete it from an immediately adjacent caret. Clicking a result’s first heading selects that result; Shift-click selects a range of results, and Command-A selects the whole report. Partial table selections preserve the table structure and unselected cells. Fully selected result entries are removed, with their notes and analysis/R metadata retained for Undo.
- Text changes, formatting, picture sizing, selection deletion, rich transfers and Add text now share one chronological undo/redo history. Structural changes store affected entries and positions, so restoring a result preserves later engine output. Restored notes retain subsequent edits across redo/undo. Empty reports retain keyboard focus so Command-Z works after deleting everything. Remove result, Remove plot and the separate Undo removal control are gone.
- The new native checks pass for real Backspace and native menu Undo, forward deletion, SVG/raster pictures, adjacent carets, grouped result selection, merged/partial tables, selections crossing results, interleaved text/structural undo, later appended analyses, saved R recipes, empty reports, Add text, contextual deletion and read-only/input/composition guards. Width/font fields and notes keep their own text-input undo. HTML/PDF/DOCX and reopened HTML omit deleted results while preserving the remaining tables, notes and charts.
- Initial regression runs exposed invisible block-separator whitespace stopping adjacent-chart deletion; the caret traversal now skips only whitespace with no rendered width. The older sizing test expected Undo from inside the width field to undo the report; it now checks the requested input isolation and exercises report undo from the sizing handle instead.
- The Release build passes the 873-file engine provenance check, all 1,552 distribution regressions, matching debug symbols and deep/strict bundle signature verification. The engine submodule is unchanged. The six report JavaScript tests pass; browser bundles/notices reproduce byte for byte and match the Release app resources.
- The full native WebKit integration suite passes against that Release app, including the new deletion checks, existing editing/transfers/resizing, legacy RTF import, semantic-container and font/colour regressions, offline tutor/provider workflows, Excel and large worksheets, embedded forms, grouped analyses and file-backed insertion/undo. All Word-package assertions pass, including retained table merges, notes and SVG/raster drawings after result deletion. Live external AI services were not exercised.
- Manual UI checks in the isolated report test app confirm clicking a result heading and Backspace removes the result; Command-Z restores its text, table, notes and sized chart. Command-A/Backspace removes the whole report and Command-Z restores it from the empty state. Clicking the SVG followed by Backspace/Command-Z removes/restores just the chart. The user’s installed application and workspace were not changed.

### Report copy/export presentation and Excel number formats (10 October 2026)

- Copy preserves the report's resolved fonts, sizes, colours, alignment, fills and borders instead of applying a separate Arial/table theme. The private clipboard retains original report/SVG markup. The public Office representation uses explicit point units, compatible underline/per-edge border declarations, and the visible collapsed table outline on outside cells. Native Excel testing exposed both its pixel-as-point font sizing and its table-outline precedence over cell borders; these are now handled in the Office representation.
- Excel receives numeric values with the displayed decimal precision, percentage or scientific format. Leading-zero identifiers, values beyond Excel's 15-digit precision and formula-like labels remain text. Number-format hints are appended literally after CSS processing, since browser CSS declarations discard Office-only properties. Existing column definitions remain in the HTML; normal Excel paste still uses the destination worksheet's column widths.
- DOCX uses computed cell/run presentation, per-side borders, padding, row/table backgrounds, vertical alignment, paragraph spacing and heading styles. Borderless tables explicitly disable all six Word table borders. Preformatted text retains its font, point size, inline emphasis, spacing and newlines. HTML/PDF no longer override the report's typography with an export theme. Border longhands survive both clipboard and saved-HTML sanitization; active content and external resources remain blocked.
- The native presentation fixture compares live, reopened, private-pasted and public-pasted tables; checks unchanged live HTML/revision; verifies single-step paste undo; and exports HTML/PDF/DOCX. Word-package checks inspect original/reopened cell and run properties, custom mixed borders, plain underlined non-bold headers, row fills and preformatted text. PDF checks verify the chosen font and relative point sizes after page fitting. Eight report JavaScript tests pass, including merged-cell outlines and Excel number precision.
- A real Microsoft Excel paste/save was inspected with `Tests/verify-report-excel-paste.py`: Arial 10pt plain headers with single underlining; Georgia 16pt heading and 18pt purple/yellow custom cell; red solid/blue dashed edges; preserved row fill; decimal, percentage and exponent values/formats; and string identifiers/formula-like labels. The disposable workbook is `.build/report-export-output/report-copy-formats.xlsx`.
- The Release build passes all 1,552 distribution checks, engine provenance and matching-symbol checks. Final browser bundles are copied into the Release app and its deep/strict signature verified. The full native report suite and Word-package verification cover the existing editing, resizing, transfers, selection/Delete, unified undo, R charts, legacy RTF and semantic-container cases as well as the new formatting fixture. The engine pin and installed user application are unchanged.
- Report-test assertions now exit with a failure diagnostic instead of trapping and leaving macOS crash dialogs. The test host also exits cleanly with usage instructions when launched without its required output-directory argument. This was verified with exit status 2; it does not suppress crash reporting for the actual application.

### Offline HTML5 help and dockable Mac viewer (10 October 2026)

- Imported all 979 files from the Windows DesktopHelp bundle at `statsdirect` commit `5398b5baae9171439c24b5d65e592db2c0eeb771` (Flare source published in `statisticalhelp` at `50b0462a35d13c995300ad4fb257b373e1b96ebf`). Every file was compared with its upstream git blob. The manifest records the revision and hashes; the importer and application build replace the complete help directory to remove obsolete assets. The target was subsequently renamed from SWHelp to DesktopHelp in Flare source commit `ee3a3d4e94f88f5dc17ce02b3b284df469753c12`, without changing runtime assets. The calculation engine remains at its independently pinned revision.
- Help uses one WKWebView in a right-hand split pane or resizable companion window. Pop out/Dock and Close/reopen preserve browser state, history, expanded R examples, reading position and the chosen presentation/width. Help automatically floats without taking input focus during modal sheets and returns afterwards. F1 and analysis/report links retain the active document and worksheet selection. Help copy, close and print commands follow the focused pane.
- The viewer serves only bundled resources at `app://statsdirect-help/`, with no worksheet/report bridge. Flare recognises the `app:` desktop protocol; an arbitrary custom scheme left its XML-loader promises pending and prevented navigation/search initialization. The generated index/search redirect works with the supported scheme, with no edits to vendor JavaScript. CSP blocks remote resource requests; clicked external references are handed to the system browser.
- `Tests/test_desktop_help.py` passes: all hashes, 798 numeric/named aliases, all 167 operation context IDs, all Mac menu help links and absence of website analytics. `Scripts/test-help-pane.sh` passes 40 native checks covering rendering, images/equations, R expansion, scroll preservation, resizing/reopening, modal focus, history, full-text search/results, external-link routing, blocked external fetches, reference anchors, unchanged worksheet selections, PDF printing and help Copy/Close commands after all workspace documents close. The test host returns ordinary failure/usage exit codes instead of trapping. Both suites are included in CI.
- Native UI inspection confirms the paired t-test form remains active when F1 opens its help, the divider resizes through its accessibility control, and Pop out/Dock work with the expected layout. Release build, 1,552 distribution regressions, engine provenance, matching debug symbols and deep/strict ad-hoc signature verification pass. The built application contains exactly the manifest's 979 help files.

- The native report presentation/export regression and its Word-package and Office clipboard checks pass with the new shell layout. The installed user application and saved documents were not changed.

- A clean Git-archive check caught 27 help paths whose directory case had been retained by Git’s case-insensitive index handling. The tracked paths now match the upstream manifest exactly. Resource lookup uses the bundle’s filename catalogue case-insensitively, matching Windows semantics even on a case-sensitive Mac volume; generated HTML/runtime files remain unchanged. A native check covers mixed-case script links.

### Dockable calculator (10 October 2026)

- Tools → Calculator opens a session pane below the active document, without creating a tab. Pop out, Dock and Close retain the expression, result, saved calculations, input undo history and chosen mode/size. Help remains independently docked on the right. Both tools float temporarily during modal parameter dialogs without taking input focus, and return afterwards.
- The wrapping native text view calculates on Enter and inserts an explicit newline on Shift+Enter. Visual wrapping never rewrites the expression. Saved expressions insert at the current selection with undo; Copy all exports their expressions and results. Errors stay inline. Edit/Close commands and F1 follow calculator focus, including when no workspace document is open.
- `CalculatorIO` calls the existing Windows `Calcit` evaluator under the shared engine execution lock. No numerical source or engine pin changed. The Release build passes 873 source/asset hashes, 1,552 distribution checks, original operation tests, matching debug symbols and deep/strict ad-hoc signature verification.
- `Tests/test_calculator.py` passes 29 engine cases: arithmetic precedence, constants, functions, logical/string results, multiline and long expressions, decimal-comma locales, rejected syntax/code/variables and recovery. `Scripts/test-calculator-pane.sh` passes native menu, keyboard, wrap, save/insert/undo, docking, resizing, minimum-window layout, modal focus, help context, worksheet-selection preservation and no-document command checks. Both are included in CI. Native UI inspection also verified entering `SQRT(81) + 2^3` and obtaining 17 with Calculator and Help docked together.
- The existing offline Help suite passes all 40 checks with the nested document split, and all 979 help hashes, 798 aliases and 167 analysis context IDs still verify. The complete engine/R regression suite passes, including the 54 worked help examples. Native report presentation/export tests pass for HTML/PDF/DOCX, report styles, borders, Excel number formatting and undo after paste.
- The rebuilt app is in the repository's `StatsDirect.app`. No new installer/release or replacement of the running user application is part of this change. Calculator entries are retained for the current session; Copy all preserves them outside the session.

### Windows calculator alignment and refreshed help (10 October 2026)

- Imported the entire DesktopHelp bundle from published Windows commit `c40b49180132b457484696f4b512e24a81f7f9e4`, including the calculator topic and regenerated index/search chunks. Its Flare source was published at `statisticalhelp` commit `033eda0`. All 979 files remain byte-for-byte upstream assets; engine pin `4ee43dc66c03` is unchanged.
- Added explicit Copy result, Recall, Insert, Remove and Copy saved controls. Selecting a saved item alone does not change the input. Recall restores its exact expression and result; Insert replaces the current selection. Both edits support Undo. Editing clears the previous answer, and an invalid evaluation cannot save or copy a stale result. Copy saved matches Windows' one-line `expression = result` format, flattening line breaks only in the copied label.
- Calculator native checks additionally cover the separate controls, stale-result clearing, Recall/Insert undo, caret preservation, all controls at the minimum window size with Help open, and wrapping that shrinks again from narrow to wide. The help test also checks the updated calculator instructions. The 29 calculator engine cases, 40 native Help checks, full help hashes/aliases/context IDs, Release build, 1,552 distribution regressions and strict ad-hoc signature/debug-symbol checks pass.
- `STATSDIRECT_APP_OUTPUT` lets the build target a separate app directory, so rebuilding does not overwrite the executable or help resources of a running user session. No installer release is published by this update.


## Calculator menu and 0.3.26 release (10 October 2026)

- Calculator is the last command in Analysis; the one-item Tools menu is removed from both the native menu bar and the in-window menu row. Its offline Help topic presents the Mac menu location while the imported Windows bundle and provenance hashes remain intact.
- Native calculator checks exercise the Analysis command, engine evaluation, saved calculations, undo, compact layout, docking, modal focus, context Help and retained worksheet selection. Native Help checks pass, including editing and Close with no document open; that final check explicitly brings its owner window to the front to model clicking its search field.
- The Release build passes engine provenance and distribution checks, and produces matching native debug symbols. The engine/R regression suite (including 54 worked help examples and form coverage), all 107 JavaScript checks, report editing/export integration checks and update-service fixtures also pass.

- The hosted calculator check exposed a mismatch between the overridden text-view undo manager and AppKit's Edit-menu path. The pane now supplies its persistent manager through the NSTextView delegate, so text editing and menu commands share it across docking changes. The optimised native test uses the real Edit commands with separate event-loop turns; insertion, Recall, Redo and undo after reparenting all pass. A background watchdog turns any future stalled test into a clear failure.

- Native calculator checks now pass all 53 cases on this Mac and macOS 15 CI, including real Edit-menu Undo/Redo and retained history after floating/docking. Test fixture replacement clears only its own obsolete undo baseline. The hosted report suite also passes with R installed.
- The export invariant compares every live report element and style except disposable chart controls, whose positions and width limits legitimately change with layout. A deliberate window resize verifies that the controls move while all report content and the revision remain unchanged. HTML, PDF and DOCX must still leave that content and revision untouched.
- The combined native suite passes locally, including report transfer/deletion/export, 10,000 × 10 paste, a 1,048,576-row entered summary, 500,001 × 2 selection prefill, MacForms, grouping, write-back and Excel insertion/undo. The large-selection fixture now waits for React to publish the loaded worksheet's edit commands before Select All, avoiding a race with the previous empty store. Actual Word XML and Excel clipboard styles are checked separately.
- The release archive was extracted and compared with the built application, with strict local signatures, all 979 offline Help assets and matching native debug symbols verified. Its SHA-256 is `d5a60f6d528a360d3396693d50c6ef6539c854f52d48a852ae5bb94adeb6bfa2`; the GitHub asset has the same digest. Apple Developer ID signing and notarisation remain excluded from this beta.
- The packaged runtime passes the complete [macOS 15 native integration suite](https://github.com/iain-buchan/statsdirect-mac/actions/runs/38049314450), including the generated Word packages and Excel clipboard checks. Separate [calculator](https://github.com/iain-buchan/statsdirect-mac/actions/runs/38048021376), [report](https://github.com/iain-buchan/statsdirect-mac/actions/runs/38048332859) and [archive assembly/checksum](https://github.com/iain-buchan/statsdirect-mac/actions/runs/38047430512) jobs pass. Test and workflow follow-ups do not change the released application sources or content from `2433c86`.

## R integration and report input display — 11 October 2026

Compared the Windows `frmMain` and `frmScript` at `84706e463c2158bd2e6dabcbd1af0d5045b9bf88`. Removed the Mac's separate R menu from both menu bars. File → New R Script starts a numbered script tab; File → Open accepts `.R` without executing it; File → Save saves the active script. Report links continue the selected result in an editable script and run it once, with inline charts and context help. Generated scripts can close without a prompt until edited, matching Windows. The script toolbar owns Run (⌘Return), Stop / Reset, Save, Clear output, Output folder, Open in R (RStudio preferred, otherwise R.app), and missing-R setup. Its single row scrolls when Help narrows the document. Each R process keeps its own directory; stopping retains access to its files, while restarting uses a fresh directory.

Removed the input-history/code expander from ordinary, dedicated contingency-table and tutor-generated reports. The R script retains the original values, input history, settings and results. User-requested R scripts printed by engine operations, such as LOESS, remain part of those results. The engine pin and statistical recipes were not updated.

Checks: Release build, 873-file engine provenance verification and 1,552 distribution regression assertions; native `Scripts/test-r-integration.sh` (menus, ⌘Return, independent tabs, safe file opening, output copies, resets, minimum width/docked Help, real paired report → R with agreement plot, HTML export, screen-data report, fallback labels and missing R); all 45 generated-script/comparison pass cases; all six engine/R host scenarios; native R plot, persistence, resize and installation checks; and `Scripts/test-learning-workspace.sh` with the actual nine PEFR pairs. The standalone learning test's wait helper is now self-contained, fixing its dependency on the combined beta harness. Native R integration is included in the main CI workflow.

The final optimised app passed strict bundle verification and was promoted to the local `StatsDirect.app`, retaining the previous app in `.build/before-r-integration-g3nqvdn8`. A live UI check confirmed both menu bars omit R, File starts R Script 1, the compact toolbar renders correctly, and Open in R opens the exact script in the installed R.app editor. The temporary example text was cleared; the updated app is open with a blank R script. No installer or GitHub release was published in this change.
# 2026-10-11 — R script AI dock

The Mac script toolbar now opens a native ChatGPT conversation in the right-hand dock.
`Scripts/test-script-ai.sh` passes 30 checks against a local mock server with fictional
worksheet values. Coverage includes no document request on opening, question-only payloads,
per-question sharing consent enforced by the host, approved dynamic worksheet reads,
identifier and unrelated-document rejection, frozen script excerpts, changed-workbook
rejection, separate per-script conversations, cancellation, institutional policy, minimum
window layout, Help/AI switching and keyboard routing. Native accessibility and screenshot
inspection confirmed the icon, dock, sharing warning and disabled Send before confirmation.

Existing ChatGPT transport and policy regressions, R integration, and native offline Help
tests pass. The separate Release candidate `.build/script-ai-build/StatsDirect.app` passes
the 873-file engine provenance check, 1,552 distribution regressions, matching debug symbols,
and strict deep signature verification. All 22 checked shared report editor modules/bundles
remain byte-identical to Windows' released editor pin. The engine stays at 5.0.14
`4ee43dc66c038f6deff1933e4fb8d42f52fafbec`; no Windows source changes were made.

No live provider question was sent. The user's existing app was not replaced/restarted.
Script conversations are in memory only; see `Docs/Learn/TutorPrivacy.md` for sharing scope.
## R pane: Output folder and the files a run writes — 11 October 2026

As the Windows script window: the R pane's toolbar has **Output folder** (opens the session folder in the Finder), and after each run the files the script wrote (charts among them) are listed as links the user can open with a click. `Tests/r-pane-driver.swift` writes a CSV from R, finds it listed once as a link, sees no list after a run that writes nothing, and finds the button enabled.

R pane, later the same day: Run script while a run is going stops that run and runs the edited script in a fresh session (as the Windows script window does); closing the tab already stopped a run. The driver starts a 20-second script, runs an edited one half a second later and finds only the edited output.

## Engine pinned to Windows main 40dd1e1d: the LOESS chart square — 11 October 2026

The shared LOESS definition opens R's svg device at 6 by 6 inches (Iain: the example chart should be square), so the chart reaches the report at 432 by 432 points and the Word export at 576 by 576 pixels; the R operations test and the Word-package check expect those sizes. The pin also brings the engine's run record, R script writer and recipes source files, which the Mac headless build compiles or excludes as the platform copies require. The manifest records 871 files.

## Engine pinned to Windows main 35610300: the method comparison scatter square — 11 October 2026

The shared MethodComparisonRegression definition draws the test-against-reference plot at 6 by 6 inches with equal axes (the line of equality at 45 degrees); the difference, residual and bias plots stay 6 by 4. Method comparison regression is still an explicit R deferral on the Mac (no calculation form yet), so the definition is carried for when that host is enabled. The manifest records 871 files; every suite and the native beta check pass at the pin.

## The Distributions calculator inverts, and records its boxes as Windows does — 11 October 2026

The Mac's distribution form (FullEngine/HostAmendments.cs) has the boxes the Windows calculator (ctlPDF) has, under the same names, and its Invert: with the value box (for the Poisson distribution, the mean) left empty and exactly one probability box filled, the value of that probability is found through the engine's own routines, as on Windows (gauinv, tfromp, ppchi2, ffromp, quantsr, tnct, poissoni, rhofromp, taufromp, with the same symmetries for small tails); the binomial distribution has no inverse. The boxes as they stand after the calculation go into the run's bag as inputs (value, df, df2, lower, upper, two_sided, asked: calculate or invert-lower/upper/two-sided), so the engine's RunRecord writes them into the record's parameters as on Windows; for the Poisson distribution the three probabilities are of exactly this count, this count or more, and this count or fewer. `Tests/test_distributions.py` (in test.sh) checks every box of every distribution against R, the eleven inverse cases of the Windows checks against R's quantiles, the recorded names, and the refusals (no box, two boxes, a binomial inverse).

## Engine pinned to Windows main b46f5f04: the R script writer binds recipe data by input name — 11 October 2026

The shared RScriptWriter lets a recipe's "# data:" header take an input of the run by its parameter name ("name = input", "name... = input", and NULL with a note when the run has no such input), for the 142 operations whose recipes Windows now carries. The Mac's current script generator is unchanged by the pin; the recipes and examples arrive with the run-record work, which uses the engine's writer. The manifest records 871 files; every suite passes at the pin.

## Engine pinned to Windows main a1063881: 177 recipes, the frames a follow-on inherits, real runs of every recipe — 11 October 2026

The engine submodule moves from b46f5f04 to a1063881 (the shared content is d7a993f0's: the two commits after it are the Windows script window's toolbar icons and their check). What the Mac takes: the record carries the frames a follow-on inherits from the run it continues (marked `inherited`, prompt empty) and keeps a setting the operation echoed as a result under the same name (the sample size calculators' `sd`); the writer makes control characters spaces in its comment lines (`Plain`), writes a Data line once, gathers the columns of several inputs of one name, and leaves out an inherited frame no variable of the recipe takes; the multiple linear regression recipe takes any column titles and any number of predictors; the recipes for the follow-on operations, the tables typed on screen and the other shapes: 177 operations in 155 recipe files (Content/R, byte for byte the engine's Assets/R), with the 354 example files of tests/RScript/examples (Tests/RScriptExamples). The README's count is 177.

`Tests/test_run_record.py` mirrors the Windows checks as extended there (Script.cs, Recipes.cs, FollowOn.cs, Regression.cs, RealRuns.cs) and goes further where the Mac runs every operation: the recipe header check admits a follow-on's parent parameters and frames (`inherits`) and the screen-typed grids, and now also requires every `name = input` binding to name a parameter (KappaScreen is the one known otherwise, below); the independent rendering of the writer's rules has `Plain`, the gathering of one name's inputs and the inherited exclusion; the "subset" comparison (every figure printed is among the help's) joins "cut"; the real runs cover 161 operations (MethodComparisonRegression, R-based and not hosted on the Mac, is the one deferral), with the example's named inputs served as pools (a frame asked once per group or repeat takes the next column), an optional frame the example lacks skipped, the columns and settings a form wants beyond the example supplied (the 2 by k trend test's scores, the survival plot's Kaplan-Meier S of each group, the survival plot's group count, Wei-Lachin's four repeats, Poisson regression's exposure), and the record compared with the example's columns under each input's name, allowing an entered frame's padding of a shorter column, a date typed as text recorded as the worksheet's serial day, and a sorted column for the plots; and a new stage runs the 12 follow-ons the manifest marks `inherits` from a real parent run (34 inherited frames checked against the parent's asked frames; the follow-on's script is the parent's where it asked for no frame of its own, and holds every line of the parent's where it did; the text is what the writer's rules give). The scripts run with the program's own R library on R's path, where `mcr` (the help's method comparison script) is installed when missing, as the program's R operations install what they need; `Content/R/session.R` puts the same library on the path for the R pane, so a script continued there finds `svglite` and `mcr`.

Results on this Mac: 54 checks; the 154 help scripts run; all 177 recipes written exactly as the writer's rules give and agreeing with the help's figures; 161 real runs complete, 142 leaving a record, all 142 scripts written as the rules give; 136 of 142 agree with the help. The six that differ are shared behaviour, raised with Windows and listed in the test as expected until changed there: Crosstabs (classifiers recorded as text under the category mode, where the recipe takes the help's numbers), KappaScreen (the recipe binds `data` where the grid's parameter is `responsesCrosstab`), LogisticRegression (the recipe's rest list `predictors...` takes the inherited prediction-grid source too: the writer's inherited exclusion covers named vectors but not the rest list), MiscRelRisk (the help's labels carry digits), SurvivalPlot and WeiLachin (a frame asked once per group or repeat keeps its last ask alone in the record, OperationRun.Note replacing the earlier note). LogRank, SizePaired and SizeUnPaired now agree and left the list. Kept on the Mac for now: the refusal of a record holding a control character in any string or key (RunRecordR.validated, ReportRHost), a stricter rule than the shared writer now needs; Windows writes such a record's script with the characters as spaces.

## Engine pinned to Windows main e99fe24a: two-level inputs, a frame asked once per loop pass, all 180 recipes — 11 October 2026

The six shared-code differences the Mac's real runs found are changed on Windows (kappa-screen.R binds responsesCrosstab; logistic-regression.R binds its inputs by name and the rest list leaves the bag's frames out when the run asked for frames of its own; a recipe that names every input it takes leaves the run's other inputs out, which covers a prediction's own grid; crosstabs.R scores its classifiers, numbers as numbers else the levels in order; OperationRun.Note keeps a parameter asked in each pass of a loop once per pass with that pass's value, the processor keeping a stack of loop passes, and the record writes the input's own value and holds the kept values of repeated pointer frames under keys `name`, `name#2`… named by the input's `held`). The record takes a two-level input: `"kind": "frame2d"` with `value.frames`, an array per block or group of its columns, and the grouped covariance's data as `"kind": "covariance"` in the same shape (each group's predictor levels first, then the outcome's replicates at each level) with its grid-asked confidence as the setting `ci`; a recipe binds either with `# nested: var = input` and gets a list of lists. With the recipes for ReplicateTwoWay, TwoWayNested and GroupedCovariance every analysis whose help shows the method in R has a script: 180 operations in 158 files, with 360 example files; the README's count is 180.

The Mac's part: `RunRecordR.requests` reads a pointer frame unless its values are kept under the input's own name or the key its `held` names, so a frame asked in several passes gives several requests of one name in the record's order, and `RScriptIO` keeps the host's frames as a queue per name, each of the writer's reads taking the next (before, a dictionary by name gave every pass the last frame's values). `Tests/test_run_record.py` follows the Windows checks as extended (TwoLevel.cs, RealRuns.cs with seven real runs, Script.cs over nested bindings): the nested header and the two-level kinds in the rendering of the writer's rules (a recipe naming every input it takes, the rest list without the bag's frames, a nested list of lists with the inner vectors named by their titles) and in the harness records; the binding check over `# nested:` and the grouped covariance's `ci`; the three two-level analyses run through the Mac's own prompts (the layout question, the number of groups or repeats, one grid per group or per repeat with subjects in rows and treatments in columns, the covariance's predictor series then each group's replicates per X level) with their records' frames checked against the examples; two inputs of one name over the threshold supplied as two frames in order, each read with its own values and no NOTE; MiscRelRisk compared as the Windows check does, every figure printed among the help's; and no expected real-run difference remains.

Results on this Mac: 55 checks; 180 of 180 recipes written exactly as the writer's rules give and agreeing with the help; 164 real runs complete (method comparison regression still deferred), 145 leaving a record, all 145 scripts written as the rules give and all 145 agreeing with the help; the 12 follow-ons from a real parent with 34 inherited frames. The desktop help was re-imported from the same Windows commit in a commit of its own (982 files, the R script window's own topic among them; `Tests/test_desktop_help.py` passes: 167 context IDs and the menu links resolve).

## Method comparison regression through R; the control-character refusal removed — 11 October 2026

The last R-based deferral goes: MethodComparisonRegression (Deming and Passing-Bablok regression through the mcr package) runs on the Mac as LOESS does, through the engine's R step. The operation's own script installs mcr into the program's R library when it is missing, as on Windows; its charts come back as inline SVG through the svglite shim, the test against reference plot square (six by six inches, 432 by 432 points) and the others wider (432 by 288). The definition's precondition asks `RController.PreferredRVersion()` for the installed R's major version; the Mac controller answers it from Rscript itself (`cat(R.version$major, R.version$minor)`), read once per Rscript path, null when R is not installed (the dialog then shows the definition's own message about R 3.0.0). The menu entry loses its `unavailable` text, so every operation of the menu is hosted (test_menu: 208 input hosts, nothing deferred); the help replay's deferral line goes as dead code (the page's example carries no figures for the replay to match, so the replay never reached it).

`Tests/test_r_operations.py` runs the help's example (Plasma against Serum Creatinine, 108 pairs of the Agreement worksheet) with Deming jackknife intervals and the two charts: the report shows the help's figures (slope 1.054539, SE 0.024883, 1.005207 to 1.103872; intercept -0.058913, SE 0.034375, -0.127066 to 0.009239), the same as R called directly through the package on the same data to six places; the script is shown; the record carries the two frames, the settings and the recipe flag. The form's defaults (Deming jackknife and Passing-Bablok bootstrap, the test against reference plot each) run twice, the second from the first's seed, and give the same report. The run-record harness no longer defers the operation: its real run through the Mac's prompts agrees with the help. The R-operations test shares the program's R library (a symlink from its temporary STATSDIRECT_R_FOLDER) so that svglite and mcr are not downloaded again on a machine that has run the program.

On Iain's instruction the Mac-only refusal of a run record holding a control character in any string or key is removed (`RunRecordR.validated`, `ReportRHost`): the shared writer makes each one a space in its comment lines (`Plain`), escapes it in its string literals (`Quote`) and admits only letters and digits into variable names (`SafeName`), so a record from a file with a line break in its title validates as written and a live one is scripted with the break as a space, the head one comment. One character stays refused: U+0000, which R cannot hold in a string at all (the writer's `Quote` writes it as `\u0000`, which R's parser rejects with "nul character not allowed", stopping the whole script before any line runs), raised with Windows for the writer to make a space as `Plain` does. The native check (report-export-driver, section 8) asserts the neutralisation, the NUL refusal from a file and for a live record, and keeps the refusals of a record without a timestamp. The adversarial review of the change set (23 agents) also found that the script shown with a method comparison result set its working directory to the run folder the Mac deletes after the run, so a user running the shown script stopped at `setwd`: the head now creates the folder it names, and the R-operations test runs the shown script through Rscript.

## Engine pinned to Windows main 9562045a: a column that moved along the sheet is found again; every follow-on's recipe; the report's find bar; no NUL refusal — 11 October 2026

The record's pointers go stale when an analysis writes its result columns to the left of its data, or a column is inserted or removed by hand, because the record is written at the report step before such output (Iain's first question about the record). Windows fixed it in the reader rather than the record: `ColumnLocator.Find` looks for the column by its hash, and by its title when it has one, first at the recorded place and then one column at a time to the right and the left within 64; `FrameReader` reads single columns at the candidate places when a column's hash no longer matches, sets the pointer's column to the new place (so the script's "column n" comment is right) and marks the values moved; the writer adds "NOTE: "title" has moved along the sheet since the analysis ran, by columns inserted or removed to its left; its values are as they were", and only a column whose values really changed is reported changed.

The Mac mirrors the reader in two calls of the script entry (FullEngine/RScriptIO.cs, Sources/ReportRHost.swift): the engine's read of a frame looks for a column whose hash no longer matches among the candidate columns the host supplied with the frame (`candidates`, each a single column over the recorded rows with the sheet's own title), through the shared locator; when the frame carries none, the reply's `relocate` names each such column by the frame's index, its place within the frame, its recorded column and rows; the Mac then reads the band either side of each (as many columns as the cell limit allows, from the open grid or the workbook file, the title row read as the title when the pointer has one) and calls again. The status line counts the columns found again beside those changed. The locator's cases of tests/RScript/Relocate.cs run through the entry in `Tests/test_run_record.py` (the first call naming the stale columns; a column inserted to the left, both columns found one to the right with their new places and their values; columns removed to the left found to the left; changed values found nowhere and noted as changed, the same values under another title not taken; a column beyond the reach; without a title the hash alone; without a hash the recorded place kept), and the native driver (report-export-driver, section 3b) inserts a column to the left of a typed worksheet's data and gets both columns found again, noted as moved with their new places and the values as they were, the status saying so.

Windows took the Mac's NUL finding into the shared writer (b4737a6b: `Quote` writes U+0000 as a space, as `Plain` gives a comment line, so a title, a value or a setting holding one no longer stops R's parser; tests/RScript/Script.cs checks it), and the Mac's NUL-only refusal goes with it: a record with a NUL validates as written and a live one is scripted with the NUL as a space, which the native check asserts.

At 9562045a every operation that continues one with a recipe (its prerequisite operation, or the root of a chain of them) takes the root's recipe with `inherits = root`: 47 more (the logistic, Cox, Poisson, simple linear and linearized-estimates follow-ons, one way's multiple comparisons, PCR, probit and the rest), 227 operations in the manifest with their roots' examples, and the record's inherited-frames loop writes an inherited two-level frame (`frame2d`, inherited true), which TwoWayNestedMeans needs; Iain had found that Continue in R on a logistic follow-on gave the data alone. The Mac harness takes the manifest's `inherits` as it is, so its follow-on stage now runs all 59 inheriting operations from a real parent, accepts an inherited two-level frame against the parent's, and requires every follow-on of a recipe'd parent to have a recipe, as tests/RScript/Script.cs does.

A pictured tour of the app, `Scripts/app-tour.sh` with `Tests/app-tour-driver.swift`, builds a test copy of the app whose main program opens the example workbook, runs a paired t test through its form, continues it in R, opens the help and calculator panes and the learning window, and saves PNGs of the window pictured from inside the app (an app may always picture its own windows; a screen recording permission is not needed), for a look at the app from a session without one.

The shared report view on Windows gained find and replace for its find bar (window.find round to the start; insertText on a selected match that is the term; every match replaced from the start, counted); the Mac report window gets the same bar (Sources/ReportFind.swift: Edit > Find, Find Next and Previous, Replace, Replace All, Match case) with the same page calls, and the beta driver checks the seven behaviours of tests/WebReports/FindReplace.cs against it.

## Engine pinned to Windows main 449b1adf: recipes install the packages they load; Open in R — 11 October 2026

Windows's recipes now install a package before loading it when it is missing (`if (!requireNamespace("x", quietly = TRUE)) install.packages("x", repos = "https://cloud.r-project.org")` before each `library(x)`; the six survival recipes, the Gini bootstrap's boot and the method comparison's mcr), with the same line in the help's R code for those topics; the manifest is unchanged. The Mac takes the eight recipes and the examples as they are and adds the rule to its header check: every `library()` in a recipe has the guard. The help bundle is re-imported from the same commit (the R script window's topic now describes Run, the session look and Open in R; 982 files).

The Windows script window gained "Open in R": the script saved as an R file named after the window in the user's StatsDirect/R folder and opened in RStudio when installed, else in R's own window. The Mac's R pane gets the same button beside Save script: the script is saved as "<window title>.R" in the program's R Scripts folder (Application Support/StatsDirect Viewer/R Scripts) and opened in RStudio (org.rstudio.RStudio) when installed, else in R.app (org.R-project.R), else in whatever opens R files; the state line says which. The Windows window's output pane now reads as an R session (each command after its prompt with its output under it); the Mac pane has shown the session that way since it began (session.R sources the script with echo and print.eval). The beta driver checks that Open in R saves the file under the expected name with the script's text (the opening of an application is left out of the headless run).

## Engine pinned to the Windows release v5.1.0 (84706e46) — 11 October 2026

StatsDirect 5.1.0 for Windows is released (tag v5.1.0 = 84706e46 on main; the GitHub release published, the installer on the website). The tagged commit is the changelog on top of 449b1adf and a Windows-only help-check change, so nothing in the engine, the recipes or the help bundle moved since the previous pin; the Mac's pin moves to the release commit so that `Content/engine-info.json` names the released engine (5.1.0 at 84706e46), with the manifest regenerated (872 files) and the suites run again on the build.

## Engine pinned to Windows main 3cc4cbc9: the recipes take the run's options and confidence level; a skipped setting is NULL — 11 October 2026

A reviewer of the 5.1.0 scripts found that the recipes had been written for the help's examples and ignored the options a run had set: a multiple linear regression's script fitted an intercept and ignored the weights whatever the run's options, a logistic regression's assumed three predictors, an intercept, grouped counts and a 95% interval, a Poisson regression's eleven predictors and an exposure, a polynomial regression's degree 2, a Cox regression's no strata and the first predictor alone, a log-rank's the help's own stratified example, and so on through 34 recipes; on a recheck, intervals fixed at 95% where the run's level should rule. Windows rewrote them (1c6520d1, a97c4e89): every recipe binds the run's options in its header (`# settings:` lines) and takes the run's numbers of predictors, series and groups, with individual logistic responses merged by covariate pattern as the report does, the Cox model stratified as the run was, the log-rank's stratified test on the run's strata with the run's weighting method, the kappa's table of weights as given, the Gini's frequency weights, the effect size's type, the logit's and probit's log doses and centile, the meta-analyses' types and standard errors, the 2 by 2's study type and exact test, the LOESS formula over the run's predictors, the method comparison's regressions and seed, principal components of the covariance matrix through a new pca-covariance.R, and every interval at the run's confidence level (Poisson confint, the conditional logistic summary by column position with backticked titles, the exact limits of the log-rank, rate and diagnostic analyses, the non-central limits of the inconsistency, the life table's Monte Carlo quantiles, the agreement's F quantile, the slope's and the Mann-Whitney difference's limits); the help's own data and sizes left in some scripts (Brown's G of the help's births, the z test's first and last 50, the agreement's three dimensions, the normal plot's four values of 75) are cut; and the Mac takes the eleven more recipes of 9af538cb and 3cc4cbc9 with the rest. The writer (ab79862d) writes a bound setting the run skipped, or was not asked for, as `x <- NULL   # the run had no x` rather than leaving it out (the script stopped on the missing name), and a list as `list(...)`; the record keeps a pick from a list (the agreement's reference observer) as a JSON array of booleans. The Windows R runner now gives each run of a script files of its own (0f9b04c5): the Mac pane has always run each script from its own session folder and a file of its own, so there is nothing to mirror there.

The Mac takes the recipes, the manifest (227 operations, 158 files) and the regenerated examples as they are, and the shared writer and record compile into its engine unchanged. `Tests/test_run_record.py` mirrors the writer's new settings rule in its independent rendering (a setting held as null or a list written as its literal; one absent written as NULL with the note); its real runs answer a setting given as null by skipping the optional prompt, as a Windows run without it (MiscRelRisk's population proportion exposed, so that its record has none and its script says so), a list of options as the form sends them (the method comparison's regressions as flags, a pick from a list as indices); and the record check passes over an optional input the example leaves out and the settings the dialog asks only on another branch (the Fisher test of a cohort study, the control responders when there are controls) or never (the normal plot's score method, held by the chart options; the method comparison's regressions, recorded as a boolean each). The harness gains the Windows checks of tests/RScript/Options.cs, Options2.cs and Options3.cs: 40 runs through the Mac's own prompts with the options, sizes and confidence levels the help's examples do not have (a weighted regression without an intercept; individual logistic responses with one predictor and a 99% interval, grouped counts without an intercept and with prior weights; Poisson counts alone and with an exposure and prior weights, at 95% and 99%; a cubic; a stratified Cox model; a conditional logistic regression of ten pairs, at 95% and at 99% with a predictor titled with a space; a stratified log-rank test with the Gehan-Breslow weight; quadratic and user-weighted kappa; the Gini coefficient of frequency-weighted values; the weighted mean difference, effect sizes given and the exact and inconsistency limits at 90%; the z test with the population standard deviation; principal components of five items, of the correlation and of the covariance matrix; the logit on log doses with centile 80; relative risks with standard errors; proportions by Miller's inverse and each study's exact limits at 90%; a cohort 2 by 2 without the exact test; a crossover with baselines; a time series with a zero at time 0; the number needed to treat at an expected risk; the attributable risk with and without the proportion exposed; a reference range of 250 values with the conservative limits; an abridged life table with utility weights; the universal agreement coefficient with observer 2 as the reference; the slope, the Mann-Whitney difference, the diagnostic test's exact odds ratio, three raters' intraclass correlation, the pooled rate ratio's exact limits and the Mantel-Haenszel inconsistency at 90%), each run's script written by the engine and run in R, and the figures R prints compared with the engine's scalar outputs or with the report's own lines where the figure sits in a table (coefficients, odds ratios, eigenvalues, a subject's area under the curve, a study's limits); the bar chart of four series, the box plot of three groups and the records Windows builds by hand (LOESS over two predictors, the method comparison's Deming line with Wald limits, the linearized estimates' model, the normal plot's score method, the summary's two centiles) are built from examples as Recipes.cs builds them and their scripts run. Two differences of route from the Windows checks: a run that compares a confidence level asks it (the analysis preference "use the default confidence interval" off), and the dialog, as on Windows, offers to treat an integer predictor of 3 to 11 distinct values as categories, which the Windows checks' hand-built frames never meet; the Mac check answers "treat as a continuous variable" to run the same model. The meta-analyses' exact methods are a preference of the program on both sides (the Windows checking host's MetaExact; the Mac's `meta-exact` analysis preference), on where the exact limits are compared.

The Mac's real runs at 2570f206 found two of the new recipes binding a setting no dialog run records, on Windows as on the Mac: the method comparison's `methods` (the dialog records each regression as its own boolean, never the list, so the script's methods was NULL and `fits[[1]]` stopped) and the normal plot's score method (a chart option, never in the bag, so `switch(as.character(NULL))` stopped). Windows changed both at 3cc4cbc9 (5f960c38): the method comparison recipe binds the nine option booleans as the dialog records them and takes the ticked ones, and the normal plot's preamble sets the van der Waerden default with a note that the run does not record the score method; its header check now reads each definition without its XML comments (a parameter commented out is asked of no run) and admits the options of a set of options as recordable settings, which the Mac's header check mirrors, and its Options2.cs runs both operations through the engine, as the Mac stage does (the regressions answered as the nine booleans, the normal plot with no setting). The real-run stage keeps one expected difference, the 2 by 2: the help's example takes the Fisher test, which the dialog asks only for a cohort or neither study, so a case-control run's script prints no Fisher P, as the engine's report for that run. The agreement analysis offers its exact P simulation only when no observer is marked as the reference, and the regenerated example marks observer 1, so the follow-on stage runs that parent without the mark.

Suites at this pin: test.sh 486 checks, the report export suite 44, the beta check 61, all exit 0; the run-record harness 113 checks (227 of 227 recipes agree with the help; 165 real runs, 145 of 146 recorded runs' scripts agreeing with the help with the one listed; 59 follow-ons).

## Engine pinned to the Windows release v5.1.1 (ca768f1e) — 11 October 2026

StatsDirect 5.1.1 for Windows is released (tag v5.1.1 = ca768f1e on main; the GitHub release published as Latest; the signed build passed the Windows release run). The tagged commit is the version number and the changelog on top of 3cc4cbc9 (the fifteen Continue in R entries closed as 5.1.1), so nothing in the engine, the recipes, the manifest or the help bundle moved since the previous pin; the Mac's pin moves to the release commit so that `Content/engine-info.json` names the released engine (5.1.1 at ca768f1e), with the manifest regenerated (872 files) and the suites run again on the build: test.sh 486 checks, the report export suite 44, the beta check 61, all exit 0. Codex merged its AI dock and combined-form work into main (2de31e4) while this pin was being checked; rebased on that merge, test.sh gives 554 and the report export suite 45, exit 0, and the beta check was intermittent in two checks the merge brought (3 of 5 runs failed): the write-back driver's selection of the dose column by synthetic mouse events on the grid canvas, which the grid can take before its pointer handling is attached, and the report driver's read of the toolbar width field in the same turn as the click that selects a chart, before the toolbar follows the selection. Neither touches the engine pin or the product; both drivers now wait for what they read (the header click repeated until the grid shows the selection; the width field read until it is enabled), and the beta check passes at 62.

## Engine pinned to Windows main 99493c03: the toolbar's R button; help re-imported — 11 October 2026

On Iain's ask, Windows added an R button to the main toolbar after the Help icon, shown while a report is active (a5e54cc5): it continues in R the result the cursor or selection is in, else the latest result that has a record of its run, as the right-click menu's Continue in R continues the result under the pointer; a report with no recorded result says so in its status line ("No result to continue in R: run an analysis into this report first."); the editor host answers a `currentTarget` request with the result, how it was picked (selection, latest or none) and whether it has a record, so that a text entry the cursor is in is reported as such rather than another result's script opened. tests/WebReports/CurrentResult.cs checks the pick (the latest with a record and not the last entry; the selected result; a note without a record reported as such; none in an empty report); the help bundle's R script window topic names the button (99493c03). No engine, recipe, manifest or record change.

The Mac's report page already carries a Help and an R button in its format row (Codex's Content/Mac/report-host.js, 2de31e4), which followed the entry the cursor was last in and were disabled when that entry had nothing. Under the rule that the Mac's report functions keep parity with Windows's, the R button now picks its result as the Windows button does: the entry the selection or focus is in now (reported even without a record, so that the click says "<title> has no record of its run to continue in R"), else the latest entry that has a record, else nothing, when the click puts the Windows status line text in the Mac's; the button carries the Windows tooltip ("Continue in R: the result the cursor is in, or the latest result, as an R script", or "Open Data and Settings in R: …" for a result without a recipe) and reports its pick in `data-how` and `data-target` for the checks. The Help button keeps its contextual rule (the entry the cursor was last in, disabled when it has no help page). The report driver's Mac controls check now walks the CurrentResult.cs cases: no recorded result (none, the status line); the selected result; the text entry the cursor is in (selection, no record, the status line); the cursor in no entry with a note appended after the recorded result (latest, not last). The help bundle is re-imported from 99493c03 (982 files).

Suites at this pin: test.sh 554 checks, the report export suite 45, the beta check 62, all exit 0.

## Engine pinned to the re-released Windows v5.1.1 (575d7e58) — 11 October 2026

Windows rebuilt 5.1.1 from the head with the toolbar's R button and re-released it: the tag v5.1.1 moved to 575d7e58 (the changelog commit on 99493c03, which folds the button's entry into the 5.1.1 section; the GitHub release's notes replaced, the version string unchanged). Nothing in the engine, the recipes, the manifest, the record or the help bundle moved since the previous pin; the Mac's pin moves to the release commit so that `Content/engine-info.json` names the released engine (5.1.1 at 575d7e58), with the manifest regenerated (872 files) and the suites run again on the build: test.sh 554 checks, the report export suite 45, the beta check 62, all exit 0.
## 2026-10-12 — Startup, recent documents and R setup alignment

The local review build `.build/cross-platform-final/StatsDirect.app` opens directly into a
worksheet. Finder/Open With and File/Open share the import path; an early open event
waits for window construction. A successful import replaces only the untouched
startup sheet. An edited sheet or failed import preserves open work. File/Open
Recent uses the system recent list, records successful open/save operations and
excludes bundled examples. Alternate document associations preserve user defaults.

Open in R now uses the guided installer when R is missing, then resumes the requested
action with the current script. Reset clears pending external-open intent. Native
injected tests cover download failure/retry, incomplete installation, postponement,
active download cancellation, repeated Run resuming once, and reset before a later
Run. No actual installer is executed. Separate package/download checks pass runtime
detection, checksum/signature/URL validation and six HTTP/cancellation cleanup cases.

`Scripts/test-startup-r-setup.sh` passes its native checks, and its Launch Services
launch opens the actual requested file without executing the script. The broader
acceptance pass also passes learning workspace/provider/course packs, script AI,
paired t/agreement, actual R output and external startup, all 101 parent/follow-on
paths (67 operations), report editing/clipboard/HTML/PDF/DOCX (49 PASS groups), and
unified toolbars (20 PASS groups). Learning JavaScript: 27 passing tests. AI tests use
the local mock transport; no live model request or email is sent.

The final learning-workspace run also checks that tutor-generated paired/agreement
reports retain each engine heading once and use the same Creole colours as
menu-generated reports. The native tutor host no longer prepends a duplicate title.

Release compilation, 1,552 distribution checks, matching debug symbols and strict
deep signature verification pass. Logs are `.build/parity-*.log` and
`.build/startup-r-setup-checks.log`. Shared editor and engine source are unchanged.
This is an unreleased local review build; see
`Docs/cross-platform-acceptance-2026-10-12.md` for cross-platform scope and limits.

## Script AI reading during streaming — 12 October 2026

The native conversation updates only the changed attributed-text suffix. It keeps
the current selection and viewport, follows new output only when already at the
bottom with no selection, and ignores identical completion updates. New or changed
conversations reset independently. Sharing and request handling are unchanged.

`Scripts/test-script-ai.sh` passes all 44 native checks using the local mock
transport. Seven streaming checks cover following a growing reply, reading earlier
text without a selection, selecting and copying Unicode text, suppressing following
while selecting, resuming at the bottom, and retaining position and code formatting
at completion. The keyboard fixture posts Command-Return through the application
event queue so it reaches the existing local key monitor.

Release build, matching symbols and strict deep signature verification pass for
`.build/ai-stable-reading/StatsDirect.app`. Logs: `.build/script-ai-streaming-checks.log`
and `.build/ai-stable-reading-build.log`. Mac-only host/test changes; no engine or
shared editor changes, live AI requests, commit, push or release.

## Script AI layout and Help ordering — 12 October 2026

Sharing controls now precede Your question, its composer and Send/Stop; Conversation
and its history follow. In short docks the upper controls scroll while history
retains a 100-point minimum. Confirmation still collapses sharing, focuses the
composer and clears a stale confirmation reminder. Each subsequent shared question
still requires consent. The Script toolbar remains AI followed by text-only Open in R.
Example workbook is the final Help menu item, using its existing command.

All 54 checks in `Scripts/test-script-ai.sh` pass. These include expanded/collapsed
order, short-dock access, drafts across script switches and dock reopening, consent,
keyboard sending, cancellation, stable streamed selection/copy/reading and pane
geometry, plus invoking the final Help item and reading the bundled PEFR workbook.
Expanded, confirmed and short-dock captures were visually checked under
`.build/script-ai-layout-output/`. No Auto Layout constraint warnings were logged.

The review build is `.build/ai-layout-final/StatsDirect.app`; logs are
`.build/ai-layout-checks.log` and `.build/ai-layout-final-build.log`. Release compilation,
matching symbols and strict deep signature verification pass. No engine/shared-editor
changes or live AI requests; nothing committed, pushed or published.

Subsequent toolbar correction: the Script window now uses an R+ icon immediately
after AI for its existing Open in R action. The accessible name and overflow-menu
label remain Open in R. The native icon was visually checked; all 53 R integration
checks and the Release build pass (`r-plus-toolbar-checks.log`,
`r-plus-toolbar-build.log`). Review build: `.build/r-plus-toolbar/StatsDirect.app`;
strict deep signature verification passes. This is a Mac-only icon/host change.

Subsequent menu correction: Window now precedes Help in both the macOS menu bar
and the in-window menu row. Within Help, Example workbook has its own section
before the update commands, and About StatsDirect is last. This supersedes the
earlier Example-workbook-last arrangement above. All 55 native Script AI/layout/menu
checks pass, including invoking Example workbook and checking its PEFR data.
The Release build at `.build/help-menu-final/StatsDirect.app` passes matching-symbol
and strict deep signature verification. Logs: `.build/help-menu-final-checks.log`
and `.build/help-menu-final-build.log`. No engine or shared editor changes.

Script toolbar contrast follow-up: native buttons (including More) explicitly use
the system label tint. Enabled commands no longer use the default muted template
grey; AppKit retains disabled/inactive-state distinctions and dark-mode adaptation.
Light and dark preview renders were visually inspected. All 53 existing R integration
checks pass, including editing, overflow and Open in R. The Release build at
`.build/icon-contrast/StatsDirect.app` passes strict deep signature and matching-symbol
verification. Logs: `.build/icon-contrast-r-checks.log`, `.build/icon-contrast-build.log`.
Only the Mac native toolbar presentation changed; no shared editor or engine changes.

## Chart alignment — 12 October 2026

New Mac report charts default to left alignment. Left/Centre/Right now act on a
single selected chart or picture; text alignment is retained, and mixed selections
do not accidentally target the first chart. The selected alignment survives resize,
Fit, public HTML clipboard/paste, save/reopen and HTML/PDF/DOCX export. The resize
handle follows the free corner, preserving left/right anchors or the centre.
Alignment and resizing use the existing report undo/redo history.

The dedicated `--alignment-only` native checks and the full report suite pass.
Checks include toolbar and native Format commands, pressed/disabled states,
keyboard/toolbar focus, no-op alignment, single-step undo/redo, Escape cancellation,
text and mixed selections, responsive reopening, rendered PDF pixel positions and
actual DOCX drawing paragraphs with SVG/PNG fallbacks. Existing report editing,
transfer/deletion, legacy RTF import, Creole styles, Office numeric clipboard and
real engine/R report checks also pass. All eight Report JavaScript tests pass.

Release build `.build/chart-alignment/StatsDirect.app` passes 1,552 distribution
regressions, matching-symbol verification and strict deep code-signature checks.
Packaged report bundles and Mac report stylesheet match the final source assets.
Logs: `.build/chart-alignment-checks.log`,
`.build/chart-alignment-full-report-checks.log`, `.build/chart-alignment-build.log`.
Rendered PDF and reopened HTML captures are in `.build/report-export-output/`.

This changes the Mac copy of shared `Report/{chart-size,editor,export,fragment,import}.mjs`
and generated report bundles, alongside the Mac-only default stylesheet. Released
Windows and the calculation engine are untouched. No commit, push, publication or
restart of the user's running application was performed.

During the subsequently authorised Windows catch-up, a Windows native regression
found report margins retained on standalone SVG downloads. Both editor copies now
strip only root margin declarations in `exportableSvg`, preserving paint/font
styles and the source. The Mac native alignment suite passes the added assertion
for all three alignments and the existing undo/resize/clipboard/HTML/PDF/DOCX checks;
all eight Report JavaScript checks pass. Log: `.build/chart-alignment-svg-checks.log`.
The refreshed `.build/chart-alignment-svg/StatsDirect.app` contains the same verified
Release binaries with regenerated report assets. Deep/strict signature and matching
debug-symbol checks pass. The user's running application remains unchanged.

The full native report suite also passes after the SVG cleanup, including chart
PNG pixels, editing/transfer/deletion, RTF import, engine/R run records, styles,
Office clipboard and HTML/PDF/DOCX round trips. Evidence:
`.build/chart-alignment-svg-full-report-checks.log`. Packaged editor assets match
the final regenerated bundles.

Pre-commit source handover: rebuilt Grid, Report and Learn assets and confirmed a
second clean rebuild produces identical files. This refreshes the worksheet
bundle's embedded shared AI/R+ icon definitions. All 110 Grid/Report/Learn JavaScript
checks pass (`.build/precommit-js-checks.log`); no application or engine logic changed
after the native acceptance runs above. Commit identity is Iain Buchan
<buchan@liverpool.ac.uk>; source publication is on the development branches without
an installer or application release.

## First-use ChatGPT installation — 12 October 2026

The Mac now downloads the pinned OpenAI app-server only after an explicit
**Use my ChatGPT** selection in Learning or the script AI dock. The setup panel
shows progress, cancellation and retry, then continues the existing browser
sign-in flow. Passive account checks and opening either pane never install it.
Offline lessons remain available. The approximately 94 MB download is installed
under the user's Application Support directory without administrator privileges;
the existing `ChatGPT Tutor` account storage and Keychain identity are retained.

`Content/Tutor/runtime.json` pins version 0.157.1, the official GitHub release,
archive hash, all five payload files and the OpenAI publisher identity. Installation
uses an exclusive cross-process lock, private staging and an atomic directory
exchange when repairing an existing version. Cancellation cleans partial files;
a subsequent attempt removes staging left by a force-quit. Archive/file hashes
and publisher checks precede installation and cached-file startup. The official
licence and notice were compared byte-for-byte with the pinned upstream tag.

Validation performed on Apple Silicon:

- `Scripts/test-tutor-runtime.sh --real-root "$PWD/.build/first-use-real-runtime"`:
  download faults (404, forbidden redirect, corruption, excessive size and
  truncation), cancel/cleanup/retry, lock contention, damaged-file repair, failed
  repair preservation, symlink rejection, stale staging cleanup and offline reuse.
  A fresh real GitHub/CDN download also passed all hashes and publisher checks.
- `Scripts/test-tutor-setup.sh .build/ai-first-use/StatsDirect.app`, with the isolated
  real runtime cache: passive Learning/script opening, explicit setup, duplicate
  suppression, native progress/cancel/retry/close, retained drafts and credentials,
  policy changes, cached setup reaching the normal signed-out connection dialog,
  and absence of bundled AI executables. The panel was visually inspected.
- `Scripts/test-tutor-protocol.sh`: mock sign-in/completion, streaming, host tools,
  cancellation, retry, usage limits, sign-out, disconnect recovery and policy.
- `Tests/probe-chatgpt-runtime.py`: the freshly installed real signed-out runtime
  accepts strict configuration, isolated dynamic tools, thread/turn schemas,
  interrupt and unsubscribe. No live account or model response was used.
- `Scripts/test-script-ai.sh`: existing script AI consent, conversation, toolbar,
  document-scope and cancellation checks pass. All 34 Learning/tutor-data
  JavaScript tests pass.
- `Scripts/test-learning-workspace.sh`: native consent, exact worksheet reads,
  engine-generated results, stale-data rejection and offline policy behaviour pass.
- `Tests/run_beta_feedback.py --privacy-only`: combined native privacy checks
  pass. Its compile list now includes the existing chart-alignment helper, which
  was missing from that harness.
- The full Release build passes, including 1,552 engine distribution checks,
  matching debug symbols and strict deep code-signature verification. Packaged
  runtime metadata/notices match source; no AI runtime binary remains in the app.
  The application is approximately 240 MiB smaller than the preceding local build.

Evidence is in `.build/tutor-runtime-tests.log`, `.build/tutor-setup-tests.log`,
`.build/tutor-protocol-tests.log`, `.build/tutor-runtime-probe.log`,
`.build/first-use-script-ai-tests.log`, `.build/first-use-learning-js-tests.log`
`.build/first-use-learning-workspace-tests.log`, `.build/first-use-privacy-tests.log`
and `.build/ai-first-use-build.log`. The test download and sign-in storage are
isolated from the user's installed application and credentials. The running
application was not restarted. The engine pin and shared report editor are unchanged.

## The report toolbar's R button disables for a note without a record — 12 October 2026

Asked which is the better practice for the toolbar's R button when the cursor is in a note that has no record of a run, disable or notify, Iain chose disable: a toolbar button is scanned rather than read, so its state carries the information, as Bold, the alignment buttons and the Mac's Help button already do for a selection they cannot act on; a message is for a command invoked with intent, the menu or a shortcut. The Mac button now disables when the selected entry has no record and when the report has no recorded result, with the reason in its tooltip ("put the cursor in a result; this text has no record of a run", "run an analysis into this report first"), and still takes the latest result that has a record when the cursor is in no result; the native handler keeps the Windows status line text for a request with no result. The Windows branch already disables; the tooltip wording was sent to the Windows session for its button. The report driver's Mac controls check walks the same four cases with the new states.

## Engine pinned to Windows main 6c3a665f: Codex's Windows work merged; the R button's tooltips — 12 October 2026

On Iain's "merge and push on both", Windows main took Codex's feature/windows-unified-toolbars (ba61512c: one document toolbar per window type with the same order and glyphs as the Mac's, the shared editor copy equal to the Mac's file for file, Learning and the script AI dock, guided R installation) and, after Iain chose disable over notify, the report toolbar's R button disabled on a note without a record and in a report with no recorded result with the reason in its tooltip, in the Mac's wording (106393a9, its four checks 8eb495e9, changelog d8ac722c), then Codex's first-use download of the ChatGPT connection component (6c3a665f). The engine, operations, recipes, manifest, records and help bundle are unchanged from 575d7e58; one new source file, StatsDirectUI/R/RInstallation.cs, is the Windows installer of R (CRAN's download verified by Authenticode through wintrust), which the Mac's engine project leaves out as it leaves out the Windows R controller, the Mac having its own installer. The pin moves so that `Content/engine-info.json` names the head the two sides now share, with the manifest regenerated (873 files).

Suites at this pin: test.sh 556 checks, the report export suite 57, the beta check 72, the unified toolbar suite 20, all exit 0.

## Engine pinned to Windows main 1bf97548: Windows 5.2.0 — 14 October 2026

Windows main moved on 13 October to version 5.2.0 (5cf8689b, changelog 9d62a829) with the Help menu taking the Mac's order (Example workbook before About StatsDirect, which stays last), the Script AI conversation as a page that follows a reply as it arrives, replies read as UTF-8 and a dropped connection that says why, Send reconnecting by itself, Open in R and Open R code replaying the shared source and the earlier R blocks with the worksheet values the tutor read, the conversation view recreated after a renderer crash, the Learning pane keeping a selection and reading position through streamed chunks (the Mac's conversation-view.mjs applied to the vendored lesson app), and Codex's verification of the signed 5.2.0 build. The engine, operations, recipes, manifest, records and help bundle are unchanged from 6c3a665f (the new help topics are written in the help repository and not yet in the Windows bundle); the pin moves so that `Content/engine-info.json` names the head, with the manifest regenerated (873 files). The Mac counterparts of the Script AI and Learning fixes are Codex's two commits on feature/mac-unified-toolbars after the merge, taken next.

Suites at this pin: test.sh 556 checks, the report export suite 57, the beta check 72, all exit 0.

## Engine pinned to Windows main 406d2557: the 5.2 help bundle — 14 October 2026

Iain had the Windows help brought up to the 5.1 and 5.2 features (help source iain-buchan/statisticalhelp master e5ce524; Flare's desktop output committed to the Windows repository at 406d2557, 416 files): new topics for Script AI (the AI assistance button and pane, the user's own ChatGPT account, the first-use download and sign-in, what each Send sends and the per-question sharing behind the no-person-identifiers confirmation, the reply page's Copy, Open in R, Open R code and Stop, the DisableOnlineTutor policy), Learning (the shared lesson library, the tutor and what it is told, document sharing with confirmation, the learning record and its exports, Learning Options) and the Report window (results as items with run records, the toolbar and its overflow, selecting a result, delete and undo, drag moves and copies, the right-click menu with Continue in R and Save chart as SVG or PNG, chart alignment and resizing, copying into Office, Save As HTML, Export to Word or PDF, the find bar); the Example topic rewritten as Help > Example workbook; the Help, Tools and About menu topics and the seventeen old report topics rewritten; Exporting graphics become Saving a chart; the licence topic listing WebView2, the editor's and lesson library's packages, PdfPig and OpenAI's Codex app server; and Data/Alias.xml carrying SCRIPT_AI 1402, LEARNING 1403, EXAMPLE_WORKBOOK 1404 and REPORT_WINDOW 1405. The Mac re-imports the bundle (987 files) and moves the pin; the engine, recipes and manifest are unchanged from 1bf97548. Neither program yet asks for the four new aliases from its Learning and Script AI panes; that follows Iain's word on both.

Suites at this pin: test.sh 556 checks, the report export suite 57, the beta check 72, all exit 0.

## After Codex's merge of the Mac AI and Learning fixes: the drivers follow, and the marked notice — 14 October 2026

Codex merged its two commits (69e5f78, 0a112bae: the Mac counterparts of the Windows 5.2 Script AI and Learning fixes, with the eight lines the tutor's script instructions gained on Windows, Sources/ConversationRScript.swift, the recovery of a failed conversation view and a selection kept while a reply streams) into main itself (cbccc10, on 622c6d3). Three things follow here. A lesson's R block now opens in R as a reviewable replay (a header saying nothing has been run, the block under its label, the shared source and earlier blocks before it when there are any), as the Windows script window's Open R code does, so the beta check expects the replay in the pane and in the file Open in R saves, rather than the bare block. The R integration suite writes its picture of the narrow script window into the folder the unified toolbar suite makes, and failed when run on its own; it makes the folder itself now. And the Learn bundle contains marked 4.3.0, imported by Learn/rich-text.mjs from the Grid package's modules, which the notice generator in Learn/build.mjs did not list (the Windows session noticed in its vendored copy); the generator reads marked's notice from there and Content/Learn/THIRD-PARTY-LICENSES.txt carries it. The script AI suite's Command-Return check timed out twice on Codex's tip and once on the merge and then passed twice unchanged, a focus-timing flake to watch; the driver now prints the pane's state when that wait times out.

Suites on main cbccc10 with the help pin and these changes: test.sh 556, report export 57, beta 74, unified toolbar 20, R integration 53, startup and R setup 29, script AI 62, learning recovery 5, conversation R 16, all exit 0.

## 14 October 2026 — Mac parity closure (source update; no installer)

After incorporating Mac commits `497760a` and `5a20b86`, the engine pin and Help
manifest identify `406d2557` (5.2.0). All 873 engine and 987 Help file hashes match
the initially tested `1bf97548` / `76911c12` sources. Shared calculation and
report-editor sources are unchanged; the incoming harness fixes and marked licence
notice are retained.
The build remains version 0.3.29; no installer or GitHub release is created here.

- `.build/parity-final-core.log`: full engine/R/form suite passed; 208 menu methods,
  all 67 follow-ons, 227 R recipe comparisons and 115 JavaScript tests (zero skips).
  Build also passes all 1,552 distribution checks.
- `.build/parity-mac-parity-retest.log`: native TXT import with literal HTML-looking
  text/UTF-16; TSV File/Open and export; worksheet PDF from actual selected cells;
  repeat mode clearing old selection, pausing for new data, a second paired/agreement
  result on edited data and cancellation; native C#/VB Run, language/save-extension
  changes, no execution on File/Open, script printing and XLS data export.
- `.build/parity-managed-final.log`: real shared Roslyn/engine execution for C# and
  VB; interactive host prompt/report; compile/runtime errors, cooperative cancellation
  and independent console capture for two scripts suspended at different prompts.
- `.build/parity-xls-final.log`: xlrd independently reads genuine BIFF8 values, types,
  dates, multiple worksheets, literal formula-like text and final valid row/column;
  invalid dimensions/text lengths leave the existing destination byte-for-byte intact.
- `.build/parity-excel{,_edges,_compatibility,_inserts,_structures}.log`: all existing
  workbook suites passed, including preservation and streaming insertion of 1,000,010
  cells; failures keep destination/source packages unchanged.
- `.build/parity-data-files-final.log`: native Swift file I/O → real JS grid model →
  native export → base R `identical()` round trips. Added Date/POSIXct NaN, NA,
  fractional Date and sub-microsecond timestamps/timezone. The new fixture failed
  before the coordinated R protocol patch and passes afterward; existing corruption,
  factors, row names, literal text and atomic-failure checks pass too.
- `.build/parity-report-ai.log` (47 PASS groups), `.build/parity-script-ai.log`
  (65) and `.build/parity-help-pane.log` (48) pass with real WKWebViews and controlled
  provider fixtures. `.build/parity-sharing.log` checks consent session/reset rules.
  Help asset validation checks all 987 file hashes, 808 aliases and 167 context IDs.

The R exchange fix is coordinated with Windows: explicitly represent Date/POSIXct
NaN as text because the raw numeric channel uses NaN for absence; only the explicit
NaN representation bypasses missing-value validation. No file protocol change.
Windows separately reports its native Learning/AI/file, report, shell and Help
checks passing. This is remote evidence, not execution on this Mac.

Explicit limits: XLS export is a values/types data copy, not rich XLS editing; SDW
conversion requires StatsDirect 2 on Windows. Printing asks for a smaller selection
above 250,000 cells. C#/VB cancellation is cooperative at engine checkpoints. Live
account sign-in and final signed/clean-machine installer acceptance remain release
checks; neither mocks nor this source update claim to replace those checks.

Additional fresh native evidence:

- `.build/parity-fresh-grid-selection.log`: 18 whole-column/cell drag checks,
  including modifiers, resize edges, blur cancellation, horizontal scrolling and
  Excel-sized dimensions.
- `.build/parity-fresh-paired-workflow.log`: one heading drag, automatic selected
  inputs, one Run, nine-pair agreement SVG and Windows-equivalent figures, active
  report reuse, wider/one-column selections, cancellation and confidence settings.
  The harness no longer waits indefinitely on requestAnimationFrame: WebKit can
  suspend it in an automated app even when the native frame is visible. It settles
  React/DOM layout before dispatching the same synthetic mouse gestures. No product
  grid behaviour was changed for this harness correction.
- `.build/parity-fresh-follow-on-workflow.log`: all 67 follow-on operations through
  101 native parent/child paths; one active report, inherited Help, original
  worksheet/range output after changing the active sheet and workbook.
- `.build/parity-fresh-conversation-r.log`: 15 checks, including six fresh real-R
  executions; original data, earlier code, selection and excluded non-R fences.

Integrated source checks after the two incoming Mac commits:

- `.build/parity-integrated-build.log`: clean Release development build; 1,552
  distribution checks and matching native symbol UUIDs. Strict deep signature
  verification passes; all 1,270 packaged Content files match current source.
  This is an isolated `.app`, not an installer or published release.
- `.build/parity-integrated-core.log`: full engine, R, form, recipe and browser
  model suite exits 0; 115 JavaScript tests pass without skips.
- `.build/parity-integrated-r-integration.log`: 53 native R checks pass. The new
  language selector sits beside Run, after the seven common editing commands.
- `.build/parity-integrated-unified-toolbar.log`: 20 native toolbar checks pass.
  Worksheet Find now focuses after React mounts its input instead of depending
  on a display-refresh callback after returning from a native sheet. Cut, undo,
  delayed clipboard acknowledgement, overflow and format-aware Save pass too.

The Report context-menu regression expectation includes the new AI Assistance
command; its action and document scope are exercised by the Report AI suite.
The copied R exchange file is identical to Windows `52146ce5` after normalising
line endings, including its explanatory NaN comment.

- `.build/parity-integrated-report-export.log`: all 57 native/export checks pass,
  including legacy RTF/WMF/EMF, editable HTML reopen, actual DOCX package styles,
  PDF pagination, charts, source records, cut/paste/drag, Delete and chronological
  undo, Excel numeric clipboard formats and selected-chart alignment.

- `.build/parity-integrated-startup-r-setup.log`: 29 startup/Finder/recent-file and
  guided R setup checks pass. Opening a script now creates no R process, working
  folder or console output. Run/explicit setup starts R on demand; cancellation,
  retry and resuming the requested action exactly once retain the edited code.
- `.build/parity-integrated-final-build.log`: final clean Release rebuild after
  passive Script opening; matching symbols, strict deep signature verification
  and all 1,270 Content files rechecked against source. No installer was built.

- `.build/parity-integrated-learning-workspace.log`: six native context/consent
  groups pass, including exact PEFR data, engine reports, stale-scope rejection
  and offline institutional policy.
- `.build/parity-integrated-mac-parity.log`: 19 native groups pass, including
  repeat analysis, TXT/TSV, printing, C#/VB execution and correctly named AI
  context that excludes non-R code from R replay, plus XLS data-copy export.
- `.build/parity-integrated-script-ai.log`: 65 native AI/menu groups pass after
  integration, with sharing, HTML conversation selection/streaming, recovery,
  R replay, cancellation, narrow layouts and the matching Help commands.
- The R integration suite also passed again after passive startup. It verifies
  that Reset retains the current R output folder, a later process uses a new
  folder, and copies made before the first Run remain intact.

Windows coordination: main `52146ce5f34b2d3ce54fc84a18819fd150ad0d22` was reported
clean and pushed by the Windows chat, with 822 passing checks and 12 physical
clipboard checks explicitly skipped to preserve existing clipboard contents.
The Mac engine pin retains incoming `406d2557`; calculation sources and the shared
report editor have not changed. No installer, release tag or version bump.

## Engine pinned to Windows main 27a20d8a: Codex's Windows parity work and the tutor texts — 14 October 2026

Windows main took Codex's two commits of 14 October (76911c12: Learning conversations and their R context kept across a browser recovery; 52146ce5: Report AI, offline maths rendering in the conversation page, session-wide sharing consent, the current Learning content and the Help menu order, R and CSV dispatch, typed Excel and R-data imports and a legacy RTF import through new SpreadsheetFiles.cs, LegacyReport.cs and R/RDataFiles.cs, and the R Date and POSIXct NaN fix in the shared data-files.R, coordinated with the Mac's 13ca3d3). The engine, operations, recipes, manifest, records and help bundle are unchanged; the new R/RDataFiles.cs is the Windows reader and writer of the R data-file exchange over SpreadsheetGear and the Windows UI, which the Mac engine project leaves out beside the Windows R controller and installer, the Mac having its own (Sources/RDataFileIO.swift). The shared files compared file for file with the Mac's 13ca3d3: Assets/R/data-files.R, Tutor/instructions.txt and Learn/lessons.json identical; Learn/app.js differing by the Windows build-time adaptations as designed; the Learn licence notice lacking marked until the next Windows sync; and the Tutor's script-instructions.txt and report-instructions.txt saying the same things in different words on the two sides, though the Windows lock vendors the Mac's by hash, settled by Iain as described below and written identically on both sides at Windows 27a20d8a. The pin moves so that `Content/engine-info.json` names that head, with the manifest regenerated (874 files).

Suites at this pin: test.sh 557 checks, the report export suite 57, the beta check 74, all exit 0.

## The tutor's instruction texts: one wording on both sides — 14 October 2026

Codex had rewritten the Windows copies of the tutor's three instruction files (Assets/Tutor/instructions.txt, script-instructions.txt and the new report-instructions.txt) in its own words while the Windows lock vendors the Mac's by hash, so the two sides told the tutor the same things differently. Iain settled it by statistical robustness: the Mac's wording is canonical (pairing by design, non-significance not proof of no effect, a non-significant bias test not establishing agreement, the methods' interval conventions, operational importance, missing design, population or decision context asked for rather than invented, grounding in the supplied results), with two sentences added on both sides: that Open in R includes only R source snapshots and R code blocks and does not translate C# or VB, and that the lessons are original teaching drafts with external subject-expert review pending. The three files are byte-identical on the two sides (LF, no BOM; SHA-256 25b486db…, 2a27b3b3…, 21cec7fb…), the Windows lock's adaptation hashes updated there.

## Engine pinned to Windows main 949419d3: the report AI pane offers the result's workbook — 14 October 2026

Iain found on the installed Windows build that the report's AI pane offered for sharing the workbook last activated, whatever the result came from. Windows (949419d3, ScriptAIPane.cs OfferResultWorkbookAsync and RecordWorkbook; tests/Learning/ReportWorkbook.cs) now has the pane, opened for a report, read the record of the result it was opened on (else the result the cursor is in, else the latest with a record) and select the open workbook the record names, found as Continue in R finds it (the record's input paths and file names, or an unsaved workbook's name, against the open windows); the selection goes through the same path as a choice by hand, so the session's data document follows and the sharing is confirmed again, the status line names the workbook, and a result without a record, or whose workbook is not open, leaves the box as it was. The Mac's pane follows the same rule (Sources/ScriptAIPane.swift offerResultWorkbook): opened for a report from the toolbar's AI button it has the result the page names, from the menu it takes the latest result with a record; the record's inputs and source are matched to the open worksheets by file path and by name, as the R reader does; the match is selected through the viewer's data-document path and the picker, the status line saying "The workbook offered for sharing is the result's: …"; the report AI driver checks a result whose record names an unsaved workbook other than the active one, and a result without a record. The engine, recipes, help bundle and tutor texts are unchanged; the manifest is regenerated (874 files).

Suites at this pin: test.sh 557 checks, the report export suite 57, the beta check 74, all exit 0; the report AI suite passes its first 44 checks here, the three new ones among them, and then waits for its composer to hold key focus, which this session's conditions do not give it (the same wait fails on earlier mains rebuilt in these conditions and passes on Codex's interactive run), so its remaining checks are Codex's and the CI's to confirm.

### R package guidance sync, 14 October 2026

Mirrored the three instruction-file additions from Windows commit
`472be7f287e02407b97e37aedcbe1d48b7be5898` into `Content/Tutor`. The guidance
requires actionable package checks, commented one-time installation with an
explicit HTTPS CRAN repository, Stan/compiler prerequisites, explicit Bayesian
assumptions and printed results/diagnostics. Existing Mac-specific wording is
preserved. Each addition was compared against the source commit; all three are
identical, with 14 added lines per file and no removed lines.

`Scripts/test-tutor-protocol.sh` passes: native protocol framing, controlled tool
calls, cancellation/retry, sign-in/sign-out, private diagnostics and institutional
policy. `git diff --check` passes. These are deterministic checks, not a live-model
compliance test. No packages were installed; no app or installer was rebuilt for
this guidance-only change. The engine/submodule pin is unchanged.
## Engine pinned to Windows main 914d325b: the tutor's prerequisites paragraph; Enter sends in the AI composer — 14 October 2026

Two more Windows commits, shared on Iain's ask. Codex's 472be7f2 adds the same fourteen-line paragraph to the tutor's three instruction texts after an example of Iain's with brms failed for want of the package: prefer base R, assume no package is installed, explain prerequisites before a package-dependent example with a requireNamespace check and an actionable stop, show the one-time install as commented-out code with an explicit HTTPS CRAN repository, note that Open in R includes earlier R blocks so a setup block alone does not prevent execution, that Stan-backed packages such as brms need a Stan backend and a C++ compiler besides the R package, offer a simpler base-R approach where appropriate stating any change in assumptions or priors, state likelihood, priors, difference direction and estimand for Bayesian examples and distinguish posterior estimation from a Bayes-factor test, print the requested estimates and intervals with MCMC diagnostics, and never call a missing-package error a failure of the model. Under the one-canonical-text decision the Mac's Content/Tutor files take the Windows bytes (SHA-256 956e1d82…, bc604375…, fbe790bb…; LF, no BOM), so the Windows lock holds. The Windows session's 914d325b has the AI pane's question box send on Enter, as the ChatGPT prompt does, and add a line on Shift+Enter, the convention the calculator already has, the label reading "Your question (Enter sends; Shift+Enter adds a line)", a send with the connection or sharing not ready doing what pressing Send would; the Mac's composer follows (Sources/ScriptAIPane.swift AIComposerInput, as the calculator's input), Command-Return still sending as before, with a driver check that Return sends and Shift+Return adds a line without the window holding focus. The engine, recipes and help bundle are unchanged; the manifest is regenerated (874 files).

Suites at this pin: test.sh 557 checks, the report export suite 57, the beta check 74, all exit 0; the report AI suite passes its first 46 checks here, the Enter and Shift+Enter ones among them (placed after the first working send, since a later point in the suite deliberately kills the renderer and leaves the connection down), before the composer-focus wait this session's conditions do not satisfy; one run failed its first check at the pane's opening and passed it on the next run unchanged, a transient to watch.

## Windows 5.2.0 released from 914d325b, the Mac's pin — 14 October 2026

StatsDirect 5.2.0 for Windows is released on Iain's word: tag v5.2.0 = 914d325b, the commit the seventh signed build came from and the one the Mac is pinned to (0bb639f), so nothing moves here; `Content/engine-info.json` already names 5.2.0 at 914d325b. The GitHub release carries the changelog's seventeen entries with a short section for the Report AI, the offline maths and session consent, and the file formats, and the hashes of its three files (StatsDirectSetup.exe 299,044,640 bytes, SHA-256 81190261…; StatsDirect-x64.msi 24,633,344 bytes, 6C937D40…; StatsDirect-5.2.0-WebHelp.zip 7,611,775 bytes, 7A134D99…); the website's Specifications page and the web help with the Script AI, Learning and Report window topics are live. The Mac's own 1.0 follows this week's work and Iain's Developer ID for signing and notarization.


## Mac CI and Report AI focus — 15 October 2026

Preserved incoming Mac commits `0bb639f` and `89a3d20`; the Windows engine remains
pinned to `914d325b`. No calculation sources, shared report-editor files, Windows
files, installer, release tag or version number changed.

The hosted Learning failure was reproduced locally with a 30-pixel conversation
viewport: padding occupied the whole area, and WebKit returned empty selected
text even though the DOM endpoints existed. The chat now reserves 130 pixels for
messages, includes the controls in its minimum height, and uses size containment
so long replies scroll within that viewport. The surrounding page can scroll in
a short window. The native fixture runs at 850 × 520 and checks the actual initial
selected words, streaming, backward endpoints, scrolling and completion. It no
longer lets two empty selections count as a successful preservation check.

AI command ownership now follows the document window's first responder rather
than requiring global key-window status. Composer focus is set after layout and
its selected text is scrolled into view. An attached sheet blocks dock commands;
the Command-Return monitor accepts only events addressed to the document window.
The Report AI regression explicitly removes key-window status, verifies that
Replace cannot target the report, opens/closes a sheet, restores composer focus,
and closes the dock without closing the report. Enter and Shift+Enter remain
covered. The CI-only optional-to-Any warning in report R source relocation is
removed by giving the column title an explicit String type.

The repeat-analysis test had waited only for a `.selection` element that was
already present in the empty chooser. It now waits for the actual selected
column names after the asynchronous worksheet refresh, uses a real heading drag,
and verifies the second run's mean changes from 56.111111 to 57.222222 after
editing the data. Named waits identify the failed stage rather than timing out
without context.

Local validation:

- `.build/ci-fix-build.log`: clean Release development app, no warnings; 1,552
  distribution checks, matching debug symbols and strict deep signature check.
  All 1,270 packaged Content files match source.
- `.build/ci-fix-full-tests.log`: full engine, form, follow-on, R recipe and
  JavaScript suite exits 0; 115 JavaScript tests pass without skips.
- `.build/ci-fix-report-ai-final.log`: complete native Report AI suite, including
  source-workbook matching, rich HTML, consent, focus loss, sheets and shortcuts.
- `.build/ci-fix-script-ai.log`: complete native Script AI and consent suite,
  including actual Command-Return dispatch, streaming selection and R replay.
- `.build/ci-fix-mac-parity-final.log`: all 19 native parity checks pass, including
  repeat analysis with the changed numerical result, cancellation, printing,
  C#/VB scripting and XLS export.
- `.build/ci-fix-learning-recovery.log`: all eleven selection checks in the short
  window and actual isolated WebKit crash/recovery, persisted drafts, later
  streaming and one Open in R bridge.
- `.build/ci-fix-tutor-runtime.log` and `.build/ci-fix-tutor-protocol.log`: pinned
  runtime installation, integrity/failure cases, native protocol, cancellation,
  private diagnostics and institutional policy pass.

The development build is `.build/ci-fix/StatsDirect.app`; no installer was built.

## Signing and notarization prepared for the Developer ID — 15 October 2026

Iain's Apple Developer account is enrolled. The app is still ad-hoc signed by build.sh, so two pieces are added for the signed release: `StatsDirect.entitlements` beside Info.plist, and `Scripts/sign-app.sh`, which signs every Mach-O inside the bundle first (the .NET runtime's libraries under Resources/Engine/dotnet, the engine and the text layout library, each with the hardened runtime, the entitlements and a secure timestamp), then the bundle, verifies the signature strictly and, with `--notarize <keychain profile>`, submits the zipped app to Apple through notarytool, waits, staples the ticket and validates it; the profile is made once with `notarytool store-credentials`. The entitlement set was found by trial on this Mac before any certificate exists: the engine runs on CoreCLR through hostfxr, which compiles code at run time, so the hardened runtime refuses it without `com.apple.security.cs.allow-jit`; with that entitlement alone the app tour (worksheet, analysis form, report, Continue in R, help pane, calculator, learning) runs in full on an app signed with the hardened runtime, and `allow-unsigned-executable-memory` is not needed. An ad hoc signature carries no team, so library validation refuses every library in the bundle (the tour stopped at "The Excel component could not be loaded"); for testing without a certificate the script switches validation off in a temporary copy of the entitlements, which a Developer ID signature does not need, every library then carrying the team. What remains is Iain's: a Developer ID Application certificate in the login keychain, a notarytool profile from an App Store Connect API key or an app-specific password with the Team ID, and the bundle identifier and version of the first signed release; then the release workflow takes the same script with the certificate and profile as secrets.

## Engine pinned to Windows main c01cb8f7: tab captions follow the document — 16 October 2026

The Windows head moved one commit past 5.2.0. c01cb8f7 (16 October) keeps the Windows workbook and report tab captions in step with their documents: a tab takes its caption from the form's title and follows every later change to it (Save As, a rename, a report's title, an imported file that gets its name after its tab exists), its tooltip the file's path or, unsaved, the title; a WindowsShell check covers it. It touches only the Windows shell and its tests. The engine's 874 files, the recipes, the examples and the help bundle are byte-identical, so the pin, the manifest, `Content/engine-info.json` and `Content/help-manifest.json` move to c01cb8f7 and nothing else from upstream changes.

The Mac had the rule only for a workbook saved as Excel: a worksheet saved as CSV or TSV, a grid saved as RDS or RData, a report saved as HTML and a script saved from its pane kept their old captions, and the tooltip was always the title. Now `Viewer.noteDocumentSaved` (Sources/main.swift) records the file and retitles through `retitleDocument` (the tab, the tab-view item, the Window menu and the window's title), and every save path calls it: Excel as before, CSV/TSV and RData when the save is the whole document, the report's HTML copy (PDF and Word remain copies, as before) and the script pane through a `scriptSaved` callback (Sources/RPane.swift). The caption keeps the Mac's conventions by kind: a workbook shows the file's name with its extension (as the Save As check in the report export suite asserts), a report and a script take the stem, which keeps Open in R writing `<stem>.R`. The tooltip is the file's path when the document has one (`Document.savedPath`: the opened or saved file, else an imported report's source), otherwise the title. The script's language change goes through the same helper, so its window-title suffix now matches the rest.

Two older differences are raised rather than changed, for Iain's word: Windows captions every saved document by its stem where the Mac shows a workbook's extension (the macOS document convention), and the Windows example opens captioned "Example workbook" where the Mac's opens as test.xlsx. Iain's word (16 October): keep the Mac convention on both, so a workbook's tab shows its file name with the extension and the example opens as test.xlsx; the Windows side keeps its own, a deliberate platform difference rather than one to close. Also noted for later: a CSV or RData save retitles the tab but leaves the grid's own workbook name, so a later run record's source file still names the workbook; and a report's saved HTML `<title>` is captured before the retitle on the first save (reopening titles by the stem, so nothing shows).

Suites at this pin: test.sh 557 checks, the report export suite 58 (one new: after Save As the workbook's tab reads renamed.xlsx with the file's path as tooltip and the Window menu follows; a new report's tooltip is its title; after `noteDocumentSaved` a report is captioned by its stem with the path as tooltip and the old name is gone from the Window menu), the beta check 75; Codex's suites unified-toolbar 20, r-integration 53, script-ai 65, report-ai 56, startup-r-setup 29, mac-parity 19, grid-selection 18, paired-workflow 37, learning-workspace 6, provider-learning 6, ai-sharing 1, learning-recovery 5, conversation-r 16; all exit 0, the focus-dependent suites among them.

## Engine pinned to Windows main 099b7193 (5.2.1 in the making): SVG charts captioned by their one link; Save and Save As for the report — 16 October 2026

The Windows head moved eleven commits past 5.2.0 as a 5.2.1 release is built (the tag not yet cut): the script window's output pane became a web page that draws the charts a run writes (a1ff485b, 3b31a250), the run's default graphics device became SVG, Codex's c01cb8f7 tab captions, 40e6da56 (the RTF import registers the code-page provider, since RtfPipe needs Windows-1252), 238dcf64 (report Save As offers Word and PDF copies beside HTML; Save stays HTML), 47e2f3b8 (the startup logo stays until the main window shows; a disposed-icon error on closing the last report), c941e949 (the WindowsShell, Learning and Calculator suites print an exception that escapes to the UI thread as UNHANDLED and fail), the version ce8c33e1 and changelog entries, and the help rebuilt (7e80e582) with the Save As formats, RTF reports opening and the charts in the script output. In the engine set only `StatsDirectUI/R/RController.cs` (Windows-only, excluded from the Mac build) and the csproj version changed; the recipes and `analysis-recipes.json` are identical; the help bundle re-import changes 101 files (the rebuilt search index and the three topics). The RTF fix does not apply: the Mac reads RTF through Cocoa's own importer (`Sources/LegacyReport.swift`), which handles the code pages itself.

Ported to the Mac, as the Windows script window now behaves:

- `Content/R/session.R`: a plot drawn without a device of its own goes to an SVG file, one per page, which the pane draws. R's own `svg()` needs X11's Cairo on a Mac (this machine: "failed to load cairo DLL" although `capabilities("cairo")` says TRUE), so the wrapper opens `svglite`, the device the program's library carries for its own charts, at R's default 7 by 7 inches as Windows draws; without svglite it keeps the PDF device as before. The file is `plots-<run>-<device>-<page>.svg`, keyed by a per-run device counter so a second device in the same run cannot overwrite the first's pages (R's `Rplot%03d` naming, which Windows uses, restarts at 001 for each device; raised with the Windows session as an observation).
- `Sources/RPane.swift`: SVG (and GIF, BMP) join the chart files; a chart is drawn under the caption "Chart: <file>", which is its one link (the plain "Plot ·" caption and the separate "Open plot file" line go); the files-written list names only the files not shown as charts, so a run of charts alone lists nothing. The AI pane reads the same plain text, so a chart stands as "Chart: <file>" there. An SVG from svglite loads in `NSImage` with a vector representation; a Bland-Altman plot with a legend, dashed lines and rotated axis labels, and a histogram, rendered through it correctly.
- `Sources/ReportExport.swift`, `Sources/main.swift`: Save (⌘S, the toolbar's Save report, the close and quit prompts) writes the report's own HTML file again without asking once it has one (`Document.reportFileURL`: the file it was saved as, else the HTML it was opened from); a report without a file, and the Export items with their fixed format, go through Save As. Save As… (⇧⌘S, "Save Report As…" for a report) is the panel with the format choice, HTML or a Word or PDF copy, proposing the report's own name and folder; for any other document it does what Save does. The chosen format is remembered as before.

Checks added: Tests/r-pane-driver.swift (five SVG files from four runs named as the wrapper names them, each captioned by its file as its one link, no "Open plot file" or "Plot ·", a run of charts alone lists no files, a run writing a chart and a CSV lists the CSV alone); Tests/report-export-driver.swift (Save writes a report's own file again without asking and clears the dirty state).

## Report save semantics and independent imported R charts — 16 October 2026

Save As now always starts with HTML unless the user explicitly chooses an export command. A remembered PDF or Word choice no longer changes that default. Only an HTML save advances the report's saved revision or establishes its file; PDF and Word remain copies. Closing after an export still asks about unsaved edits, and edits made while any save is running remain dirty. The close prompt explains that HTML keeps the editable report.

The multiple-chart checks exposed duplicate SVG identifiers, dropped `use` glyphs, svglite clip identifiers containing `=`, and chart styles losing their scope. The shared report modules now give each SVG its own identifiers, preserve local glyph references, and resolve its safe drawing styles independently before inlining them. Inherited glyph paint is retained. External glyph references and active SVG content remain blocked. Both import and paste use the same helper; the browser bundles are rebuilt from source. No Windows files or engine pin are changed by this fix.

`report-saving-checks.swift` exercises the actual native format picker, cancellation, new and existing reports, explicit export choices, close prompts, direct Save and edits during a save. `report-svg-checks.swift` imports five charts together: two reproducible R/svglite fixtures, a repeated first chart and two Cairo-style glyph fixtures with conflicting styles, glyphs, clips and gradients. Pixel comparisons check separate versus combined charts, HTML reopen, paste and undo/redo. A separate visibility assertion prevents missing glyphs from passing as matching blank pictures. HTML, PDF and DOCX are exported; `verify-report-svg.py` inspects all five Word vectors and their PNG fallbacks. The Cairo-style fixtures are synthetic: this Mac's base-R Cairo device requires XQuartz, which is absent; real R charts are generated with svglite.

Validation: Release build and its distribution checks pass (`.build/report-save-review/build.log`); the complete native report driver passes (`report-full.log` in the same folder), as do all 115 browser model tests (`all-javascript.log`). All Word/package verifiers pass in `package-checks.log`. The new verifier initially expected five separate PNG files, then was corrected to check five valid picture relationships with four PNG files because the identical repeated chart legitimately shares its fallback. The rendered PDF was inspected with all five charts intact. The prior native failure on duplicate SVG references is captured in `svg-before.log`. No installer was rebuilt.

## PDF by default for ordinary R output; SVG retained for reports — 16 October 2026

`Content/R/session.R` now uses R's built-in PDF device for ordinary script output. Each run/device owns its filename, with all pages in one PDF by default; the existing native output view displays every page and links to the original file. Report charts keep their separate SVG generation/import path. Explicit graphics devices still work, and the default remains seven inches square unless the script changes the PDF settings.

The Mac and Windows sessions jointly checked a subtle R requirement: `dev.new` filters arguments against the default device's formal signature. A wrapper accepting only `...` silently loses its arguments. The PDF wrapper therefore adopts the installed PDF device's signature and forwards only supplied arguments, preserving `pdf.options`, custom size/page mode, explicit filenames and `file=NULL`. Numbered files retain all pages when `onefile=FALSE`. An empty supplied-argument list is converted to `character(0)` before `mget`; otherwise a no-argument plot fails. Both cases were reproduced and fixed before the final checks.

Validation logs under `.build/r-pdf-default`: `r-pane-verified.log` passes the native output checks for multiple pages/devices, errors, variable persistence, agreement plots, file links, explicit SVG/PDF devices, independent concurrent tabs, unchanged earlier chart bytes/timestamps, `dev.new`, `pdf.options` and stopping/restarting a run. `r-integration-final.log` passes the full actual-application R workflow, including PDF output through Continue in R with the original report's SVG and HTML export intact. `report-r-operations.log` passes the engine's R operation comparisons, including SVG LOESS and method-comparison charts, numerical agreement, errors and cancellation. The standalone output suite now has a repeatable `Scripts/test-r-pane.sh` runner and is included in CI. The engine pin and shared report-editor sources are unchanged. No installer was rebuilt.

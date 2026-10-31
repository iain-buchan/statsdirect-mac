# Interactive R console: Mac 1.1.0

The console is enabled in the normal 1.1.0 app by
`StatsDirectInteractiveRConsole`, independently of prototype identity. Normal
updates and the blank-workbook startup remain enabled. R is optional until a
session is requested: guided setup installs native Apple Silicon R if needed,
then prepares compatible SVG support from official CRAN Mac binaries in
`~/Library/Application Support/StatsDirect Viewer/R Library`. Setup is shared by
concurrent tabs, cancellable and retryable, and leaves scripts unexecuted.

1.0.0 remains the live signed and notarised release. IT Services will sign and
notarise 1.1.0 after release testing; 1.0.1 is superseded. Neither these checks nor
the separate prototype builder produces an installer or publishes a release.

Build with `Scripts/build-interactive-console-prototype.sh`. The separate app is
`.build/interactive-r-console.noindex/StatsDirect Console Prototype.app`, with
bundle identifier `com.statsdirect.consoleprototype`. It reuses the installed
app's engine/runtime assets read-only and requires installed R and its headers
for this development build. The builder prepares the SVG device with
`Scripts/prepare-r-console-svg.sh` in the prototype’s private R library.
Signing is local/ad hoc only. Matching debug symbols
are stored outside the app.

The app starts with one blank workbook. File > New Script and opened R files
start in Script view without executing the source. Continue in R opens the
generated analysis script in Console view and runs it once. Open in R (R+), after
AI, saves the source in R Scripts and opens RStudio or starts a fresh R.app
session. File > New C# Script and New VB Script preserve the managed script
editors. The isolated development app also offers New R Console (Prototype).

- Enter runs a command; Shift+Enter inserts a line. Up/Down recalls history.
- Commands, text output and charts share one scrolling transcript. The toolbar
  and input prompt stay visible. Following the end survives chart decoding,
  multiline input growth and window resizing. Reading earlier output, selecting
  text or holding a pointer pauses following; Clear Output/new sessions restore
  it. Entering a new Console command or answering R explicitly resumes following
  so its results come into view. Script/Console switches retain the reader's
  position.
- Script shows accumulated executable commands, supports editing, Run selection
  or Run all, and Save R Script. Console and Script use the same R workspace.
  Executed Script and Continue in R batches enter Up/Down recall intact, without
  duplicating Script source. Unexecuted source and prompt answers stay out of
  executable history. Renderer recovery restores recorded origins and history
  before applying the exact current edited Script; it never executes a replay.
- `readline()` and menu questions accept real answers; answers are not added to
  executable source or command history.
- Stop interrupts without sending a blank answer or EOF. Completed assignments
  remain; subsequent expressions in that submission do not run after an error or
  interrupt. Stop is not a rollback. Restart explicitly clears the workspace,
  retains script source and invalidates old input requests.
- Charts retain immutable SVG assets and display their original vector bytes in
  the console WebView. Open chart uses a native window with the same SVG in a
  WebView, scaled to fit, with native zoom buttons, a percentage display,
  Command-plus/minus/zero shortcuts and trackpad magnification. Fit restores the
  full chart. Save, Print and Close target the chart window. Copy
  advertises vector SVG first under its native Mac clipboard type, with a PNG
  fallback. A submitted script captures each
  completed plot page, rather than every intermediate `plot()`, `abline()` and
  `mtext()` step. Multiple actual pages are preserved; a paired-t agreement
  script produces one completed SVG. Earlier interactive chart versions remain
  immutable. Report SVG charts and the released app are unchanged.
- AI opens the existing right dock with the same sharing consent. It can receive
  an explicitly shared, bounded snapshot of script and output, not arbitrary R
  workspace objects. Opening the dock does not send code or data.

## Architecture

WebKit presents the shared `Content/RConsole` HTML/CSS/JavaScript assets; Windows
uses the same assets in WebView2 on its separate prototype branch. Native hosts
own file access, interruption, plot assets and execution. The bridge contract is
in `interactive-r-console-ui.md`.

A separate native worker dynamically loads the installed R library, enables
interactive R callbacks and evaluates parsed expressions on its main R thread.
Private framed FIFO input and an event file carry control traffic; printed R
output and user stdin never act as that protocol. The SVG snapshot device is `svglite`, installed from CRAN binaries in the
prototype’s private R library; it works without XQuartz. An internal PDF
recording device retains R’s display list for incremental drawing; it is not
the displayed output. The Swift transport validates
session IDs, generations and event sequences, drains raw output, and cancels only
its own child. SIGUSR1 sets R's interrupt flag, including during sleep and input.
The worker checks for a disappeared host while waiting for commands or answers.
Interactive prompts publish their actual UTF-8 answer capacity. Rejected input
restores the current prompt so the learner can shorten an answer and retry.

Each session has its own working directory under Application Support/StatsDirect
Console Prototype/R Sessions. User-created files and SVG chart assets remain there when
a console closes; private temporary IPC files are removed. A renderer reload
replays retained output without executing R commands again. Visible output is
bounded; this is not a complete disk-backed console log or saved R workspace.

This is a development prototype, not a sandbox for untrusted R code. R code has
ordinary local user permissions. Terminal emulation, package-install workflows,
full IDE completion/debugging, and automatic workspace restoration are outside
this first prototype.

## Focused verification

- `Tests/test_interactive_r_worker.py`: actual installed R, persistent variables,
  interactive questions, multiline parsing, Unicode, error recovery, interrupts,
  repeated Stop, stale input, buffered output, multiple plots, revisions and
  non-plot command deduplication; abrupt host-death cleanup, rejected-answer retry, completed paired-t charts
  plot preservation after errors/Stop, and multi-panel/base/grid pages (39 checks).
- `Tests/r-console-ui.test.mjs`: protocol/session guards, bounded safe output,
  source retention, both native continuation styles and exact plot revisions.
- `Scripts/test-r-console-integration.sh`: live WebKit/native-worker integration,
  including renderer recovery, input rejection, Restart, original inline SVG,
  SVG/PNG clipboard representations and vector chart opening/copying. The
  scrolling/history and chart-zoom updates passed the full suite on 31 October 2026 (95 pass
  results), including genuinely delayed SVG decoding, multiline draft layout,
  upscroll/selection/pointer preservation, detached-image rejection,
  Clear/new-session following and both Script/Console reading positions. Actual
  R counters prove renderer recovery reruns no executed batch or unexecuted edit.
  Native chart checks verify rendered enlargement, percentage updates, keyboard
  shortcuts, zoom limits, Fit and unchanged SVG bytes. Explicit Console commands
  and replies resume following while empty submissions/background output retain
  the reader's position.
- `Tests/r-console-ui.test.mjs` and `Tests/r-console-recovery.test.mjs`: 15 model
  checks passed, including whole multiline execution recall and exact source
  preservation during repeated recovery.
- Manual app checks: paired t-test with inline charts, interactive question,
  Stop without accepting an answer, retained variables, AI dock/focus return,
  real chart-button clicks and wheel scrolling over the prompt.

Focused console checks validate these changes without repeating unrelated engine
work. The 1.1.0 signing handover still requires the complete applicable release
tests and CI checks on that candidate.

Rendered UI checks require a visible native test window. WebKit can accept model
events while suspending animation frames in a hidden/occluded page; the runner
now requires visibility before interacting with controls and records diagnostics
on failure. On this Mac, activating the test window through computer use allowed
the complete suite to run. `--scroll-only` and `--history-only` select focused
subsets. `STATSDIRECT_KEEP_CONSOLE_TEST_APP=1` retains the disposable test bundle
for diagnosis; normal runs remove it, and the retained local bundle was removed
after verification.

Windows coordination: the scrolling/history update comes from
`iain-buchan/statsdirect` main commit
`7eab958252a9be691fc02d56bc1acf89baca5e25`. Its original `console.js` base was
byte-identical to Windows blob `0416d8bbe5fa4f9d59fa53466dd414d27da12780`. A later
shared-UI refinement resumes following after an explicit Console command/reply;
this behaviour was agreed with the Windows session. Both Open chart and Copy
chart card buttons remain. Windows reported 121 native checks and 13 model checks
passing. The Mac adoption also includes the Mac host's renderer-recovery envelope
fix and its own WebKit/R checks. It does not change Windows sources or installers.

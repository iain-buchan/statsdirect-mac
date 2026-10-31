# Interactive R console: Mac prototype

This work is isolated on `prototype/interactive-r-console`. It does not change
main, the 1.0.1 University signing candidate, the installed StatsDirect app or
any GitHub release. No installer is produced.

Build with `Scripts/build-interactive-console-prototype.sh`. The separate app is
`.build/interactive-r-console.noindex/StatsDirect Console Prototype.app`, with
bundle identifier `com.statsdirect.consoleprototype`. It reuses the installed
app's engine/runtime assets read-only and requires installed R and its headers
for this development build. Signing is local/ad hoc only. Matching debug symbols
are stored outside the app.

The app opens an R Console tab. File > New R Console (Prototype) opens another
independent session. Continue in R opens the generated analysis script in the
console and runs it once. Existing Script/C#/VB functionality remains available.

- Enter runs a command; Shift+Enter inserts a line. Up/Down recalls history.
- Commands, text output and charts share one scrolling transcript. The toolbar
  and input prompt stay visible.
- Script shows accumulated executable commands, supports editing, Run selection
  or Run all, and Save R Script. Console and Script use the same R workspace.
- `readline()` and menu questions accept real answers; answers are not added to
  executable source or command history.
- Stop interrupts without sending a blank answer or EOF. Completed assignments
  remain; subsequent expressions in that submission do not run after an error or
  interrupt. Stop is not a rollback. Restart explicitly clears the workspace,
  retains script source and invalidates old input requests.
- Charts retain immutable vector PDF assets. Inline PNG previews are bounded;
  Open vector PDF and Copy chart refer to that exact version, including an older
  chart before a later `abline()`. Report SVG charts are unchanged.
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
output and user stdin never act as that protocol. The Swift transport validates
session IDs, generations and event sequences, drains raw output, and cancels only
its own child. SIGUSR1 sets R's interrupt flag, including during sleep and input.
The worker checks for a disappeared host while waiting for commands or answers.
Interactive prompts publish their actual UTF-8 answer capacity. Rejected input
restores the current prompt so the learner can shorten an answer and retry.

Each session has its own working directory under Application Support/StatsDirect
Console Prototype/R Sessions. User-created files and plot PDFs remain there when
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
  non-plot command deduplication; abrupt host-death cleanup and rejected-answer retry (28 checks).
- `Tests/r-console-ui.test.mjs`: protocol/session guards, bounded safe output,
  source retention, both native continuation styles and exact plot revisions.
- `Scripts/test-r-console-integration.sh`: live WebKit/native-worker integration,
  including renderer recovery, input rejection, Restart and vector chart copying.
- Manual app checks: paired t-test with inline charts, interactive question,
  Stop without accepting an answer, retained variables and AI dock/focus return.

Only focused console checks are needed here: the calculation engine is unchanged
and the frozen signing candidate already passed its release CI.

Windows coordination: `iain-buchan/statsdirect`, branch
`prototype/interactive-r-console`, commit `7e55acb52658d0a7ef019db750ffa4599904b739`.
Windows reported 82 focused checks passing, with identical shared UI assets from
Mac commit `25d0341`. Windows main and its released installers remain unchanged.

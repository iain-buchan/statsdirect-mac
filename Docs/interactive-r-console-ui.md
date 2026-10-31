# Shared interactive R console UI prototype

`Content/RConsole/index.html`, `console.css` and `console.js` are dependency-free
HTML assets shared by the Mac WKWebView and Windows WebView2 prototypes. They
present R input/output; all R execution, prompt handling, interruption and file
access belong to the native host and its separate R worker.

The UI has a single transcript with text and plot previews, an input field and
a Console/Script switch. Script supports Run selection or Run script, plus Save.
It is unavailable for execution while R is evaluating, answering a question or
waiting for an incomplete expression. Console entry supports Enter to submit,
Shift+Enter for a new line, single-line Up/Down history, and Escape/Control+C to
interrupt when no text is selected. Stop sends an interrupt action without an
empty answer or EOF. Restart invalidates the old input request immediately.

## Native bridge

Mac: `window.webkit.messageHandlers.statsDirectRConsole.postMessage(message)`.
Windows: `window.chrome.webview.postMessage({channel:'statsdirect-r-console', ...message})`.

Every action has `protocolVersion:1`, `sessionId` and `generation`. The initial
`ready` action uses `sessionId:null` and generation zero. Native hosts must exempt
that bootstrap action from their existing-session check. Other actions are:

| Action | Fields |
| --- | --- |
| `submit` | `source`, `origin:'console'|'script'` |
| `inputReply` | `requestId`, `text` (an explicitly entered empty reply is valid) |
| `interrupt`, `restart` | no source or answer payload |
| `saveScript`, `scriptChanged` | `source` (the complete source) |
| `ai`, `help` | no content payload |
| `openPlot`, `copyPlot` | `plotId`, `revision`; resolve that exact asset in native-owned state |
| `modeChanged` | `mode:'console'|'script'` |

The native host calls `window.StatsDirectRConsole.receive(event)`. First send:

```json
{"type":"session","protocolVersion":1,"sessionId":"unique-session","generation":0,"seq":0,"script":"x <- 1\n","capabilities":{"plotMimes":["application/pdf"],"ai":false,"help":true,"openPlot":true,"copyPlot":true}}
```

Later events carry the same version/session/generation and a strictly increasing
`seq`. The page ignores old generations, wrong sessions and repeated/reordered
sequence values. A new session requires a higher generation. The source script
and command history survive Restart; displayed output resets to the new session.
An optional `events` array in the initial session packet can replay that session.
When sending `script` on Restart, the host must use its current source mirrored
by `scriptChanged`, rather than the original seed. Omitting `script` retains the
page's existing source; a reloaded WebView needs the native copy supplied again.

| Event | Fields and meaning |
| --- | --- |
| `state` | `state:'starting'|'ready'|'busy'|'continuation'|'input'|'stopped'|'interrupting'`, optional `prompt` |
| `inputRequested` | `requestId`, `prompt`, optional `kind:'continuation'`, `addToHistory` |
| `commandAccepted` | optional `commandId`; R is evaluating |
| `commandFinished` | `status:'ok'|'error'|'interrupted'`; does not itself mark R ready |
| `inputEcho` | `text`, `prompt`, `origin:'console'|'script'|'continueInR'|'input'`, optional `commandId` |
| `output` | `stream:'stdout'|'stderr'`, `text` |
| `plot` | `plotId`, integer `revision`, `mime`, image-data `preview`, `label`, optional `pages` |
| `notice` | `text` |
| `exited` | optional `message` |
| `started` | accepted informational worker event |
| `capabilities` | updated `capabilities` object |

Windows native REPL continuation callbacks can send `inputRequested` with
`kind:'continuation'`. The UI replies using `inputReply` and the exact request ID,
even if a following state event says `continuation`. The Mac parser can instead
send a plain `state:'continuation'` with no request ID; the next entry is `submit`.
Source execution stays disabled in either continuation state. Normal `readline()`
questions use `kind:'input'` or omit `kind`.

The host echoes accepted submissions; the page never pretends execution happened
merely because an action was sent. Use **origin `input` for human answers**, so
answers do not become executable source or command history. Continuation source
lines should use origin `console`. Console command echoes append to the Script;
script/Continue-in-R echoes do not duplicate the existing source.

`state:'ready'` is authoritative after R has unwound. Do not translate Busy(false)
or `commandFinished` alone into top-level readiness. A matching input request is
required before the page allows an answer; Stop/Restart removes it immediately.

## Graphics and retained data

Mac ordinary plots retain a vector PDF master. The native host supplies PNG page
previews and resolves Open vector PDF/Copy chart using its own plot map. Windows
may advertise ordinary SVG; an image-data SVG preview is accepted. Emit one plot
event per displayed PDF page, with a distinct plot ID or revision and useful label.
Revisions append immutable transcript pictures rather than overwriting earlier
results. Open/Copy actions carry both `plotId` and `revision`, so an older card
cannot accidentally resolve the latest picture. The UI rejects actions from a
card removed by a session reset. IDs, revisions and generations must resolve only
the matching immutable assets owned by the console host.

The UI accepts only base64 image-data previews; no arbitrary HTML, file URLs,
external image URLs, frames or widgets. R output uses DOM `textContent`, never
HTML. The page blocks network connections, frames, object plugins and inline
scripts. AI/Help/Open/Copy controls are enabled only by explicit native capability
flags; no unsupported actions are simulated.

Displayed output is capped at 200,000 characters, 500 entries and 24 MiB of image
previews. The complete Script is retained, and native original graphics remain
available. History retains up to 100 recent commands with a 500,000-character
budget; it does not contain prompt answers. `snapshot()` returns source, bounded
plain output, history and transcript metadata, excluding image bytes.

Additional presentation APIs: `focusInput()`, `setMode('console'|'script')`, and
`paste(text)` (literal insertion into the active source/input field, no execution).
`receive()` returns true only for an accepted event. Native hosts must enforce
their own session, request, state and file-access checks independently of the UI.

Run the meaningful model regression tests with:

```sh
node --test Tests/r-console-ui.test.mjs
```

Transcript rendering preserves existing controls across focus and selection changes.
New output waits while a transcript pointer is held down, then refreshes after
the click. Native integration tests retain the original button reference through
selection-change animation frames and real R output during a pointer press.

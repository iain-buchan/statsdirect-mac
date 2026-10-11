# Mac interaction update — 11 October 2026

## Windows release boundary

The Windows repository and released application have not been modified. The Mac calculation engine remains pinned to `4ee43dc66c038f6deff1933e4fb8d42f52fafbec` (5.0.14); its source is unchanged. Do not import the later engine or R recipe updates until the separate Windows investigation is resolved.

The Mac checkout was missing the report editor already shipped by Windows. Its shared editor modules and generated bundles are now copied unchanged from `4e9f9d10a7dbf795c28fc3dc3e5924476a3bc1d6`, the revision named by the Windows `ReportEditor/README.md` and build script. Rebuilding `Report/build.mjs` reproduces that revision byte for byte. There are no new changes to that shared editor implementation for Windows to adopt.

New Mac behavior lives in `Content/Mac/report-host.js`, the Swift report host, the Mac grid/forms UI and its headless host wrapper. Windows does not load these files. The Mac extension adds contextual Help/R toolbar buttons and a draft region for typing directly into an empty report. Native context-menu and report-block integration follow the same existing shared-editor contract. Reports open editable, with no Edit/Add text buttons, separate notes field, engine-credit footer or displayed input-history code. Help links remain in exported documents; full input history remains available in the R script.

The user's requirement is to leave the released Windows version unchanged and identify any future shared-editor change that could affect it before distribution.

## Analysis forms

Compatible highlighted worksheet data is submitted automatically. Saved confidence defaults are retained. The original engine's parameter groups become a single form with Run, conditional controls and engine validation. Previewing a changed option does not execute calculations or add history. Prompts that require a distinct column (such as weights) start without the previous data selection; selections wider than permitted are not cropped. The paired-test Agreement checkbox and single Run workflow remain intact.

This is host integration, not a rewrite of statistical routines. Complex group/identifier and specialised multi-stage workflows still use their existing dedicated controls where the engine requires them.

## Verification

- Full `test.sh`: engine regressions, R comparisons, help replay, forms, 107 JavaScript tests; 207 available menu commands open and 66 combined-form workflows match the sequential engine outputs.
- Native analysis workflow: selected data, saved confidence, chi-square prefill and conditional Fisher control, instant result retention, active report, weight selection and oversized-selection handling.
- Paired workflow and R integration native suites passed.
- Report suite: one editable region, formatting across results, blank-report typing/undo, contextual toolbar and native menus, chart sizing, cut/paste/drag, unified deletion/undo, HTML/PDF/DOCX, Office clipboard, legacy RTF and HTML sanitization. Export package checks verify tables, borders, numerical formatting and vector/raster pictures.
- Release build and matching native debug symbols; shared editor source and bundle identity checked against the released Windows pin.

The candidate app is `.build/mac-interaction-build/StatsDirect.app`. The existing running app was not replaced or restarted during the build. No push or release has been made for this update. `origin/main` is ahead of the local base and includes engine changes currently on hold; reconcile deliberately before a later push, rather than fast-forwarding the engine as part of this UI work.

## Script AI dock

A later candidate at `.build/script-ai-build/StatsDirect.app` adds an accessible sparkle/AI
button beside Run and Stop in every R script. It opens a native conversation dock in the
same right-hand position as Help; the two panes replace each other. The app's existing
ChatGPT account connection is reused. Each script has its own in-memory conversation,
with a composer, streaming responses, Stop and New conversation. Code suggestions are
selectable/copyable text; the assistant cannot run R or alter a script.

Sharing starts off. Users may send just their question/history, or explicitly share the
current script/output and one chosen workbook after confirming they contain no person
identifiers. This is enforced in the native host, not just the button state. Context is
scoped per question, script/output are frozen bounded snapshots, and a changed workbook
invalidates its approved reads. The existing worksheet identifier checks remain active.
The sharing controls sit below the conversation and can be collapsed. See
`Docs/Learn/TutorPrivacy.md` for the precise scope and in-memory retention behavior.

Changes are restricted to the Mac Swift shell, Mac connection client, a new bundled
script-assistant prompt, documentation and tests. The Windows repository and engine pin
remain untouched. All 22 shared report editor modules/bundles checked remain byte-identical
to the released Windows editor revision above.

The new native suite reports 30 passing checks using a local protocol fixture and fictional
data, including consent, question-only payloads, approved dynamic data reads, rejection of
identifiers/unapproved documents/changed workbooks, conversation isolation, bounded excerpts,
minimum-window layout, Help switching, cancellation, policy, and Command-Return/Command-W
routing. The native interface was also inspected through accessibility and screenshots.
Existing ChatGPT transport and institutional-policy regressions pass. The Release app builds
with the 873-file engine provenance check and 1,552 distribution regressions, matching debug
symbols and strict deep ad-hoc signature verification. No live OpenAI question was sent.
The existing native R integration and offline Help suites also pass against this candidate.
The user's running application was not replaced or restarted.

The AI candidate was subsequently launched at the user's request after confirming StatsDirect
was already closed. The last source-only wording change shortens the sharing warning to end
after "identifying free text." It has not yet been rebuilt into that running candidate.

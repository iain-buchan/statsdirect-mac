# Mac document toolbars

Agreed with the **StatsDirect for Windows .NET** Codex session on 12 October 2026. The toolbar work was implemented in the Mac host. Subsequent local changes to shared report-editor files are identified below; the Windows sources and engine pin remain unchanged.

Common order: **Save | Undo, Redo | Cut, Copy, Paste | Find | document controls | Help, R, AI where available**. Mac shortcuts retain Command; Windows retains Control.

- Reports: original style, font, size, emphasis, lists, alignment and chart-sizing controls; contextual Help and Continue in R. One editable report and one undo history. Save uses the existing HTML/PDF/DOCX panel.
- Scripts: Run, Stop/Reset, Clear output, Output folder; Help, AI, Open in R. AI uses the letters AI; Open in R uses R+ and retains its accessible name and overflow label. Install R is shown only when needed. Copy follows the selected editor/output pane, including when keyboard focus moves into More. Read-only output never causes editing of a stale script selection.
- Worksheets: Clear selected cells, Add 100 rows, Add column. The cell-value/formula field stays separate. Save retains Excel/CSV/R-data routing. Find searches populated cells in the current sheet. Cut clears its captured selection only after a successful native clipboard acknowledgement and only if the worksheet has not changed.

All three use 20 px monochrome outline glyphs on 30 px targets. `Content/Mac/toolbar-icons.json` is the common source for SVG and AppKit drawing. Save/Cut/Copy/Paste/Find/Help/R reproduce Windows `SharpToolbarRenderer` geometry (24-unit coordinates, 1.8-unit round strokes). Undo/Redo and Run match the Windows session's agreed additions. Run is the triangle `(7,3) → (21,12) → (7,21)`.

One toolbar row at every width. Secondary commands move into More in their original order; Save, core editing and Run have priority. Web overflow moves original controls, preserving selection, state and event handlers. Native overflow invokes the original buttons and reflects their enabled states. More has a tooltip and accessibility name; Escape dismisses the web popup and returns focus, and all overflow controls remain keyboard accessible. An empty More control is hidden. A short window scrolls the popup rather than clipping its controls.

The Mac adapter adds Save, clipboard, Find and contextual controls after editor initialisation, with inline toolbar CSS so standalone report export requires no extra stylesheet file.

## Subsequent chart alignment

New Mac report charts are left aligned. Left/Centre/Right operate on a selected
chart or picture and reflect its alignment; ordinary text selections retain text
alignment commands. Justify is unavailable for a single selected picture. Chart
alignment belongs to the picture's inline margins, so removing editable wrappers
on save/copy does not discard it. The free-corner resize handle follows alignment:
bottom right for left/centre, bottom left for right. Each gesture uses the existing
report undo history; Escape cancels resizing.

This change modifies the Mac copy of shared sources based on Windows editor pin
`4e9f9d1`: `Report/chart-size.mjs`, `editor.mjs`, `export.mjs`, `fragment.mjs` and
`import.mjs`, and regenerated `Content/Report/{editor,export,import}.js`. The files
are no longer byte-identical to that pin. The default-left stylesheet is Mac-only.
The common-source changes add selected-picture alignment, exact single-picture
selection, alignment-aware resizing, and preservation of alignment in HTML/PDF,
DOCX and Office clipboard fallbacks. These changes need coordinated review before
Windows chooses to import them; they do not alter the released Windows app.

The full native report suite passes, including the new selected-chart commands,
button state, text/mixed selection, alignment-aware resizing, single-step undo/redo,
public clipboard, HTML reopening at different widths, rendered PDF and actual DOCX
drawing paragraphs. Existing editing, transfer/deletion, RTF import, Creole styles,
Excel numeric clipboard and engine/R result checks also pass. The eight Report
JavaScript tests pass. Evidence: `.build/chart-alignment-full-report-checks.log`.
The Release app is `.build/chart-alignment/StatsDirect.app`; its 1,552 distribution
checks, matching debug symbols and strict deep signature verification pass, and
its packaged editor assets match the final source bundles. This remains an
unreleased review build; the user's running app was not replaced. The subsequent
source handover uses `feature/mac-unified-toolbars` and
`feature/windows-unified-toolbars`, with Iain Buchan as author and committer.

During the subsequently authorised Windows catch-up, Windows native tests exposed
report margins in standalone SVG downloads. Both copies now remove only the root
margin declarations in `exportableSvg`, preserving chart paint/font styles and the
source element. The Mac alignment regression covers this for all three alignments.
The refreshed Mac review app is `.build/chart-alignment-svg/StatsDirect.app`, using
the same verified Release binaries with the regenerated editor asset; its signature
and matching symbols pass. The running user app is unchanged.

Validation entry points:

- `Scripts/test-unified-toolbar.sh`: command order, one row at wide/narrow widths, More formatting with retained selection/undo, keyboard dismissal, native save/find, worksheet search/cut/undo, delayed clipboard acknowledgement, overflow actions and CSV save routing.
- `Scripts/test-report-export.sh`: existing report editing, chart sizing, transfer/deletion, Office clipboard and HTML/PDF/DOCX checks.
- `Scripts/test-r-integration.sh`: editing/output targeting, native Find, overflow, independent R sessions, paired t/agreement handoff and external R output.
- `Scripts/test-grid-selection.sh` and `Scripts/test-paired-workflow.sh`: selection and analysis gestures.
- `node --test Grid/*.test.mjs Report/*.test.mjs`: model regressions, including sparse worksheet Find at Excel limits.

The main CI runs the toolbar suite. The manually dispatched native workflow also accepts `toolbars`.

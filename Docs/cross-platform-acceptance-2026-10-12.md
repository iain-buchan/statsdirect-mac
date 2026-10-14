# Mac and Windows workflow alignment

## Mac implementation update — 14 October 2026

Iain authorised the remaining Mac fixes, coordinated Windows work, tests, and a
commit/push, explicitly excluding installer rebuilds. This source update includes:

- Report AI, rich offline WebView conversations and app-session sharing acceptance
  across Report, Script and Learning. Selecting a different data document or
  restarting the app asks again. Each question retains a bounded, fixed context.
- Current offline Help retained from incoming Mac commit `497760a` / Windows `406d2557` (identical to the initially tested `76911c12` bundle), including Learning,
  Report window and Script AI; matching seven Help commands and agreed order.
- Repeat analysis: a checkbox during worksheet acquisition automatically opens
  the next acquisition after a successful result/write-back. It clears the old
  selection, preserves the active report and stops on cancellation or failure.
  Instant-answer forms retain their existing edit/recalculate workflow.
- Worksheet and entry-table printing from actual data, with the native preview,
  page ranges and PDF options. Selected cells/columns/rows are honoured; otherwise
  the used rectangle prints. Wide worksheets use eight-column page bands. Print
  snapshots above 250,000 cells ask for a smaller selection, never silently omit
  cells. Scripts print their current source text.
- RDS/RData preserve Date/POSIXct NaN distinctly from missing values, including
  fractional dates and precise timestamps. The shared exchange-script fix was
  coordinated and independently round-trip-tested on Windows and Mac.
- File/Open accepts literal TXT reports, TSV data, C# and VB scripts. Script files
  never execute on opening, and opening does not start a background R process. The Script toolbar chooses R, C# or Visual Basic;
  C#/VB use the unchanged Windows `IScriptEngine.Run(..., ScriptType.Method, host,
  null, null, null)` contract with the Mac interactive host. Prompts, reports,
  worksheet output and console errors use normal Mac documents. Console capture
  stays separate when scripts are suspended at different prompts. C#/VB Stop is
  cooperative at engine checkpoints; arbitrary user loops cannot be force-stopped
  inside the application process. Windows-specific APIs are not emulated.
- Explicit Excel 97–2003 **data-copy export** writes all worksheet values and types
  as genuine BIFF8, independently checked with xlrd. It checks 65,536 rows, 256
  columns and 32,767-character cell limits before atomic replacement. A data copy
  does not clear the original document's unsaved flag or change its source path.
  Rich workbook preservation remains the existing XLSX save path.

Legacy qualifications remain explicit: **SDW conversion needs Windows with the
StatsDirect 2 converter**; Mac gives migration instructions and never modifies the
SDW. XLS data export does not preserve Excel formatting, formulas, charts or macros.
These are narrower legacy-format capabilities than Windows, not an assertion of
complete legacy-format equivalence. Final packaged clean-machine, account sign-in,
update and side-by-side release acceptance remain release gates. No installer,
version number, shared calculation source or shared report-editor module changed.

Mac commits `497760a` and `5a20b86` were incorporated, preserving the engine pin
`406d2557`, Help, test-harness improvements and marked licence notice. The 873
engine source hashes are unchanged from the initial test baseline.

The XLS writer uses only the Apache-2.0 NPOI 2.7.4 core assembly and explicit MIT
writer dependencies. Its OOXML, image and XML-signature stacks are not included.
Notices ship in `Content/Licenses`. Sources: [pinned NPOI package](https://www.nuget.org/packages/NPOI/2.7.4),
[HSSF writer](https://github.com/nissl-lab/npoi/blob/master/main/HSSF/UserModel/HSSFWorkbook.cs).
Newer NPOI packages have different licence/dependency considerations; upgrading
this pin requires reviewing those rather than silently importing the whole stack.

### Coordinated Windows source update

The Windows chat committed and pushed `52146ce5f34b2d3ce54fc84a18819fd150ad0d22`
on 14 October. It reports 822 passing checks: Learning/AI/file interchange 290,
WebReports 260, shell 32, Help 42, Continue in R 163, shared Learning/R 27 and
report JavaScript 8. Twelve physical clipboard checks were explicitly skipped to
preserve the user's enhanced-metafile clipboard; browser-selection and Office
payload/export checks ran. These are remote-session results, not native Windows
execution on this Mac. It confirms Report AI, session consent, HTML/maths chat,
refined lessons, Help order, CSV/R/script routing, XLSB, RTF-to-HTML/SVG import and
R-data exchange. The copied R exchange code includes the agreed Date/POSIXct NaN
fix on both platforms. Windows has a conservative R metadata safeguard after
ambiguous structural/row-name edits; Mac retains per-cell raw metadata.

No calculation algorithms, shared report-editor source or installers changed in
these coordinated updates. Installer and cross-platform release gates below still
apply before claiming Windows 5.2 / Mac 1.0 release equivalence.

## Release parity audit — 14 October 2026

Release target requested by Iain: **Windows 5.2 and Mac 1.0 should offer equivalent
functions and a similar look and feel, with different worksheet-grid implementations.**
This audit supersedes the historical readiness statements below. **Full functional
parity is not yet established.** Matching the analysis menus is not sufficient.
The audit itself changed no code, version, installer or release. The implementation update above records the subsequently authorised Mac fixes; the gap table below is the original audit, retained for traceability, not the current outstanding-work list.

Baselines: Windows clean `main` at `76911c12`; Mac `main` at `cbccc10` plus the
tested, uncommitted Report AI, HTML conversation, session-sharing and Help-menu
changes. The Mac engine pin remains `1bf97548` (5.2.0). No calculation, operation,
template or R-recipe changes separate that engine pin from current Windows main.
The shared `Report/*.mjs` editor modules match the Windows vendored modules after
normalising line endings; the platform hosts and export adapters remain separate.

| Area | Confirmed alignment | Gap to close before claiming parity |
| --- | --- | --- |
| Analyses and follow-ons | Both expose the same 208 distinct menu operations among 277 XML definitions. Mac completes 208 menu and 67 follow-on operations; file-host routes are separate. LOESS and method-comparison regression now run through R on Mac. | Keep final package operation coverage, numerical comparisons and selected-data workflows in both release gates. The older 9 October statement that these two R operations are deferred is obsolete. |
| Repeating analyses | Both can run analyses again and retain appropriate input. | Windows has a live batch/repeat loop. Mac has no equivalent automatic batch workflow. |
| Reports | Shared editable HTML editor, one chronological undo history, formatting, tables, charts, left/default and selected-chart alignment, HTML/PDF/DOCX export and contextual R/help. | Mac imports old RTF with WMF/EMF-to-SVG conversion. Windows currently refuses RTF and asks users to convert it in Word. Windows accepts TXT reports; Mac File/Open does not. Neither platform's DOCX export should be described as DOCX editing/import. |
| Script languages | Both support R execution, a console, plots, external R and generated scripts/data. | Windows also exposes functioning C# and VB script execution. Mac's script UI is R only. |
| AI conversations | Script AI uses rendered HTML; code review/opening, streaming selection and renderer recovery are implemented on both. | Windows has no Report AI dock, has no maths renderer in its Script conversation (Learning already has KaTeX), and still asks for sharing approval per question. Port Mac's Report AI, formatted maths and memory-only consent across Report/Script/Learning, resetting at restart or a different data document. |
| Learning | Same 12 lesson IDs, provider course example and curated resource library; options, course packs, questions, evidence and export exist on both. | Windows needs the four refined lessons (precision, diagnostic, risk/NNT, meta-analysis), method-specific R code, revised tutor instructions and removal of the pending-review notice. Fixed question keys must remain compatible with saved attempts. |
| Help | Same seven menu commands and offline HTML help; contextual help remains available. | Mac lacks Windows' newer Learning, Script AI and Report window pages and refreshed navigation/topics. Standardise Example workbook above updates, with About last. |
| Toolbars and appearance | Common monochrome Windows-style icons, one toolbar per document, shared report editor; Script AI then R+ with accessible Open in R text. | Review final builds at common wide/narrow sizes, including overflow, enabled/disabled contrast, consent collapse, report AI, charts and light/dark appearance. |
| CSV and R files | Mac opens/saves CSV and RDS/RData; both have R scripts. Windows has functioning Import Data/Export Data CSV/TSV routes. | Windows File/Open advertises CSV and R scripts but omits them from dispatch; repair this defect. Windows has no RDS/RData file import/export; copying data to R is not equivalent. |
| Excel compatibility | XLSX is the common writable exchange format; both read XLS/XLSX. | Mac also opens XLSB/XLSM/templates, whereas Windows File/Open only dispatches XLS/XLSX. Windows writes legacy XLS as well as XLSX; Mac writes XLSX only. Treat these as explicit format differences, not merely a different grid control. |
| Legacy data | Windows has a reachable SDW conversion workflow. | It requires a compatible installed StatsDirect 2 executable; it is not native parsing. Mac has no equivalent. A migration policy is needed rather than silently promising legacy-file parity. |
| Printing | Both print reports and Help. | Windows prints/previews worksheets and scripts; Mac explicitly disables these commands for worksheets, R/script windows and entry tables. |
| Setup and updates | Guided R and AI-runtime setup, direct workspace startup and recent-file handling exist. | Final clean-machine install/cancellation/resume and update tests remain. Platform installation/security steps may differ, while the requested action should resume consistently. |

The deliberate difference is the worksheet **implementation**; it should not hide
missing analyses, file handling or printing. Keep Command/Control shortcuts,
native file dialogs, window controls and operating-system installation conventions.
Do not remove a useful capability from one platform merely to make the lists match.

### Evidence from this audit

- Fresh Mac `test.sh` completed successfully with engine 5.2.0:
  `.build/release-parity-core.log`, `.build/form-coverage.json` (no missing operations).
  It covers independent R comparisons, forms/branches, all 67 follow-ons, worksheet
  output, the LOESS and MCR examples, 227 recipe/manifest comparisons, actual R
  execution and 112 JavaScript tests without skips. The known Chi2by2 help-versus-
  dialog Fisher-option difference is explicitly checked; it is not an unexplained
  cross-platform numerical mismatch.
- Current Mac native evidence: `.build/help-menu-{native,script}.log`,
  `.build/ai-webview-{report,script,learning}.log`, `.build/merge-main-report.log`.
  These cover menu actions and workbook selection, WebView recovery/selection,
  session-sharing boundaries, report editing/interchange and engine-generated
  PEFR/agreement results. Native GUI tests do not individually click every possible
  branch of every operation.
- Windows chat confirmed live source routes, rather than inferring features from
  library capability. Its fresh audit resolved all 208 menu operations, checked
  all 277 definitions/60 guarded conditions, grouped-data/ANCOVA selection and
  42 native HTML5 Help checks. Its fresh full Continue in R run passed 163 checks
  using R 4.6.1, covering 227 recipe/help comparisons, actual calculations,
  regression follow-ons and the script window. Logs in the Windows workspace:
  `outputs/parity-audit-htmlhelp.txt` and `outputs/parity-audit-rscript.txt`.
  It also reports today's 32 shell checks passing, and existing evidence for
  258 WebReports, 23 installed Word/Excel, 217 Learning and 27 shared checks;
  seven physical clipboard checks were skipped to preserve the user's clipboard.
  These are Windows-session reports, distinct from tests executed on this Mac.
  No Windows production source was changed by the audit.
- Mac lesson comparison found exactly four substantive lesson revisions plus the
  review-status wording on all twelve. `resources.json` and
  `provider-course-example.json` match semantically. See
  `Docs/Learn/CONTENT-REFINEMENTS-2026-10-12.md` for the numerical/method evidence.

### Release gates

1. Close the concrete feature gaps above, or explicitly agree a common supported
   scope for legacy formats/languages. Fix the Windows File/Open routing defect.
2. Freeze matching engine, R recipes, lessons, Help and shared-editor revisions;
   record platform adaptations instead of silently diverging copied content.
3. Run the same colleague workflow on both packaged candidates: open test.xlsx;
   drag PEFR Before/After; Paired t + agreement + Run; append to the active report;
   edit/copy/resize/undo and export; Continue in R; Open in R with results/plot;
   ask Report and Script AI, reusing consent until a new workbook; use Learning
   with the same example and export the learner's record.
4. Exchange representative edited XLSX/CSV, HTML reports with tables/charts and
   run records, generated R scripts and provider course packs in both directions.
   Check actual Office paste, final screenshots and relevant accessibility/keyboard
   paths on both operating systems.
5. Test signed release packages, clean-machine setup/upgrade/uninstall, true
   missing-R and AI-runtime installation, a real account sign-in/reply, and update
   discovery from the published previous version. Mock protocol/installer tests
   are valuable but do not establish this final package acceptance.

The public Mac release remains `v0.3.29` (12 October); current local metadata also
says 0.3.29, not 1.0. The Windows chat reports its signed 5.2 installer predates the
latest Help and Learning commits. Neither existing installer therefore represents
the final proposed parity candidates. Version bumps and publication are separate
from this audit.

Both chats agree: close these gaps and execute the common packaged workflow before
describing Windows 5.2 and Mac 1.0 as functionally equivalent. This audit is not an
instruction to publish, to change version numbers, or to remove legacy functionality.

## Historical implementation and acceptance notes

Approved scope: direct workspace startup, learning under Help, contextual script AI,
guided R installation, and the same document/analysis workflows on both platforms.
These are local review builds, not a release or a claim of complete feature parity.
No calculation algorithms changed. The initial host work left shared report-editor
files unchanged; the later chart-alignment changes below modify the Mac copy.

## Mac host changes

- Finder/Open With events use the existing Excel, CSV, R data, R script and report
  importers. Events arriving before the window exists are queued until startup.
- A successful file open removes only the untouched initial blank worksheet. Edits,
  other open documents and failed imports preserve the user's work.
- File → Open Recent uses macOS recent-document storage, supports reopening and
  clearing, and includes successfully saved editable documents. Bundled examples
  stay in Help rather than retaining paths into an old application bundle.
- File associations are alternate handlers, leaving the user's default applications
  in place. Legacy RTF is an import format; no RTF writer was added.
- Open in R offers the existing verified R installer when R is absent, retains the
  script, and resumes the requested action after installation. Run and Open in R
  share the setup window; cancellation preserves the document.
- Tutor calculations use the engine's report headings directly, matching reports
  created from the analysis menu without adding a duplicate host title.

## Acceptance cases

| Workflow | Mac executable check | Windows counterpart |
| --- | --- | --- |
| Blank startup and explicit-file startup, failed import, edited blank preservation, recent files | `Scripts/test-startup-r-setup.sh` | Direct MDI startup, requested file, New/Open/Recent |
| Missing R: retry, postponed/cancelled download, incomplete installation, resume once | `Scripts/test-startup-r-setup.sh`; `Tests/r-installation-test.swift`; `Tests/test_r_install_download.py` | Guided setup with per-user and machine R detection |
| Select PEFR columns → Paired t → agreement → one Run → same active report | `Scripts/test-paired-workflow.sh` | Same selection/Run sequence |
| Regression/ANOVA follow-ons preserve parent data/results | `Scripts/test-follow-on-workflow.sh` | Parent/child operation regression checks |
| Report → Continue in R → exact script/data, result and agreement plot; external R startup | `Scripts/test-r-integration.sh` | Script generation, Run and Open in R |
| Single toolbars, narrow-window overflow, selection-preserving edit commands | `Scripts/test-unified-toolbar.sh` | Native report/script/grid toolbar checks |
| Styled reports, tables/charts, clipboard and HTML/PDF/DOCX | `Scripts/test-report-export.sh` | Existing report and clipboard/export checks |
| Learning reads only approved documents; worked example → calculation and R | `Scripts/test-learning-workspace.sh` | Native learning bridge and document scope checks |
| Learner/provider options, course pack, MCQs, evidence and assessment export | `Scripts/test-provider-learning.sh`; `Learn/*.test.mjs` | Windows learning content/host checks |
| Script AI: per-question scopes, compact consent, read-only context, cancellation | `Scripts/test-script-ai.sh` | Windows dock and fake app-server checks |

The native R setup fixture injects availability and a package handoff. It does not
remove R or launch an installer. It resumes scripts using the real installed R.
Package tests separately reject invalid URLs, redirects, oversized/corrupt/unsigned
files, and check cancellation cleanup. The production installer still verifies the
pinned SHA-256 and macOS publisher signature before handing off to Installer.

AI transport tests use a local fake app-server and synthetic/example data. They do
not send a live model request or email. A live sign-in/reply and installation on a
clean machine remain release acceptance tasks, not results inferred from mocks.

## Coordination

The Windows chat is implementing native startup, R setup, Learning/Options and a
script AI dock, reusing the Mac course/lesson and tool contracts. The official
OpenAI app-server runtime is packaged per platform, with its license, provenance
and pinned digest; credentials are never included. Platform-specific wording must
be adapted. Builds and test evidence are reviewed before either release is changed.

## Verification status

The release-configuration Mac build is at `.build/cross-platform-final/StatsDirect.app`.
`parity-final-build.log` records 1,552 distribution checks, successful compilation and
matching debug symbols. Deep/strict code-signature verification passes.

Passed:

- Startup and R setup native checks (`startup-r-setup-checks.log`).
- Actual Launch Services file opening (`parity-finder-open.log`): the requested
  script opens alone, without a chooser and without executing its contents.
- R package validation plus six HTTP/cancellation/cleanup cases
  (`parity-r-download-checks.log`); no installer executed.
- All 27 learning-library JavaScript checks (`parity-learning-model-checks.log`).
- Native learning workspace, provider/course-pack, script AI, paired workflow and
  R integration suites (`parity-<suite>.log`). These include actual engine/R results
  and plots, but mocked AI transport.
- All 101 parent/follow-on paths, covering all 67 follow-on operations, the active
  report, inherited help and output to the original worksheet/range.
- Report editing, transfer/deletion/undo, Creole styles, Office clipboard and
  HTML/PDF/DOCX round trips (49 PASS groups); unified toolbar checks (20 groups).

Mac acceptance is complete for the cases above. Windows Learning, AI and R setup
passed 101 native checks, including direct engine calculations for the same ten
methods: TPaired, UnivariateSummary, Chi2by2, ExactFisher, Wilcoxon, TUnpaired,
Spearman, Agreement, Normality and QuickSummary. Tests include the nine-pair PEFR
result (t = 4.9257744860354), agreement SVG and real R replay; duplicate requests add
one result; missing pairs retain alignment; stale, cancelled and unapproved data
cannot produce a report. Windows script AI remains read-only. Its 173 existing
WebView2 report checks, 28 shell checks and 27 shared lesson/provider/R content
tests pass. The pinned Windows app-server starts under its strict isolated
configuration with no inherited sign-in. The full Continue in R suite passes all
162 checks, covering all 227 manifest recipes, real engine examples, follow-ons,
grouped frames, moved-column provenance, cancellation and script-window controls.
In-flight data edits, cancellation at the queued report append, and subsequent
report recovery also pass. The Windows release build succeeds with its existing
NU1701 compatibility warning; no new build errors are present.

Windows review executable:
`C:\Users\ieb21\Documents\Codex\2026-09-19\po\work\windows-parity\app\StatsDirect.exe`.
Windows source/runtime provenance and its acceptance notes are under `Learning/`
in the Windows repository: `acceptance.md`, `README.md`, `upstream.lock.json` and
the complete `changed-files.txt` review list. Windows remains on
`feature/windows-unified-toolbars`, HEAD `575d7e58`; Mac remains on
`feature/mac-unified-toolbars`. Both local review builds are ready.
No version bump, commit, push or release was made.

Before release, exercise a real personal ChatGPT sign-in/question, a true missing-R
installation including OS elevation/cancellation/resume, clean Windows 10/11
installer/upgrade/uninstall, and representative file interchange on both machines.
Office payload/export checks passed automatically; physical pasting into Word,
Excel and PowerPoint was not repeated in this pass.
At that acceptance checkpoint, shared editor and engine pins remained unchanged.

## Subsequent Mac UI review

The toolbar-contrast Mac review build is `.build/icon-contrast/StatsDirect.app`. Script AI now
places sharing, Your question and Send/Stop above Conversation, retains usable
controls/history in short docks, and preserves reading and copying while replies
stream. Window precedes Help in both menu bars. Within Help, Example workbook has
its own section before updates, and About StatsDirect is last. The Script toolbar uses AI followed by
the R+ icon for Open in R, reflecting the subsequent toolbar correction.

All 54 native Script AI/layout/menu checks pass (`ai-layout-checks.log`), including
opening the actual example workbook, per-question consent, retained drafts,
cancellation and stable streaming. Expanded, confirmed and short-window captures
were inspected. Release build, matching symbols and strict signature checks pass
(`ai-layout-final-build.log`). These Mac-only follow-ups remain uncommitted and
unpublished; the release qualifications above still apply.

The subsequent R+ toolbar build and all 53 R integration checks pass
(`r-plus-toolbar-build.log`, `r-plus-toolbar-checks.log`), with strict signature
verification and a visual check of the native AI/R+ icons.

The final menu-order build passes all 55 native Script AI/layout/menu checks
(`help-menu-final-checks.log`), including the order of both menu bars and the Help
sections. Release compilation, matching symbols and strict signature verification
pass (`help-menu-final-build.log`).

The Script toolbar now uses the system label tint for its enabled icons, including
More, instead of AppKit's muted default template tint. Light/dark appearance previews
confirm that enabled commands have stronger contrast while unavailable commands
remain faded. All 53 R integration checks, the Release build, matching symbols and
strict signature verification pass (`icon-contrast-r-checks.log`,
`icon-contrast-build.log`). The user's running session has not been restarted.

## Subsequent chart alignment

The latest review build is `.build/chart-alignment/StatsDirect.app`. New charts
default to left alignment. Left/Centre/Right operate on selected charts as well as
text, with the correct button state, resize anchor and unified undo. HTML, PDF,
DOCX and clipboard output preserve the choice; existing explicit chart alignments
are retained on import. The Mac copy of five shared editor modules and three
generated bundles now differs from pin `4e9f9d1`; see
`Docs/mac-unified-toolbars-2026-10-12.md`. No Windows source or engine changed.

The full native report suite and eight Report JavaScript tests pass, including
rendered PDF geometry, responsive HTML reopening, Word drawing alignment and
existing report/clipboard regressions. Release compilation, 1,552 distribution
checks, matching symbols, packaged-asset comparison and strict deep signature
verification pass. Logs: `.build/chart-alignment-full-report-checks.log` and
`.build/chart-alignment-build.log`. Nothing was committed, pushed or published;
the running user app was left open.

The subsequent Windows catch-up is now explicitly authorised by Iain. It also
identified root report margins retained by standalone SVG downloads. The shared
`exportableSvg` cleanup is applied on both platforms; the Mac native alignment
suite and eight JavaScript tests pass. The refreshed Mac review app is
`.build/chart-alignment-svg/StatsDirect.app` (unchanged Release binaries, regenerated
editor assets, strict signature and matching-symbol verification passed).

## Windows catch-up completion

The Windows development branch now includes the AI-then-R+ Script toolbar,
left-default charts with selected-picture alignment, and the revised Help menu.
Updates moved from Tools to Help; Help remains after Window. Iain gave a newer
direct instruction in the Windows chat to put **Example workbook last**, in its
own section after About. That Windows-specific order supersedes the earlier
before-updates request for this review build; the Mac menu was not reordered here.

Windows validation passes: 217 native WebView2 report checks, 23 checks with
installed Word/Excel, 131 Learning/AI/R-setup checks, 163 R workflow checks,
28 shell checks and eight shared-editor JavaScript tests. Rendered PDF alignment
is checked and editing focus outlines no longer appear in Windows print output.
The Windows importer has a scoped default that preserves incoming stylesheet
alignments. Shared editor source uses the same standalone-SVG margin cleanup as
Mac; Windows-specific importer/default/print adaptations stay in its host/build
adapter. The full Mac report suite also passes after that shared cleanup.

Windows review executable:
`C:\Users\ieb21\Documents\Codex\2026-09-19\po\work\windows-parity\app-mac-catchup\StatsDirect.exe`.
Its Release build passes with the existing NU1701 compatibility warning. Evidence
is in that workspace's `outputs/windows-catchup-*.txt`; source provenance is in
Windows `ReportEditor/chart-alignment-port.md` and `Learning/acceptance.md`.
Validation above was completed before the source handover. Iain subsequently
authorised committing and pushing both development branches in his name:
`feature/mac-unified-toolbars` and `feature/windows-unified-toolbars`. This source
handover does not merge the branches to main, build an installer or replace either
released application. Existing clean-machine/live-sign-in release qualifications
remain applicable; earlier no-commit/no-push notes describe their test checkpoints.

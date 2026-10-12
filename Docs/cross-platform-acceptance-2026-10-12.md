# Mac and Windows workflow alignment

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

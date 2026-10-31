# Mac 1.1.0 release qualification

31 October 2026. The calculation engine remains pinned to 5.2.9 / `2652fee4`.
No installer, release asset, signing handover or release promotion is produced by
these checks. Signed and notarised 1.0.0 remains live.

## Release configuration

The normal app enables the interactive R console independently of prototype
identity, packages and signs its native worker, and verifies matching debug
symbols. It starts with a blank workbook and retains automatic update checks.
R files and AI suggestions open unexecuted in Script view; Continue in R runs its
generated script once. Managed C#/VB editors and external R+/Open in R remain
available. Bundled learning examples retain their explicit run behaviour.

First-use setup detects Intel/Rosetta R and guides native Apple Silicon R setup.
SVG dependencies use official CRAN Mac binaries in the app's private library,
with staged installation, a fresh-process smoke check, cancellation and retry.
Native Find and Print support both Script and Console views.

The old CI failure required generated help footers which had deliberately been
removed. Report tests now check their absence and retain help metadata through
save/reopen. PNG export also has one deadline covering loading and asynchronous
decoding, with cancellation and post-load renderer-failure cleanup.

## Local checks

- Normal optimised Release app build: passed. All 20 native binaries support
  macOS 14; host, engine, text bridge and R worker have matching debug symbols.
  Strict deep ad hoc signature verification passed.
- Worksheet, report and learning JavaScript: 115 passed. R console model and
  renderer-recovery checks: 15 passed.
- PNG renderer lifetime failures: seven passed, including held decoding,
  cancellation, closed owners, process termination and invalidated contexts.
  Five existing raster rendering checks passed.
- First-use setup: five checks passed; three native-architecture check groups
  passed. The setup/installer Swift files typechecked independently.
- Fresh private SVG support: ten official CRAN binary packages installed in an
  isolated temporary library; a fresh R process verified `svglite 2.2.2` and
  generated a complete SVG. The temporary library was removed. The user's R
  installation and default libraries were unchanged.
- Worker signing: three policy/component checks passed, including recorded
  Developer ID routing without Keychain access and 39 real embedded-R checks
  under a hardened ad hoc signature. Only the worker permits loading external
  R libraries. Actual Developer ID signing/notarisation and verification of the
  returned app remain part of the IT Services handover.
- Report export and editing: the complete native suite passed in two segments
  after correcting stale menu expectations and waiting for real asynchronous
  clipboard completion. Notebook schema/executed-cell validation, imported R
  replay, DOCX styles/tables/links/numeric formatting, alignment and five
  independent imported SVG charts all passed. Notebook verification used the
  existing isolated Python environment with `nbformat 5.10.4`, matching CI.
- Production console: native WebKit/R checks passed in two segments after a
  fixture was made to wait for the actual rendered chart before selecting text.
  They cover AI sharing/context, source recovery, chart copy/export and zoom,
  devices, history and scrolling, Find, Script/Console printing, passive imports,
  C#/VB routing and immutable external R handoffs. The complete suite runs
  without segment flags in CI.

## CI

The main workflow builds the current app and runs engine/R comparisons, Excel
and data-file checks, native workflows, report export, Office SVG fonts, PNG
failure cleanup, production console/AI/Find/Print checks, guided R setup,
AI sharing/recovery and the complete WebKit integration driver. Legacy R-pane
fixtures explicitly select the legacy host; public workflow fixtures select the
production console. CI results are attached to the exact pushed commit.

Previous engine, Excel and worksheet suites had already passed at `8fb4f73`;
the final workflow checks them again against the release changes. No Windows
source or engine submodule was modified. The Mac console UI adds a capability
gated R+ button, hidden for hosts which do not supply that capability; this was
reported to the Windows session.

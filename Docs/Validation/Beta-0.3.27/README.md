# Mac 0.3.27 — AI dock and analysis workflows

This release packages the tested application from `2de31e4fb2b422e1c81fcf667e6c7201c592dbd3`.
Its calculation engine is 5.1.0 at `3cc4cbc92ab779880d7fc8f04d1a94ee47e2b620`.
Later engine changes on main are deliberately outside this release.

The release changes the application version to 0.3.27 and renews its outer ad-hoc
signature. All other resources, engine binaries and the native executable with
its signature removed are byte-identical to the tested application. No Windows,
shared editor or numerical source changes are included in release preparation.

The [integration record](../../../Tests/verification.md) documents the completed
Release build, 208 menu hosts, 66 grouped workflows, 113 run-record checks,
227 R recipe/help comparisons, 109 JavaScript tests, native AI/analysis/R/help
checks, Excel and data-file regressions, and the complete native report and form suite.

Release validation checks the extracted application, strict deep local signatures,
matching native debug symbols, source/resource identity and update version handling.
The paired-workflow test now selects the worksheet tab and waits for rendering
before its single synthetic drag, then waits for selection propagation. The
report toolbar and worksheet write-back test timing fixes from `3519ba3` are also
included as test-only changes. The imported-workbook notice check also waits for
React to render after the native import has finished. These waits do not change
the shipped application.

The package is for Apple Silicon and macOS 14 or later. Apple Developer ID signing
and notarisation remain outstanding; the beta retains its existing ad-hoc signature.


## Package verification

The extracted archive passed the complete local native beta suite and the independent
DOCX/clipboard package checks. All 982 Help files match the offline manifest. The
same ZIP passed the [macOS 15 packaged integration suite](https://github.com/iain-buchan/statsdirect-mac/actions/runs/38156543087).
The paired workflow, including one drag and one Run with agreement, passed locally
and on the hosted runner after waiting for worksheet rendering.

The [archive assembly job](https://github.com/iain-buchan/statsdirect-mac/actions/runs/38156223853)
verified the exact tested ZIP checksum. GitHub asset sizes and SHA-256 digests match
the local files. Both archived and extracted native symbols match the application.

- Application ZIP: 157,710,999 bytes; SHA-256 `501f4e9b6c77c4be14443e488f37b9c9419046ed3c6c7e355c5010f9250e33fe`.
- Symbols ZIP: 2,235,649 bytes; SHA-256 `71f0e63b3c1f91e23518299035d840b77010cb7453c39d978255ec3dbe55648a`.

The complete [GitHub build and regression suite](https://github.com/iain-buchan/statsdirect-mac/actions/runs/38156183602) also passed, including the engine/R comparisons, selection and analysis forms, Excel/data files, Help, Calculator, report exports, R integration, AI dock/sharing and the final native integration stage.

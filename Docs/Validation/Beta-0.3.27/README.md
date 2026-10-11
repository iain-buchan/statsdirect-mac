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
included as test-only changes. These waits do not change the shipped application.

The package is for Apple Silicon and macOS 14 or later. Apple Developer ID signing
and notarisation remain outstanding; the beta retains its existing ad-hoc signature.

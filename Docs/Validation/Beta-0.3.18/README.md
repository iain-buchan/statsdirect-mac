# Mac 0.3.18 package validation — 8 October 2026

Source: `5792a8b` plus the 0.3.18 version change. Engine source remains **5.0.14**,
submodule `b10edfefa54bb9ebcdb36b9019b428f75c7d136d`. No numerical engine source changed.

## Included changes

- Typed column storage, streaming Excel and R-data transfers, generic embedded entry tables
  beyond the former one-million-cell cap, and the Excel Swift actor-isolation fix.
- Follow-on analyses using their parent data; grouped column/identifier layouts, including
  nested and replicated two-way ANOVA; duplicate-combination validation, preserved retries,
  first-use defaults, compact nested subgroups and text identifier columns in R snapshots.
- Tutor sharing off by default, per-question native confirmation saved before access,
  single-document scope, likely identifier heading blocking, and institutional tutor-disable
  policy with local learning retained. See [privacy controls](../../Learn/TutorPrivacy.md).

## Verification

The application source was verified immediately before packaging with the complete engine/R
regression suite, all **82 JavaScript tests**, native grid/analysis/report/learning checks,
mock tutor protocol and policy tests, and Swift compilation with warnings treated as errors.
Details are in [the source verification record](../../../Tests/verification.md).

The 0.3.18 package build passed its pinned-source check and **1,552 distribution checks**.
Additional release checks passed:

- `test.xlsx`: all 11 sheets, 14,363 populated cells, 22 formulas, cached results, styles and
  types survive edits. Typed snapshots and streaming patches agree. Excel edge cases cover
  1904 dates, shared-formula references, chart sheets, part-name escaping/case, control
  characters, duplicate sheet names and failed-open/save cleanup.
- Native CSV/RData/RDS round trips, encoding variants, factor/NA levels, dates/timestamps,
  row names, non-finite values, Unicode and edit/failure handling.
- Update-service version comparison, release filtering, URL validation and network fallback
  fixtures.
- ZIP integrity, version 0.3.18 after extraction, identical extracted executable/engine/web
  assets, credential-file exclusions, deep strict local code-signature verification and
  preservation of OpenAI's original runtime signature (team `2DC432GLL2`).

The final native integration check uses **the ZIP's extracted resources and engine** via
`python3 Tests/run_beta_feedback.py --app '.build/release-0318-extracted/StatsDirect Viewer.app'`.
It covers privacy/consent and offline learning, provider courses, report exports/clipboard,
10,000 × 10 worksheet paste, a 1,048,576-row entered summary, a 500,001 × 2 prefill, and
nested group/subgroup selection, fallback and R labels.

## Package identity

`StatsDirect-0.3.18-macOS-arm64.zip` — **156,586,980 bytes**.

SHA-256: `570acfb62b206cdb49d7c0bc5fecde2ced8afaf1350d2bf4ec73b021e4f70a89`.

The published ZIP is reconstructed using the existing verified-transfer workflow to avoid
uploading unchanged runtime bytes over a slow connection. Its full size and SHA-256 must
match this exact locally tested ZIP before publication. The release also includes
`SHA256SUMS.txt`.

## Installation and limits

Apple Silicon, macOS 14 or later. Expand the ZIP and copy **StatsDirect Viewer.app** to
Applications, replacing the older app after saving work and quitting it. Installation is
manual. The app is locally ad-hoc signed; Apple Developer ID signing and notarisation remain
pending. macOS may require Privacy & Security → Open Anyway after an opening attempt.

Tests used a local mock tutor and did not request Keychain credentials, send live AI data,
or send email. Managed-policy deployment by an institution was not performed. Identifier
heading checks are not anonymisation. Some specialised entry forms retain their own limits;
grouped-covariance identifier input remains pending. Intel Macs are not supported by this
package.

# Mac 0.3.19 package validation — 8 October 2026

The application is now **StatsDirect.app**, with **StatsDirect** as its executable,
display name and application-menu name. The bundle identifier remains unchanged so
settings, learning records, institutional policy and account storage keep their existing
locations. Build instructions and native test launchers follow the new name; launchers
read the executable from the source app plist so older packages can still be tested.

Source: 0.3.18 (`f9196c1`) plus this naming release. Engine 5.0.14 remains pinned to
`b10edfefa54bb9ebcdb36b9019b428f75c7d136d`. Numerical and application functionality is
unchanged; see [0.3.18 validation](../Beta-0.3.18/README.md) for its full regression run.

## Verification

- Fresh build passed pinned source/asset checks and 1,552 distribution regression checks.
- Extracted release launched successfully; the actual macOS application menu reads
  StatsDirect, and About shows StatsDirect 0.3.19, engine 5.0.14 and the pinned revision.
- Native report tests passed against the extracted resources/engine: paired-t/agreement
  and chi-square results, HTML, five-page PDF, DOCX, HTML reopening and full/partial/empty
  clipboard paths. The updated report test launcher reads the renamed executable correctly.
- ZIP integrity, application/executable/display names, unchanged bundle identifier,
  extracted executable/engine/web byte equality and credential-file exclusions passed.
- Deep strict ad-hoc signature verification passed. The bundled official tutor runtime
  retains its original vendor signature, team `2DC432GLL2`.
- Shell syntax and Python compilation checks passed for changed scripts.
- The release-transfer helper handles the old/new app prefixes. Local reconstruction
  from the 0.3.18 ZIP reproduced the complete 0.3.19 ZIP byte for byte and by SHA-256.

## Package

`StatsDirect-0.3.19-macOS-arm64.zip`: **156,531,516 bytes**.

SHA-256: `f24553baf0029b0c87216d432338bb06186ffc944495781e0f64f2b07d14553d`.

Apple Silicon, macOS 14 or later. Expand the ZIP and copy StatsDirect.app to Applications.
After saving work and quitting the old app, remove StatsDirect Viewer.app to avoid keeping
both names. Existing settings and learning records remain in place. Installation is manual;
Apple Developer ID signing and notarisation are still pending. This naming release does not
repeat the full engine/R and native learning suites already recorded for 0.3.18.

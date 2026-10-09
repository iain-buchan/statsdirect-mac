# Mac 0.3.20 validation — 9 October 2026

Integrates the Windows and Mac work through Mac commit `9e60f13`, then adds an optimised
native Release configuration and a bounded CI retry for the observed WebKit timeout.
The app remains named **StatsDirect**, with its existing settings and account identity.

## Incorporated work

- Engine **5.0.14**, revision `00aa1ced98e02b8b72e345c8a0d89c2dc8900e42`.
  This includes the Windows identifier-selection and covariance missing-value fixes,
  removal of unreachable operations, and HTML report value encoding.
- Help **2000ba0e199fcc3ab27cddf2f6f52157e5d9360d**, 399 topics from the help repository's
  `Docs` build. The retired engine WebHelp copy is not used.
- Grouped covariance from long data with identifiers, including missing replicates.
- Worksheet output placement, selection and undo; inserted columns in eligible opened
  Excel workbooks preserve formats, widths and formula references.
- Help-example replay, chart geometry checks and continuous integration.

## Release build

The Swift shell uses `-O -whole-module-optimization -g`; C++ bridges use `-O2 -g`.
The existing managed engine Release configuration is unchanged. Runtime safety checks
remain enabled; no unchecked optimisation or fast-math flag is used. Debug native builds
are available with `STATSDIRECT_CONFIGURATION=Debug`.

Compiler-generated dSYM bundles are retained outside the app. The build verifies each
bundle's Mach-O UUID against the corresponding executable and requires actual function
locations in the debug information. Release symbols cover the Swift shell (949 functions
with locations), engine bridge (120) and text-measurement bridge (1). Previous local symbol
bundles are archived. Native integration hosts use the same Swift flags as the app.

## Local verification

- Clean build output, pinned-source/asset checks and **1,552 distribution checks**.
- Full `test.sh` engine/R regression suite, **94 JavaScript tests**, all **33** baseline
  help-example replays, and the twelve chart-geometry test groups passed.
- Rebuilding Grid, Report and Learn reproduces the committed web bundles exactly.
- Excel workbook, edge-case and insertion tests passed, including cross-sheet formula
  references, successive inserts, formats/widths and refusal of unsupported features.
- Native CSV, RData and RDS round trips and failure handling passed.
- The optimised native integration host passed using the final ZIP's extracted resources
  and engine: tutor consent/policy and course learning (mock tutor), report HTML/PDF/DOCX
  exports and clipboard, 10,000 × 10 worksheet paste, 1,048,576-row entry summary,
  500,001 × 2 prefill, nested/grouped covariance roles and R labels, and transform
  write-back with one-step undo. No live AI request or email was sent.
- The actual extracted executable launched. About reports StatsDirect 0.3.20, engine
  5.0.14 and revision `00aa1ced98e0`.
- ZIP integrity, binary/web byte equality, version and engine provenance, exclusion of
  credential files and dSYM bundles from the app ZIP, and deep strict ad-hoc signing passed.
  The bundled official tutor runtime retains its original `2DC432GLL2` vendor signature.
- Both ZIPs passed integrity checks. Local verified transfer reconstructed the installer
  from the previous release byte for byte, with the same complete SHA-256.

## CI timeout handling

The upstream `9e60f13` CI run failed during the native interface waits after the million-row
entry test; earlier steps passed. Wait failures now identify the source file and line.
CI retries the WebKit suite once only when this particular wait timeout is logged. An
assertion, compile error, numerical failure or second timeout still fails the job. Both
attempts are logged. Five simulated outcomes verified the shell's exit codes and retry
counts, including pipeline failure propagation under GitHub's default shell. The complete
GitHub Mac job and release checksum verification are publication gates.

## Packages

- `StatsDirect-0.3.20-macOS-arm64.zip`: **156,191,030 bytes**.
  SHA-256: `2cf007ad1eca21d48048c971c7bc748d69d096fdc9db38ab0e87b3bc68ebb0e7`.
- `StatsDirect-0.3.20-macOS-arm64-symbols.zip`: **1,944,826 bytes**.
  SHA-256: `f0e78b5cd438d13eef015eca89096891cb35a7e728b61092d4bed91483f3b2b5`.

The symbols archive is for crash diagnosis; users need only the application ZIP.

## Remaining limits

Apple Silicon, macOS 14 or later. **Apple Developer ID signing, hardened runtime and
notarisation remain pending the Apple Developer account.** The downloaded beta therefore
still needs the per-app Open Anyway exception. Intel support is not included. Existing
Excel insertion safeguards remain; they are not silently relaxed. The help-example survey
still lists harness coverage gaps and does not establish parity for every help page.

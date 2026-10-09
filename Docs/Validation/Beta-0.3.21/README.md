# Mac 0.3.21 — Excel reading compatibility

Opening and reading workbooks is separate from the safeguards on inserting columns into existing workbooks. File → Open and the grid’s Open Excel action accept `.xlsx`, `.xls`, `.xlsb`, `.xlsm`, `.xlt`, `.xltx` and `.xltm`.

## Implementation

- Ordinary XLSX retains the existing streaming reader and preserving edit/save path. Protected sheets, tables, merged cells, named ranges, validation and large worksheets remain readable.
- ExcelDataReader **3.9.0**, MIT, reads BIFF2–8, XLSB, Strict OOXML, macro-enabled and template workbooks, and supported encrypted workbooks. The library and licence are packaged in the application.
- Compatibility imports load all worksheet values, including hidden sheets, into the existing typed snapshot/grid pipeline. They retain coordinates and value types. Formula values come from the last Excel save; formulas, formatting, charts and macros are not copied. A persistent note explains this, and save writes a new `.xlsx` without overwriting the original. Macros do not execute.
- Encrypted files use a native secure opening-password field with retry and cancel. Passwords are not saved. Failed opens remove partial snapshots; cancelled opens create no document. No decrypted source package is retained.
- Old BIFF files with out-of-order row records retry in the reader’s indexed mode. Out-of-range date-formatted numbers remain numbers rather than preventing XLSX import.
- Source-column insertion restrictions remain unchanged. The calculation-engine source remains pinned at **5.0.14 / 00aa1ced98e02b8b72e345c8a0d89c2dc8900e42**; help remains **2000ba0e199fcc3ab27cddf2f6f52157e5d9360d**.

## Verification

- `Tests/test_excel_compatibility.py`: cell-for-cell comparison with an independent XLSX reader; grid export of every imported cell; XLS/XLSB/Strict XLSX; BIFF2–5; cached formula values, errors, identifiers, Unicode, dates and times; templates and macro-enabled packages; hidden/empty sheets; protected sheets, merged cells, tables, named ranges and validation; out-of-order row blocks; corrupt-file cleanup; source preservation; correct/missing/incorrect passwords with legacy XOR/RC4 and OOXML standard/agile encryption.
- A generated import contains **1,048,577 populated cells**, reaching row **1,048,576** and column **XFD / 16,384**. Decoded snapshot counts, coordinates and values are checked. There is no million-cell import cutoff; this does not establish that an entirely dense maximum-size worksheet fits in RAM.
- Native Excel integration checks cover secure password/cancel/retry, decrypted data in WKWebView, clearing the password field, snapshot loading, full data-copy export, the persistent notice and protection against overwriting the source through its path or a filesystem alias.
- Existing Excel round-trip, edge and column-insertion suites pass. The full engine/R regression suite, 94 JavaScript tests, 33 baseline help examples and chart geometry checks pass. The build passes the pinned-source check and 1,552 distribution regression checks with no new Swift warning.
- A separate exploratory survey opens **272 of 278** upstream root-level Excel fixtures smaller than 10 MB (ExcelDataReader tag v3.9.0, commit `f3343f5524518923bdeb4801e5003c0417fd35f3`). The remaining six are explicit corrupt/empty fixtures: EmptyZipFile.xlsb, EmptyZipFile.xlsx, FailBinary.xls, Issue382_Oom.xls, Issue5.xls and OldIssue12556_Corrupt.xls. [Recorded outcomes](excel-fixture-battery.json). This survey checks successful opening, not numeric parity for every cell of every file.
- Application/archive integrity, extracted executable/engine/grid byte equality, version, runtime library/licence inclusion, deep strict ad-hoc signature verification and matching usable debug symbols pass. The transfer reconstruction reproduces the tested ZIP exactly.

The full extracted-app native integration suite and the GitHub Mac CI job are publication gates. Native tutor tests use the local mock; no live AI request or email is required.

## Packages

- `StatsDirect-0.3.21-macOS-arm64.zip`: 156,291,199 bytes; SHA-256 `81cb771b3ae30105eb8a81d36367d73b10fd02040de22138168b3bdb8dfff1e4`.
- `StatsDirect-0.3.21-macOS-arm64-symbols.zip`: 1,947,016 bytes; SHA-256 `3fa6b5c5d6339224e31dbd905ebaad210c3d6b343d31144a03f3514c617dc362`.

## Limits

The format list describes supported workbook data, not a complete Excel renderer or calculator. Passwords must be known; corrupt files and unsupported encryption/rights-management formats can still fail. Export from a compatibility import is a values-only, unencrypted XLSX data copy. Ordinary XLSX retains its established preserving editor.

Apple Silicon, macOS 14 or later. Apple Developer ID signing/notarisation remain pending; this beta is still ad-hoc signed and may require the per-app Open Anyway exception. Intel is not included.

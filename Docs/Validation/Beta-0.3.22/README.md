# Mac 0.3.22 — column insertion in formatted workbooks

Analysis output now moves existing columns structurally. A column's values, types, formula flags, R metadata and display width travel together; only new or edited values are exported as cell patches. Undo/redo retains earlier edits at their correct coordinates. A million-row move no longer duplicates all cells into an undo record.

The native host validates an insertion against the original workbook before changing the grid. A revision-checked token prevents a delayed result from overwriting more recent worksheet changes. Unsupported insertion opens the analysis output separately and explains why. The original workbook and any existing save destination remain intact on failure.

## Behaviour checked

| Case | Result |
| --- | --- |
| First column, before/after selection, multiple output frames | Whole columns shift; one undo restores the operation |
| Replace selection | Existing data are replaced without requiring spare columns; formulas remain read-only |
| Earlier edits, typed values, formula cells | Original identities move; save exports only genuine edits |
| Repeated saves and undo/redo | Insertions are applied from the immutable original in their recorded order |
| More than one million cells | Streaming structural insertion; tested with 1,000,010 populated cells |
| Fonts, fills, borders, numeric formats, widths, hidden columns, row heights | Existing formatting retained; original style XML compared byte-for-byte |
| Formulas | A1 references, absolute/mixed references, whole rows/columns, cross-sheet references and shared formulas adjusted; external workbook references stay external |
| Names, print areas, validation, conditional formatting | Ranges and formula references adjusted |
| Filters, hyperlinks, frozen panes | Coordinates and relative filter-column indexes adjusted |
| Charts and drawings | Chart references and drawing anchors adjusted; move/size anchor modes respected |
| Merged ranges, Excel tables and array formulas | Move intact; an insertion splitting one is refused |
| Worksheet protection | Insertion refused when protection disallows it; permitted insertion tested |
| Excel's last column | Overflow refused before grid/file mutation |
| Unsupported coordinate-bearing structures | Specific refusal for legacy VML shapes/comments/controls, pivot/slicer/linked-data metadata, Excel extensions/custom views/consolidation and what-if tables |
| Ambiguous references | Unqualified global cell names and divergent 3-D ranges refused |
| Reading | These editing safeguards never prevent opening a workbook |

The structural transformation streams worksheet rows and preserves unrelated package parts. ClosedXML.Parser 2.0.0, already shipped under its MIT licence, is now an explicit dependency for formula parsing. Small saves recalculate through ClosedXML; streaming saves request Excel recalculation and report uncached formulas. The grid labels cached expressions as original Excel formulas after edits; save/reopen refreshes them, with Excel recalculation first for streaming output.

This remains a data grid rather than an Excel formatting renderer. New result columns use worksheet defaults or a spanning column definition's properties. It does not add arbitrary drag-and-drop column reordering.

## Verification

- `Tests/test_excel_inserts.py`: independent openpyxl/XML checks of the cases above, including the shipped example workbook's shared formulas, actual grid planner/store/export through `Tests/insert-workbook.mjs`, arithmetic recalculation, repeated saving, untouched source/destination checks and temporary-file cleanup.
- `Grid/*.test.mjs`: column identity/metadata, small undo size for a million-row column, atomic failure, final-coordinate edits, kind-only changes and full-width replacement.
- `Tests/write-back-driver.swift`: real WKWebView/native analysis output, file-backed preflight, refusal before mutation, undo and rejection of a stale plan.
- Existing engine/R comparisons, baseline help examples, chart checks, Excel round-trip/edge/compatibility tests and CSV/R file tests remain part of regression validation.
- Source engine unchanged: **5.0.14 / 00aa1ced98e02b8b72e345c8a0d89c2dc8900e42**. Help unchanged: **2000ba0e199fcc3ab27cddf2f6f52157e5d9360d**.

The extracted installer and GitHub Mac CI must pass before publication. Apple Silicon, macOS 14 or later; Developer ID signing and notarisation are still pending.

## Package checks

The local regression suite and all 101 JavaScript tests pass. Excel round-trip, edge, insertion, compatibility and CSV/R data-file suites pass. The Release build has no Swift warnings. Archive integrity, deep strict signature verification, extracted executable/engine/grid equality and usable matching symbols are checked separately.

- `StatsDirect-0.3.22-macOS-arm64.zip`: 156,302,890 bytes; SHA-256 `dee35d7e1e992cfbb65c83f0248389964fa58027f1454e640a7542c7850e8404`.
- `StatsDirect-0.3.22-macOS-arm64-symbols.zip`: 1,950,261 bytes; SHA-256 `6b01624e1525ba08be3714f506550cb1c3ed357ef40586ab19ff76cbdb2738be`.

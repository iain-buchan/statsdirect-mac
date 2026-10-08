# Typed columnar worksheet store

`store.mjs` holds each worksheet column in 4,096-row chunks: a `Float64Array` of values (NaN
where the cell holds no canonical number), a `Uint8Array` of kinds (blank, number, text,
datetime, timespan, boolean, error) and a `Uint8Array` of flags (loaded from a file, modified
since loading). Text that is not the shortest round-trip form of a number lives in a sparse
`Map` per column, formulas in another, and any extra fields a loader attaches (the R data
`rMissing`/`rRaw` markers) in a third. A numeric cell costs about ten bytes, so a worksheet of
Excel's dimensions (1,048,576 rows by 16,384 columns) is bounded only by the data in it.

Measured in Node on an Apple Silicon Mac (`node --test Grid/store-scale.test.mjs`, with
`STATSDIRECT_SCALE_FULL=1` for the 16-column run):

| Paste | Time | Memory, including the undo snapshot |
|---|---|---|
| 1,048,576 rows × 4 columns (one text column) | 2.5 s | 58 bytes per cell |
| 1,048,576 rows × 16 columns | 5.6 s | 44 bytes per cell |

In the grid page itself, a 1,048,576-row CSV loads in 4.5 s and the sheet scrolls to its last
row; exporting it back to CSV takes 0.6 s.

## What stays the same

The public surface the grid, workbook, CSV, R data and tutor code use: `columns`, `rows`,
`get`, `apply`, `paste`, `undo`/`redo`, `paired`, `columnTitle`, `csv`, `usedRows`,
`headerRow`, `excelRows`, `csvRows`, `formulasStale`. Cell text is returned exactly as entered
or imported: a number is stored as a double only when its text is the shortest round-trip
form, so `1.50`, `0012` and `1e21` keep their text. The kind rules are unchanged (they were
`cellKind` in `workbook.mjs` and are now `deriveKind` in the store).

## What changed

- Per-cell metadata is read through `kind(c, r)`, `formula(c, r)` and `loaded(c, r)` instead
  of a `metadata` Map; `count()`, `usedColumns()`, `columnUsedRows(c)`, `forEachCell(fn)` and
  the `canUndo`/`canRedo` getters replace walks over a `cells` Map.
- Loaders call `setLoaded(cells)` (the existing per-cell JSON) or `setLoadedBatches(batches,
  kindOf)` (per-column `{col, rows, nums, texts}` as the CSV loader now produces).
- Undo steps are per-column typed patches with a 50-step, 256 MB budget.
- `paste` scans the clipboard text once (`scanDelimited`) without building rows of strings.
- The prototype's caps are gone from the grid: 100,000 cells per paste, copy and clear, 500,000
  cells for CSV import and export, 1,000,000 rows per analysis. The Excel dimensions are the
  only bound. (The R data export and the Excel open/save paths keep their caps until the
  transfer work below.)

## Excel files: streaming open and save

`FullEngine/WorkbookIO.cs` reads each worksheet part of an .xlsx package with `XmlReader`,
so memory is spent only on the cells a sheet holds (shared strings and cell styles are read
once per workbook; shared formulas are expanded for their dependant cells). The reply lists
the cells as JSON, or, when the request names a `snapshot` directory, writes one typed
columnar file per sheet (`snapshot.mjs` documents the format) that the grid fetches into
typed arrays. A new workbook is written by a streaming XML writer with inline strings. An
opened workbook is patched: through ClosedXML, which recalculates formulas and preserves
styles, when the original plus the edits hold at most one million cells, and otherwise by
streaming each worksheet part and merging the edited cells, in which case formula cells keep
their expressions, lose their cached results and the workbook is marked for recalculation
when Excel opens it (`uncachedFormulas` in the reply tells the user).

The prototype's 500,000-cell, 50 MB, 256 MB and 128-sheet limits are gone. Measured through
the native driver on the 1,048,576-row × 4-column probe workbook (35 MB):

| Step | Time | Engine memory |
|---|---|---|
| Open with a typed snapshot (4,194,304 cells; 55 MB snapshot file) | 2.1 s | 162 MB |
| Save every cell as a new workbook (streaming writer; 34.5 MB file) | 3.9 s | 240 MB |
| Reopen that workbook | 1.4 s | |
| Streaming patch of two cells in the opened workbook | 4.0 s | 155 MB |

(`Tests/probe_big_workbook.py` produced these on a 1,048,576 × 4 workbook written by openpyxl; `Tests/test_excel.py` covers the same
paths on the example workbook, including the streaming patch forced with `stream: true`, and
`Tests/test_excel_edges.py` covers indented and oddly addressed worksheet parts, the 1904 date
system, chart sheets, percent-encoded part names, shared-formula ranges, characters XML cannot
hold, duplicate sheet names and cleanup after a failed open.)

## Moving cells between the engine, the grid and the forms

- `Sources/SnapshotStore.swift` serves snapshot files to pages through the `sdsnapshot://`
  scheme (GET by id) and stores a page's snapshot (POST). Opening an Excel file, saving one
  (`excelSnapshot` in `main.tsx` posts the edited cells as typed columns) and building a
  derived worksheet from an analysis (`snapshotColumns`) and R data files all go through it,
  so cell data is never serialised to JSON or passed through a JavaScript string.
- Analysis forms receive metadata only (`analysis-source.mjs` `analysisMetadata`: column
  titles, the last used row of each column, the selection, and small highlighted rectangles).
  Rectangles above 65,536 cells are deferred until a screen form needs them; this is a
  transfer optimisation, not an input limit. When a step is submitted the form asks for chosen
  columns (`columnValues`), which match `FullEngine/HostParameters.cs` `ReadFrame`'s
  `{columns: [{title, values}]}`. A lesson's fictional data still travels with `cells`.

Reviewed behaviour worth knowing: a form's lazy request names the sheet its metadata came
from and is refused if that sheet is gone or renamed; a step cannot be submitted twice while
its columns are being read; the ChatGPT tutor's view of a form's worksheet input is the chosen
columns and row range (it reads cell values through the grid's own bounded tutor path).

## Embedded entry tables

`entry-table.mjs` uses the same typed store for the analysis forms. There is no one-million-cell
limit on entry or selected-range prefill. Excel's row and column dimensions and each method's
requirements still apply (for example, a 2 × 2 table requires exactly four cells). A paste is
validated before any values change, including quoted tabs/newlines and fixed-table bounds.
Editing a cell changes its column storage; it does not clone the whole table. Column arrays
are built when submitting an answer to the engine. The separate exact r × c prototype's
existing 2,500-cell restriction remains.

`Grid/entry-table.test.mjs` exercises a 1,048,576 × 2 populated table, all 16,384 columns,
large selected ranges, exact text and atomic rejection at the bounds. The native integration
suite (`Tests/run_beta_feedback.py`) pastes 1,048,576 observations into a real analysis form
and verifies the engine's count, mean and sum; it also prefills a 500,001 × 2 highlighted
rectangle through the worksheet bridge. The Excel queue helper is explicitly nonisolated:
it uses supplied function pointers and JSON, while library lookup and completion remain on
the main actor. The Swift host builds with `-warnings-as-errors`.

## R data files

R data files (.rds, .RData) go through base R (`Content/R/data-files.R`) as before, but no
cell is serialised one at a time any more. Opening: R writes one file per column (percent-
escaped text lines, flag bytes, little-endian doubles) and `Sources/RDataFileIO.swift`
turns each table into a typed snapshot file (the snapshot format gained an optional `extras`
group, a JSON object per cell, which carries the R markers `rMissing` and `rRaw`; the engine
skips it). Saving: `r-data.mjs` builds typed column records and a table manifest, the grid
posts the snapshot, and the application writes R's exchange files, formatting numbers as
JavaScript does (`Snapshot.jsNumber`, checked against Node in `Tests/test_data_files.py`).
The 500,000-cell and 50 MB caps are gone; the Excel dimensions remain the bound. Run
`STATSDIRECT_SCALE=1 python3 Tests/test_data_files.py …` for the 1,048,575-row round trip.

## Still to do

1. The values a form sends to the engine for a very large column selection still pass
   through JSON (bounded by the selection, not the sheet).

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

## Still to do for the Excel limit end to end

1. Workbook open and save in `FullEngine/WorkbookIO.cs` load the whole file with ClosedXML and
   cap at 500,000 cells; replace with a streaming reader and writer and a columnar transfer.
2. Analysis forms receive the whole sheet as per-cell JSON (`analysisSource` in `main.tsx`,
   `Sources/OperationHost.swift`); replace with a request for the chosen columns only, in
   columnar form, matching `FullEngine/HostParameters.cs` `ReadFrame`, which already takes
   `{columns: [{title, values}]}`.
3. R data export (`r-data.mjs`) keeps its 500,000-cell cap until the R file path is exercised
   at scale.

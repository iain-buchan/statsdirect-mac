# Glide data-grid tab

This prototype uses Glide Data Grid 6.0.3 and React 18 inside the application's existing WKWebView. JavaScript, CSS and required libraries are bundled into `Content/Grid`; the grid does not require a server, CDN or internet connection. Runtime dependency licenses are included beside the bundle.

Each new worksheet starts empty with 100 rows and eight columns. File → New Worksheet creates another independent tab. It supports cell editing, range/column/row selection, a cell-value field, clipboard buttons, tab-delimited paste, undo/redo, adding rows/columns, and CSV opening/saving through native Mac dialogs. RDS and RData table import/export use the installed R runtime. Excel import accepts `.xlsx`, `.xls`, `.xlsb`, `.xlsm`, `.xlt`, `.xltx` and `.xltm`, including Strict OOXML and supported Excel password encryption. Worksheet names, cell coordinates and data types are retained.

Analysis controls belong to the Analysis menu and its separate forms. The worksheet contains only editing controls and the first-row-header option. The general paired-test form retains the agreement statistics and SVG chart question. File → Open accepts supported Excel, CSV, R and HTML files; File → Export groups output formats. Help → Example workbook opens the bundled StatsDirect workbook.

Native Edit commands call `statsDirectGrid.editCommand` for cell selections, falling back to the normal responder chain when an input field has focus. Undo and Redo use worksheet history; Copy/Cut/Paste use the native clipboard. A blank workbook uses physical worksheet coordinates for all exports, without inserting an implicit header or demo observations.

`store.mjs` uses sparse typed columns behind the grid callbacks, with a typed snapshot bridge for file import and engine transfers. Logical dimensions are bounded by Excel's 1,048,576 rows and 16,384 columns; the grid expands for pasted or generated data. Import has no million-cell cutoff. The compatibility regression reads 1,048,577 populated cells including the last row and column; this is not a claim that a densely populated sheet of every possible cell will fit in memory.

Data are held in the open tab until saved. Excel and RData save all worksheets; CSV and RDS save the current worksheet. Saving CSV does not clear unsaved workbook/R metadata, and saving one RDS does not mark a multiple-table document saved. Closing an edited grid or quitting prompts before discarding unsaved data. R sessions are independent and start with an empty script editor.

## Build and checks

With Node.js and pnpm available, run these commands in this directory:

```
pnpm install --frozen-lockfile
pnpm test
pnpm build
```

Then run `../build.sh` to rebuild the Mac application. The generated browser bundle is checked in, so the Mac build can use it without Node.js. Regenerate it whenever Grid source changes.

The native bridge is `Sources/GridHost.swift`. Only the bundled grid's main frame has access to its clipboard and document message handler. The underlying statistical algorithms remain unchanged.

References: [Glide's setup guide](https://docs.grid.glideapps.com/extended-quickstart-guide), [editing callbacks](https://docs.grid.glideapps.com/api/dataeditor/editing), [selection API](https://docs.grid.glideapps.com/api/dataeditor/selection-handling).

## Excel boundary

`workbook.mjs` tracks worksheets, original cell types and changed cells. It sends changes for ordinary XLSX imports and all populated cells for new worksheets or compatibility imports. Header detection affects analysis, not physical cell coordinates. Existing text identifiers stay text. In ordinary XLSX imports, formula cells are read-only and analysis using potentially stale formula values fails explicitly.

`Sources/ExcelHost.swift` owns native open/save dialogs and calls `WorkbookIO` through the existing in-process .NET bridge. Ordinary XLSX files use the streaming XML reader and an immutable source snapshot, released when the document closes. Existing workbooks are patched using ClosedXML 0.105.1 or streaming for large files; new workbooks use a streaming writer. Saving is atomic and checks the document revision before clearing its dirty state.

`FullEngine/WorkbookImport.cs` uses ExcelDataReader 3.9.0 (MIT) for legacy BIFF, binary, macro-enabled, template, Strict and encrypted workbooks. These open as data copies: cached formula values are available for analysis; formula expressions, formatting, macros and charts are not copied to the grid/export. A persistent note explains this. Export writes all worksheet values to a new `.xlsx` and prevents replacement of the source. Macros are never executed. Opening passwords are requested in a native secure field, used for that request only, and not saved; cancel creates no partial document. Worksheet protection does not block reading. Unrecognised, corrupt or unsupported encrypted files report an error.

Analysis output can insert columns before or after the selection, or at the start, including in large workbooks and before formula cells. The grid moves column objects (values, types, formula flags, R metadata and display widths) with one undo step; exported patches contain only new or edited values. `WorkbookInsert.cs` streams the original package into a structurally adjusted copy before applying those patches. It updates formulas across sheets, shared formulas, defined names, validation, conditional formatting, filters, hyperlinks, frozen panes, print ranges and drawing anchors. `WorkbookStructures.cs` handles table expansion, stable field identities, linked query fields, pivot sources and whole reports, slicers, legacy controls, threaded comments and Excel extension references. Interior table insertions create unique header strings and unbound query fields; merged headings expand. New cells and columns inherit the adjacent formatting. Original style IDs, cache field IDs, metadata indices and unrelated package parts are retained.

The native host checks insertions against the source package before changing the grid, then checks the grid revision before committing. It refuses to split an array formula, PivotTable report or what-if data table, exceed XFD, or violate worksheet protection. Malformed or ambiguous references still need correction before structural editing. Partial-sheet changes leave divergent 3-D references unchanged, following Excel. Every refusal leaves both the grid and existing destination file intact; results can open separately. Formula cells stay read-only; while the worksheet is edited the formula bar labels their expressions as the original Excel formulas. Save and reopen to obtain adjusted expressions/results. Large or feature-rich workbooks use the streaming save path and need Excel recalculation; pivots retain their snapshot until refreshed in Excel. Excel controls and slicers are preserved for Excel rather than rendered by the StatsDirect data grid. No original numerical source was modified.

`Grid/workbook.test.mjs` checks multiple sheets, header handling, changed-cell export, text identifiers, undo and formula safeguards. `Tests/test_excel.py` exercises the native C ABI plus this actual grid model, then uses an independent reader to compare the bundled StatsDirect workbook before/after an edit. Compile `Tests/workbook-driver.cpp`, then run the Python test with the driver path and Node path as arguments (Python requires openpyxl). Formula results are checked separately from retained formula expressions.

`Tests/test_excel_compatibility.py` exercises format detection, legacy versions, password variants, failed-open cleanup, source preservation, complex worksheets and full-height import. `Tests/run_beta_feedback.py --excel-only` verifies the native password/cancel/retry flow, snapshot loading, all-cell export and persistent notice in WKWebView. Both run in CI.

## Embedded contingency form

`chi-square.tsx` is a separate offline entry point for the screen-data form. `contingency.mjs` owns counts, labels, resize/paste and atomic history. The form's seven checkbox names, labels and defaults in `chi-options.json` match the original ExactChiRbyCScreen XML and are checked by a regression test. The original engine validates parameters again in `AnalysisIO`; the form does not calculate test statistics. Native menu, cancellation, report tabs and CSV saving are in `Sources/AnalysisHost.swift`.


## CSV and R data files

`csv.mjs` parses quoted comma-separated records strictly, preserves field text and bounds the rectangular table size. `CSVFileIO.swift` handles UTF-8/UTF-16/Windows-1252 decoding and atomic UTF-8 output. Native CSV import/export is in `GridHost.swift`; CSV document saves participate in dirty-state and revision checks.

`r-data.mjs` snapshots table data and R column metadata. `RDataHost.swift` owns the dialogs; `RDataFileIO.swift` invokes the bundled `Content/R/data-files.R` using `Rscript --vanilla` and isolated temporary files. No shell interpolation or extra R package is used. Base R reads/writes RDS and RData; a quoted text exchange carries values, explicit missingness, factor levels and date/time raw values. A successfully written temporary R file atomically replaces the requested destination. The existing interactive R sessions and the calculation engine are untouched.

Run `node --test Grid/*.test.mjs` from the repository root for model tests. To verify the actual native file boundary, compile `Sources/CSVFileIO.swift Sources/RDataFileIO.swift Tests/data-file-driver.swift` with `swiftc -o /tmp/statsdirect-data-file-driver`, then run `python3 Tests/test_data_files.py /tmp/statsdirect-data-file-driver /path/to/node`. The test uses base R for independent equality checks, including empty/all-missing tables, exact column types, ordered factors, row names, Date/POSIXct values, edits and failed-write preservation. Native open/save dialogs are checked separately in the app.

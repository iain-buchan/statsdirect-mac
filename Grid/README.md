# Glide data-grid tab

This prototype uses Glide Data Grid 6.0.3 and React 18 inside the application's existing WKWebView. JavaScript, CSS and required libraries are bundled into `Content/Grid`; the grid does not require a server, CDN or internet connection. Runtime dependency licenses are included beside the bundle.

Each new worksheet starts empty with 100 rows and eight columns. File → New Worksheet creates another independent tab. It supports cell editing, range/column/row selection, a cell-value field, clipboard buttons, tab-delimited paste, undo/redo, adding rows/columns, and CSV opening/saving through native Mac dialogs. RDS and RData table import/export use the installed R runtime. It also imports and exports `.xlsx` workbooks, retaining separate worksheet stores and their original row numbers. Formula cells are read-only.

Analysis controls belong to the Analysis menu and its separate forms. The worksheet contains only editing controls and the first-row-header option. The general paired-test form retains the agreement statistics and SVG chart question. File → Open accepts supported Excel, CSV, R and HTML files; File → Export groups output formats. Help → Examples contains the bundled StatsDirect workbook.

Native Edit commands call `statsDirectGrid.editCommand` for cell selections, falling back to the normal responder chain when an input field has focus. Undo and Redo use worksheet history; Copy/Cut/Paste use the native clipboard. A blank workbook uses physical worksheet coordinates for all exports, without inserting an implicit header or demo observations.

`store.mjs` is a sparse cell store behind the grid callback. It currently stores text, with numeric validation at analysis time. This is a working interaction prototype, not yet the typed column store proposed for large sheets. Logical dimensions are bounded by Excel's worksheet dimensions; a single paste/copy is limited to 100,000 cells. Million-row performance, memory use, Office clipboard fidelity and very wide sheets have not been benchmarked.

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

`workbook.mjs` tracks worksheets, original cell types and changed cells. It sends only changes for imported files and a complete cell list for a new worksheet. Header detection affects analysis, not physical cell coordinates. Existing text identifiers stay text; formula edits and analysis using potentially stale formula values fail explicitly.

`Sources/ExcelHost.swift` owns native open/save dialogs and calls `WorkbookIO` through the existing in-process .NET bridge. Only paths selected by the native dialogs are used. Each opened workbook has an immutable source snapshot, released when its document closes. Saving is atomic and uses a revision check before marking edits saved. `FullEngine/WorkbookIO.cs` reads via ClosedXML 0.105.1. For existing workbooks it patches cells in the original XLSX package, retaining existing style definitions and unrelated parts; new workbooks are created with ClosedXML. No original numerical source was modified.

`Grid/workbook.test.mjs` checks multiple sheets, header handling, changed-cell export, text identifiers, undo and formula safeguards. `Tests/test_excel.py` exercises the native C ABI plus this actual grid model, then uses an independent reader to compare the bundled StatsDirect workbook before/after an edit. Compile `Tests/workbook-driver.cpp`, then run the Python test with the driver path and Node path as arguments (Python requires openpyxl). Formula results are checked separately from retained formula expressions.

## Embedded contingency form

`chi-square.tsx` is a separate offline entry point for the screen-data form. `contingency.mjs` owns counts, labels, resize/paste and atomic history. The form's seven checkbox names, labels and defaults in `chi-options.json` match the original ExactChiRbyCScreen XML and are checked by a regression test. The original engine validates parameters again in `AnalysisIO`; the form does not calculate test statistics. Native menu, cancellation, report tabs and CSV saving are in `Sources/AnalysisHost.swift`.


## CSV and R data files

`csv.mjs` parses quoted comma-separated records strictly, preserves field text and bounds the rectangular table size. `CSVFileIO.swift` handles UTF-8/UTF-16/Windows-1252 decoding and atomic UTF-8 output. Native CSV import/export is in `GridHost.swift`; CSV document saves participate in dirty-state and revision checks.

`r-data.mjs` snapshots table data and R column metadata. `RDataHost.swift` owns the dialogs; `RDataFileIO.swift` invokes the bundled `Content/R/data-files.R` using `Rscript --vanilla` and isolated temporary files. No shell interpolation or extra R package is used. Base R reads/writes RDS and RData; a quoted text exchange carries values, explicit missingness, factor levels and date/time raw values. A successfully written temporary R file atomically replaces the requested destination. The existing interactive R sessions and the calculation engine are untouched.

Run `node --test Grid/*.test.mjs` from the repository root for model tests. To verify the actual native file boundary, compile `Sources/CSVFileIO.swift Sources/RDataFileIO.swift Tests/data-file-driver.swift` with `swiftc -o /tmp/statsdirect-data-file-driver`, then run `python3 Tests/test_data_files.py /tmp/statsdirect-data-file-driver /path/to/node`. The test uses base R for independent equality checks, including empty/all-missing tables, exact column types, ordered factors, row names, Date/POSIXct values, edits and failed-write preservation. Native open/save dialogs are checked separately in the app.

# Glide data-grid tab

This prototype uses Glide Data Grid 6.0.3 and React 18 inside the application's existing WKWebView. JavaScript, CSS and required libraries are bundled into `Content/Grid`; the grid does not require a server, CDN or internet connection. Runtime dependency licenses are included beside the bundle.

The worksheet starts with the nine PEFR pairs in a 100-row, six-column grid. It supports cell editing, range/column/row selection, a cell-value field, clipboard buttons, tab-delimited paste, undo/redo, adding rows/columns, and CSV saving through the native Mac dialog. It also imports and exports `.xlsx` workbooks, retaining separate worksheet stores and their original row numbers. Formula cells are read-only.

The paired test uses two selected column headers, a two-column rectangular range, or the two column selectors. Blank cells are treated as missing; nonnumeric text in the analysed columns is reported as an error. Columns are transferred to the full C# engine, and their names are passed to its original report renderer. Calculations create separate report tabs. The input snapshot in large reports is limited to the first 1,000 rows and says so explicitly.

`store.mjs` is a sparse cell store behind the grid callback. It currently stores text, with numeric validation at analysis time. This is a working interaction prototype, not yet the typed column store proposed for large sheets. Logical dimensions are bounded by Excel's worksheet dimensions; a single paste/copy is limited to 100,000 cells. Million-row performance, memory use, Office clipboard fidelity and very wide sheets have not been benchmarked.

Data are held in the open tab until saved as Excel. CSV exports only the current worksheet. Closing an edited grid or quitting prompts before discarding unsaved data. The R tabs and the older PEFR example form are independent of this worksheet.

## Build and checks

With Node.js and pnpm available, run these commands in this directory:

```
pnpm install --frozen-lockfile
pnpm test
pnpm build
```

Then run `../build.sh` to rebuild the Mac application. The generated browser bundle is checked in, so the Mac build can use it without Node.js. Regenerate it whenever Grid source changes.

The native bridge is `Sources/GridHost.swift`. Only the bundled grid's main frame has access to its clipboard/save/run message handler. The underlying statistical algorithms remain unchanged.

References: [Glide's setup guide](https://docs.grid.glideapps.com/extended-quickstart-guide), [editing callbacks](https://docs.grid.glideapps.com/api/dataeditor/editing), [selection API](https://docs.grid.glideapps.com/api/dataeditor/selection-handling).

## Excel boundary

`workbook.mjs` tracks worksheets, original cell types and changed cells. It sends only changes for imported files and a complete cell list for a new worksheet. Header detection affects analysis, not physical cell coordinates. Existing text identifiers stay text; formula edits and analysis using potentially stale formula values fail explicitly.

`Sources/ExcelHost.swift` owns native open/save dialogs and calls `WorkbookIO` through the existing in-process .NET bridge. Only paths selected by the native dialogs are used. Each opened workbook has an immutable source snapshot, released when its document closes. Saving is atomic and uses a revision check before marking edits saved. `FullEngine/WorkbookIO.cs` reads via ClosedXML 0.105.1. For existing workbooks it patches cells in the original XLSX package, retaining existing style definitions and unrelated parts; new workbooks are created with ClosedXML. No original numerical source was modified.

`Grid/workbook.test.mjs` checks multiple sheets, header handling, changed-cell export, text identifiers, undo and formula safeguards. `Tests/test_excel.py` exercises the native C ABI plus this actual grid model, then uses an independent reader to compare the bundled StatsDirect workbook before/after an edit. Compile `Tests/workbook-driver.cpp`, then run the Python test with the driver path and Node path as arguments (Python requires openpyxl). Formula results are checked separately from retained formula expressions.

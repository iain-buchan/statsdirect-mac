# Shared notebook format

`ReportNotebook.cs` and `ReportNotebookImport.cs` are exact copies of the platform-independent Windows notebook writer and reader. Their source revisions and SHA-256 values are recorded in `upstream.json` and `import-upstream.json`. Keeping these helpers separately allows the Mac to retain its released calculation-engine pin while sharing the notebook format and validation rules with Windows.

To update it, copy the tested file from the recorded upstream path and update the provenance together. Do not edit the copy independently. The helper uses the BCL and the existing `StatsDirect.R`/`StatsDirect.Templates` types; it has no Windows UI dependency.

`RScriptNotebook.cs` supplies export transport, using the existing data acquisition, hash verification and column relocation for both dataset metadata and R replay. `RScriptNotebookImport.cs` supplies the import transport, preserving recovered records and original provenance as JSON strings across the native bridge. The Swift hosts own file selection, stable report capture, atomic writing and staged workspace recovery. Imported code is never executed by opening a notebook.

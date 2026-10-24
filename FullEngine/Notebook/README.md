# Shared notebook writer

`ReportNotebook.cs` is an exact copy of the platform-independent Windows notebook writer. Its source revision and SHA-256 are recorded in `upstream.json`. Keeping this one helper separately allows the Mac to retain its released calculation-engine pin while sharing the notebook format and input-validation rules with Windows.

To update it, copy the tested file from the recorded upstream path and update the provenance together. Do not edit the copy independently. The helper uses the BCL and the existing `StatsDirect.R`/`StatsDirect.Templates` types; it has no Windows UI dependency.

`RScriptNotebook.cs` supplies the Mac transport. It uses the existing data acquisition, hash verification and column relocation, then reuses those typed values for both dataset metadata and R replay. The Swift host owns the save panel, stable report capture and atomic file write.

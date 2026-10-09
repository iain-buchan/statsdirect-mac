# Mac 0.3.24 — advanced Excel column insertion

## Changes

Column insertion used by analysis write-back no longer rejects an entire workbook because it contains pivots, slicers, connected tables, controls, comments or worksheet extensions.

- Inserting inside an Excel table expands its range, filters and column definitions. Existing field IDs remain stable; new fields have unique IDs and headings. Connected tables receive unbound fields with their query layout retained.
- Merged headings expand. Inserted cells and columns inherit adjacent number formats, fonts, widths and other stored styling.
- Pivot source ranges and complete reports move. Cache records, pivot field indices and slicer identities stay intact. Slicer/drawing anchors follow the owning sheet; refresh remains an Excel operation.
- Classic notes, threaded comments, legacy form-control links, list ranges, VML anchors and modern control/object anchors relocate together.
- Sparklines, extended validation/conditional formulas, dynamic-array metadata, custom views, consolidation sources, cell watches, publishing ranges and connection parameter cells are retained with updated coordinates.
- Divergent 3-D references keep their original coordinate when only part of the sheet group moves, as observed in Excel. Shared formulas, defined names, ordinary charts and formatting retain the preceding release's support.

Complex packages use the streaming patcher even when small, preserving parts that the formula evaluation library cannot interpret. Excel recalculates these saved workbooks. The calculation engine is unchanged at 5.0.14, revision `70eeec462a9c`.

## Automated validation

`Tests/test_excel_structures.py` exercises both ordinary and explicitly streamed requests through the production native C ABI, including a genuine Excel-authored pivot/slicer workbook. It checks preserved IDs and package payloads, duplicate headings, multiple insertions, formatted cells, source hashes, failure atomicity, high field IDs and sparse table headers. CI includes this suite.

The existing insertion tests also pass, including the actual grid export, repeated saves, undo/redo, formula relocation, chart/note anchors and **1,000,010 populated cells**. Excel import/round-trip/edge/compatibility tests and all **101 JavaScript tests** pass. The Release build passes its **1,552 distribution checks** and verifies matching native debug symbols. The complete native WKWebView integration suite passes, including file-backed insertion inside tables/merges, atomic refusal inside an array, undo and stale-plan rejection, alongside the existing report, tutor, grouping and million-row checks.

## Native Microsoft Excel validation

Microsoft Excel **16.113.3** opened the generated table, pivot/slicer, sparkline/validation, threaded-comment, what-if, custom-view and form-control workbooks without repair. Excel accepted and saved the relocated form controls and threaded comments; the resulting packages pass Open XML SDK validation. Native-save verification caught incomplete synthetic fixtures: the control now has a separate proper shape, and threaded-comment tests use a genuine Excel-authored thread including its legacy fallback. A moved thread and its text survive an actual Excel save.

The moved pivot refreshed to A = 40, B = 60, total = 100. Selecting A in its moved slicer changed the total to 40. Refreshing after insertion inside the source range exposed the new field while retaining the original aggregates and usable slicer. The native-authored pivot export and Excel-resaved export pass Open XML SDK validation.

Excel recalculated the expanded table's formula results as 20, 40 and 60. It preserved the relocated sparkline and normalised extended validation to equivalent standard validation on the correct cells. Separate package inspection verifies the persisted coordinates. These checks use fictional QA workbooks only.

External query refresh against a live provider and ActiveX execution were not exercised. Their opaque payloads are retained; StatsDirect does not execute them. Synthetic OOXML tests cover query fields/parameters, metadata, views and object links independently of their display in Excel.

## Remaining constraints

The host still refuses edits that split an array formula, what-if data table or pivot report, violate insertion protection, or exceed Excel's XFD boundary. Native Excel also disables insertion inside the tested pivot and refuses splitting the tested array. Malformed/ambiguous references retain atomic error handling. Reading is unaffected.

This work completes support for the advanced structures previously blocked in **column insertion and analysis output placement**. It does not introduce arbitrary drag reordering, row deletion or an Excel formatting renderer. Excel remains responsible for pivot/query refresh, control execution and recalculation of complex files.

Apple Developer ID signing and notarisation remain excluded. This is an Apple Silicon beta for macOS 14 or later.

## Format references

- [Microsoft extension reference relocation](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-xlsx/4d7cc415-6c51-4c71-8dbd-a2e28bdd9193)
- [Sparkline data and destination references](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-xlsx/6b28a993-e0fd-451d-860e-35097c6baa77)
- [Slicer table-column identity](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-xlsx/c3629be2-99fe-44b7-970c-3ea6df625cf5)
- [Unbound query fields](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.querytablefield?view=openxml-3.0.1)
- [Connection cell parameters](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.parameter?view=openxml-3.0.1)

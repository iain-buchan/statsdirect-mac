# Reports

With a report tab selected, use **File → Save Report…** (⌘S) and choose HTML, PDF or Word (.docx). File → Export also offers each format directly. The complete active report is saved, including results appended by earlier analyses.

- **HTML:** a standalone report with inline styles and charts. Bundled help links become links to the public StatsDirect help site. App-only actions and scripts are removed.
- **PDF:** paginated A4 output using the native WebKit print pipeline, retaining vector charts. Long tables continue across pages; WebKit does not repeat their headings reliably.
- **DOCX:** editable text and tables, merged cells, repeated table headings, hyperlinks, superscripts/subscripts, and SVG charts with PNG fallbacks. Word layout differs from the on-screen report. Closed input-details sections are excluded from PDF/DOCX.

Select report content and **Copy** (⌘C), then paste into Excel. Tables remain cells, numbers remain numeric, and merged headings are retained. Scientific notation is preserved; labels and long numeric identifiers are text. Charts paste as pictures. A tab-separated fallback serves plain-text destinations. Excel retains destination column widths: use its AutoFit Column Width command if long labels need more room. Verification used Microsoft Excel for Mac with normal ⌘V.

## Development

The prebuilt browser bundle and dependency licences are included in `Content/Report`; normal app builds need no JavaScript package installation. Rebuild after changing the exporter:

```sh
pnpm --dir Report install --frozen-lockfile
pnpm --dir Report build
node --test Report/clipboard.test.mjs
Scripts/test-report-export.sh
```

The native test runs the real paired-t/agreement and chi-square engines, exports a combined report with a 65-row table and merged headings, checks PDF pagination, reopens HTML for DOCX export, and checks full/partial/empty clipboard selections. It uses an isolated app, leaves the user's workspace intact, and writes artifacts under `.build/report-export-output`. Add `"$PWD/StatsDirect Viewer.app" --stay-open` for native Office and save-dialog checks.

Report preparation runs offline in an isolated WebKit JavaScript world. Saving is atomic; unreadable images/styles and oversized reports produce an error rather than an incomplete export. Current bounds are 30 MB source HTML, 200 images, and 80 MB base64 DOCX. Very wide tables may need page/column adjustments in Word or a smaller report.

# Report SVG copying into Office on Mac

Main-report Copy Chart and selected-chart Copy/Cut publish the same SVG under
`com.microsoft.image-svg-xml` and `public.svg-image`, alongside PNG. Before
publishing, `OfficeSVG.forClipboard` turns supported chart text into CoreText
glyph paths. Word's Convert to Shape otherwise changes the size and placement
of text, particularly rotated axis captions.

Only the public report clipboard SVG changes. The private report fragment,
editable report, saved/exported SVG, PNG fallback and R chart clipboard keep
their original content. Outlined labels remain vector artwork in Office but
cannot be edited as text there. The SVG paths retain accessible label/title
text. No shared Windows/editor code or calculation code is changed.

The helper handles the canonical exporter's leaf text, installed fonts, regular,
bold and italic faces, transforms and presentation attributes. It preserves
unsupported text verbatim rather than guessing: for example CSS stylesheets,
unresolved fonts, nested tspans, right-to-left runs, color glyphs and advanced
text layout. Parsing, label work and output size are bounded. A conversion
failure returns the source SVG.

## Verification on 31 October 2026

The actual nine-pair PEFR agreement report was copied using the rebuilt Mac
app's Copy Chart command, pasted with Word's Paste Special > Picture (SVG), and
converted with Graphics Format > Convert to Shape in Word for Mac 16.114.1.

Before the fix, all 17 labels became textboxes with incorrect size/placement;
the rotated Y caption moved into the plot. After the fix, visual inspection
confirmed unchanged label positions, axis rotation, nine open points and both
red limits of agreement. The saved DOCX contains one group with 45 shapes:
36 custom paths (19 chart lines and 17 outlined labels) and nine ellipses,
with no textboxes or remaining SVG image. The converted chart remains vector.

Local proof documents are in `.build/word-convert-shape.noindex/`:
`report-before-convert.docx`, `report-converted-before-fix.docx` and
`report-converted-after-fix.docx`.

Automated checks:

- `bash Scripts/test-office-svg.sh`: 67 font, geometry, pixel/baseline,
  preservation, unsupported-layout and work-limit checks passed.
- `bash Scripts/test-report-export.sh /Applications/StatsDirect.app
  --office-clipboard-only`: native context/selected copying, public SVG types,
  PNG, private editable labels, unchanged source/serialization, cut/paste undo
  and Excel table formatting passed. The native fixture also checks all 17
  PEFR labels, nine points and 19 lines.
- `bash Scripts/build-interactive-console-prototype.sh`: optimized native build
  passed; that separate development app was used for the actual Word test.

The frozen 1.0.1 University signing candidate and live 1.0.0 release are unchanged.

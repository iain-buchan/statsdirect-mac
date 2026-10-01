# Simplified Learning Options — Mac 0.3.16

Validated on 1 October 2026 on Apple Silicon macOS.

Learning Options now has two main sections: experience/goals and training provider. Statistical skill level and assessment type are saved, exported and supplied to the tutor. Advanced preferences and provider conditions remain expandable. Course packs are nested under the provider. The learner web-resource list and its bridge actions are removed; old caches remain on disk but are excluded from new tutor requests. Reference retrieval still uses imported tutor packs. The default assessment address is support@statisticalhelp.org; existing custom/provider addresses and historic submissions are preserved.

## Validation

- All 19 Node learning/lesson-context/provider tests passed, including old-record migration, retained hidden preferences, immutable historical submissions, skill/assessment export, and rejection of invalid new preference values. Existing question history, scoring and independent-practice checks also passed.
- The native WKWebView driver checked two main form sections, no URL management controls, nested pack controls, default recipient, closed optional details, changed skills and retained prior experience. Provider import, three lessons/MCQs, practical work, R snapshot, returned review, export and restoration all passed.
- A local ChatGPT protocol fixture verified that statistical skill level, AI self-assessment preference and imported course references reached the real native request; retired enabled/disabled web caches and learner identity were excluded. This is not a live model assessment.
- Existing Swift learning-client/course-pack compatibility checks passed.
- Native visual inspection checked both sections and the three assessment choices; selecting CPD updated the explanatory text and saved it.
- Swift compilation, JavaScript bundling and deep/strict local signature verification passed. The engine and bundled engine files are unchanged from 0.3.15 (official core 5.0.14). Numerical suites were not rerun for this learning-options and tutor-context change.

No assessment email was sent. Assessment type controls teaching intent and portfolio metadata; it does not create an accreditation service or award credit. A Course URL is an identifier, not an automatically imported website. Existing 0.3.15 records retain historical source citations. Example course 1.1 uses the updated default address and self-assessment preference.

Release archive: 153755889 bytes; SHA-256 `27826b5cd43dd9ad6655f99211c58a9a8709b76b95c912f4936ff92740089f63`. The extracted app passed deep/strict local signature verification, matched the tested app content and executable, and retained byte-identical engine files.

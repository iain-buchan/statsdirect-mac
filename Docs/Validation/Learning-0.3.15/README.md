# Provider courses and web resources — Mac 0.3.15

Validated on 30 September 2026 on Apple Silicon macOS. The calculation engine remains pinned to official StatsDirect 5.0.14 (`b10edfefa54bb9ebcdb36b9019b428f75c7d136d`).

## Feature checks

- All 17 learning, lesson-context and new provider-course Node tests passed. These cover retained historical question keys and first answers, independent-practice feedback withholding, saved practical submissions, old-record migration, citation/evidence persistence and provider-response binding.
- Swift resource tests passed for schema-1 compatibility/schema-2 validation, recipient injection rejection, HTTPS/public-address checks, stripping scripts/navigation, PDF discovery, source dates, relevant retrieval, unrelated-source exclusion and visible fetch errors.
- All six starter URLs were fetched and parsed with the actual native URLSession downloader. Metadata is retained in [learning-resources-live.json](learning-resources-live.json). OpenLearn and What If PDFs also loaded: 44 pages/113,762 characters and 361 pages/1,237,705 characters, respectively; see [learning-resources-pdf.json](learning-resources-pdf.json). No third-party teaching text is committed.
- Native WKWebView integration imported the example provider course, displayed ten total lessons, saved a practical submission, opened its R example without execution, attached an R text snapshot, answered all three original provider questions and imported a matching provider response. Records survived export/restore.
- The existing local ChatGPT protocol fixture asserted that provider details and a relevant enabled source/URL reached the actual native context builder, while a disabled source and learner identity did not. The cited response was retained in the record. This tests integration, not live AI teaching quality.
- Existing native workspace integration still passed: exact nine PEFR pairs from test.xlsx, paired engine analysis and SVG report, result reuse, stale/closed data rejection, cancellation, help/report/R context and lesson-only sharing.
- The full normal build and its engine regression checks passed. Final Swift compilation, bundled JavaScript generation and deep/strict local signature verification passed.
- Native visual inspection confirmed Learning Options, provider fields and the six-resource list with readable wrapping and scrolling. Pressing Load / refresh enabled resources in the packaged 0.3.15 app completed all six downloads and displayed Ready statuses and retrieval dates.

## Scope and limits

Course authors currently edit the documented JSON template; there is no visual course-authoring application. Retrieval selects bounded, relevant text excerpts rather than reading whole websites or fine-tuning a model. Complex PDF equations and figures require reference to the original. Practical answers and AI feedback are not automatically accredited; the chosen provider reviews them. Provider response files are recorded but not authenticated.

Email prepares a Mail draft with TXT and JSON attachments for the learner to send. No real assessment email was sent during validation. Report/R evidence is a text snapshot and excludes chart images and original workbook files. The application remains an ad-hoc-signed, non-notarised beta.

## Reproduce

Run the Node tests in Learn/learning.test.mjs, Learn/lesson-context.test.mjs and Learn/provider-course.test.mjs. Compile Sources/LearningCore.swift, Sources/CoursePack.swift, Sources/LearningResources.swift and Tests/learning-resources-test.swift with PDFKit; run with --live and --pdf for network checks. Run Scripts/test-provider-learning.sh and Scripts/test-learning-workspace.sh against the built application. Both native scripts use isolated application identities and stores.

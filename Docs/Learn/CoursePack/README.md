# Courses and reading lists for StatsDirect Learning

Open **Help → Learning Options**. Learners can enter their training organisation, course/version, assessment email and the provider’s assessment/CPD conditions. A provider course can fill these fields. The provider decides whether submitted work meets its requirements; StatsDirect does not award or authenticate credit.

## Start with an example

Choose **Use example provider course** to try a three-lesson public-health service evaluation, paired data, an R example and three original practice questions. It replaces the active pack and archives the previous one; saved submissions and question attempts remain in the portfolio. The example has no accreditation attached.

Providers can edit [provider-course-example.json](provider-course-example.json) and import it with **Import course pack**. No programming or model training is required to use a pack, although authoring the structured JSON currently requires editing a file. Searchable PDF, UTF-8 Markdown/text and the original schemaVersion 1 JSON packs remain supported as reference notes.

## Provider pack format

Schema version 2 has `id`, `version`, `title`, `provider`, `documents`, `lessons`, `questions` and `resourceURLs`. The example is the complete working template.

- `provider`: name, a single `reviewEmail`, `assessmentRequirements` and `cpdStatement`. The learner sees and can amend these details before preparing a submission.
- `documents`: unique IDs, titles and teaching text. References are retrieved from these documents when relevant.
- `lessons`: an ordered sequence of unique IDs, titles, objectives, summaries, practical steps and a challenge. Optional reading URLs link to the prescribed material. The shared StatsDirect foundation lessons, including epidemiology and causal inference, remain available.
- A lesson may include an existing StatsDirect `operation` ID and numeric example `columns`. Each column has a title and values. The regular analysis form opens with these data. Optional `r` text opens in an R tab **without running**; the learner can inspect it and press Run. Importing a course never executes code.
- `questions`: original provider-authored MCQs with 2–8 labelled choices, one correct choice and an explanation. Optional hints, teaching notes, objectives and choice-specific feedback are supported. These are local, unsupervised practice questions, not a secure examination; do not put secret examination keys in learner packs.
- `resourceURLs`: public HTTPS pages or PDFs added to the learner’s resource list. They are not automatically downloaded during course import.

Pack IDs and lesson/question IDs use letters, digits, hyphens and underscores. Limits: 100 lessons, 300 questions, 30 resource URLs, 500 reference documents/pages and 1 MB of reference text. Each local import file is at most 16 MB. Provider examples allow up to 32 columns / 20,000 numeric values per lesson. Invalid imports leave the current pack unchanged. A provider pack must be imported on its own; notes-only files can be imported together.

## Web resources

The starter list includes OpenLearn medical statistics; CDC’s archived Principles of Epidemiology; Penn State STAT 507; two OpenIntro chapters; and Hernán and Robins’ What If book page. Links and short descriptions are bundled; third-party teaching text is downloaded only when the learner presses **Load** or **Load / refresh enabled resources**.

Add one URL per line. Each row shows whether it is enabled, what was downloaded and when, or the actual error. Loading a page reads that page, not an entire course website. Recognised PDF links can be added and loaded separately. For a protected or blocked site, use its browser download and import a permitted searchable PDF/text copy. Figures, scanned pages and complex mathematical notation need checking against the original.

Only enabled, successfully downloaded material is available to the tutor. A failed refresh retains the earlier text and date with a visible failure status. Removing a resource removes its cached text from future retrieval; sources already recorded in conversations remain in the record. The downloader uses public HTTPS, checks destinations and redirects, sends no browser cookies/account credentials, does not execute page scripts, and limits downloads to 16 MB, PDFs to 700 pages and extracted text to 2 MB per resource. The local library is limited to 30 resources / 20 MB.

Local keyword ranking chooses up to five overlapping extracts, each at most 1,700 characters, based on the learner’s question and lesson topic. Unrelated extracts are excluded. References include the original URL, retrieval date and PDF page/title. This is retrieval, not fine-tuning. The tutor receives selected excerpts through the existing ChatGPT connection when the learner sends a question. Links alone do not give the tutor access to material. The application does not grant redistribution rights to third-party course content.

## Assessment and evidence

The learner can save practical responses from each provider lesson, retaining successive submissions with the lesson and provider/version snapshot. Provider MCQ attempts likewise retain their original questions and keys even if a later course version changes them. Supported practice records assistance; independent practice pauses the in-app tutor and withholds keys/feedback until the attempt ends. It cannot detect outside assistance.

**My learning record** includes practical submissions, first MCQ answers/reasoning, assistance, the teaching conversation and citations, reflection and attached text snapshots of selected open reports or R sessions. Text snapshots do not include chart images or original workbooks. Preview the complete record, choose the assessment recipient, and prepare an email draft with TXT and JSON attachments. The learner sends it in Mail. No automatic submission or delivery confirmation is claimed.

A provider may return a file based on [provider-response-template.json](provider-response-template.json). Copy the learner’s `portfolioID` from the submission, fill in the provider, reviewer, date, decision and feedback, and include any actual credit statement/reference. The learner imports it from **Returned assessments**. A response for another portfolio is rejected. Imported decisions are explicitly labelled as unauthenticated provider-supplied records; this is not certificate verification.

Records, source caches and course packs stay under `~/Library/Application Support/<bundle-id>/Learning/` with private file permissions. Corrupt saved records are not silently replaced.

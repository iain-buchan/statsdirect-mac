# Courses and reading lists for StatsDirect Learning

Open **Help → Learning Options**. The main provider fields are Course (name or URL), Assessment email address, Assessment type and A course pack from your tutor. Additional provider/version and assessment/CPD conditions are available in expandable details. A provider course can fill these fields. The provider decides whether submitted work meets its requirements; StatsDirect does not award or authenticate credit.

## Start with an example

Choose **Try example course** to try a three-lesson public-health service evaluation, paired data, an R example and three original practice questions. It replaces the active pack and archives the previous one; saved submissions and question attempts remain in the portfolio. The example has no accreditation attached.

Providers can edit [provider-course-example.json](provider-course-example.json) and import it with **Import course pack**. No programming or model training is required to use a pack, although authoring the structured JSON currently requires editing a file. Searchable PDF, UTF-8 Markdown/text and the original schemaVersion 1 JSON packs remain supported as reference notes.

## Provider pack format

Schema version 2 has `id`, `version`, `title`, `provider`, `documents`, `lessons`, `questions` and `resourceURLs`. The example is the complete working template.

- `provider`: name, a single `reviewEmail`, `assessmentRequirements` and `cpdStatement`, and optional `assessmentType` (`none`, `cpd` or `self`). The learner sees and can amend these details before preparing a submission.
- `documents`: unique IDs, titles and teaching text. References are retrieved from these documents when relevant.
- `lessons`: an ordered sequence of unique IDs, titles, objectives, summaries, practical steps and a challenge. Optional reading URLs link to the prescribed material. The shared StatsDirect foundation lessons, including epidemiology and causal inference, remain available.
- A lesson may include an existing StatsDirect `operation` ID and numeric example `columns`. Each column has a title and values. The regular analysis form opens with these data. Optional `r` text opens in an R tab **without running**; the learner can inspect it and press Run. Importing a course never executes code.
- `questions`: original provider-authored MCQs with 2–8 labelled choices, one correct choice and an explanation. Optional hints, teaching notes, objectives and choice-specific feedback are supported. These are local, unsupervised practice questions, not a secure examination; do not put secret examination keys in learner packs.
- `resourceURLs`: optional HTTPS reference metadata retained for compatibility. The learner reading list is retired in 0.3.16; these links are not fetched or added to tutor context. Supply reference text in `documents` and reading links in lessons.

Pack IDs and lesson/question IDs use letters, digits, hyphens and underscores. Limits: 100 lessons, 300 questions, 30 resource URLs, 500 reference documents/pages and 1 MB of reference text. Each local import file is at most 16 MB. Provider examples allow up to 32 columns / 20,000 numeric values per lesson. Invalid imports leave the current pack unchanged. A provider pack must be imported on its own; notes-only files can be imported together.

## Curated content and reference notes

The learner web-resource list was removed in 0.3.16. Core lessons and questions are curated in the application between releases. Tutors can still import PDF/text/JSON materials or distribute provider course packs. A Course field containing a URL identifies the course; it does not download the site or claim that its content has been read.

Old downloaded resource caches remain on disk but are no longer used for new tutor requests. Existing conversations retain their original source citations. The downloader and seed catalogue remain in source control for future editorial work, without learner-facing download controls.

Local keyword ranking selects up to five relevant course-pack extracts of up to 1,700 characters for each tutor question, with document/page references and any supplied source URL/date. Figures, scanned pages and complex notation need checking against the original. Import does not fine-tune the model or confer redistribution rights.

## Assessment and evidence

The learner can save practical responses from each provider lesson, retaining successive submissions with the lesson and provider/version snapshot. Provider MCQ attempts likewise retain their original questions and keys even if a later course version changes them. Supported practice records assistance; independent practice pauses the in-app tutor and withholds keys/feedback until the attempt ends. It cannot detect outside assistance.

**My learning record** includes practical submissions, first MCQ answers/reasoning, assistance, the teaching conversation and citations, reflection and attached text snapshots of selected open reports or R sessions. Text snapshots do not include chart images or original workbooks. Preview the complete record, choose the assessment recipient, and prepare an email draft with TXT and JSON attachments. The learner sends it in Mail. No automatic submission or delivery confirmation is claimed.

A provider may return a file based on [provider-response-template.json](provider-response-template.json). Copy the learner’s `portfolioID` from the submission, fill in the provider, reviewer, date, decision and feedback, and include any actual credit statement/reference. The learner imports it from **Returned assessments**. A response for another portfolio is rejected. Imported decisions are explicitly labelled as unauthenticated provider-supplied records; this is not certificate verification.

Records, source caches and course packs stay under `~/Library/Application Support/<bundle-id>/Learning/` with private file permissions. Corrupt saved records are not silently replaced.

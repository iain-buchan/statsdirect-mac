# StatsDirect Learning (macOS prototype 0.3.0)

Open **Help → Learning** or **Help → Learning Options**. This is an integrated closable Mac document: original Windows artwork, seven lessons, five learner pathways, 30 original draft MCQs, local persistence, real StatsDirect analysis forms and seven runnable base-R examples with plots. Epidemiology and causal inference are shared foundations. Options include learning needs, named exams/qualifications, prior knowledge, R experience, target date, priorities and teaching style.

## OpenAI tutor

Choose **AI settings**, enter your own API key and an available model (default `gpt-6-sol`). The native host stores the key in macOS Keychain; it is never passed into the WebView, saved in a learning record or bundled with the app. Each explicit Send calls the [Responses API](https://developers.openai.com/api/docs/guides/text) at the fixed HTTPS OpenAI endpoint using `store:false`, bounded recent conversation (up to 40 messages / 60,000 characters), lesson context, learning options and any retrieved course excerpts. API billing and [provider data controls](https://developers.openai.com/api/docs/guides/your-data) apply; `store:false` is not a promise of zero retention. Review identity fields and other open worksheets are not automatically attached. A model name can be changed for the API project's availability; the default was checked against the [model catalogue](https://developers.openai.com/api/docs/models) on 25 September 2026.

The tutor has no tools and cannot run R, modify marks or send email. Replies are rendered as escaped text/code. Curated lesson buttons start allowlisted engine methods, help pages and bundled R examples; model-generated code is never auto-executed. Cancellation and API errors keep local records intact. Live OpenAI quality/network testing requires a user-supplied API key and remains outstanding for this build; offline request/response boundary tests use synthetic data only.

## Teaching and records

Supported practice gives feedback after each answer, recording hints and in-app assistance. Independent practice disables in-app tutoring and withholds keys/results until completion or early termination. First answers, reasoning, confidence, question snapshots and provisional scores are saved, together with the complete teaching conversation, activity log and reflection. Existing sessions freeze their question version when created. This is unsupervised practice, not a secure examination. Fixed answer keys score MCQs; free-text reasoning and AI explanations are not independently marked.

**My learning record** previews the exact attachment, exports TXT or JSON and opens a native Mail draft addressed to the learner's choice of support@statsdirect.com or chil@liverpool.ac.uk. Sending is completed in Mail. If no Mail sharing service is available, Finder reveals the attachment for manual email. The app cannot verify dispatch, delivery, independent review or CPD accreditation. No email is sent during automated verification.

Records and course packs are stored in `~/Library/Application Support/<bundle-id>/Learning/` with private file permissions. A malformed existing record is not overwritten. Browser preview uses separate browser-local storage and does not accept API credentials. Test builds use a separate bundle ID and storage.

## Course packs and sources

See [the tutor pack guide](../Docs/Learn/CoursePack/README.md) and its JSON template. Import searchable PDF, UTF-8 Markdown/text or JSON. Retrieval uses local keyword ranking, so relevance and source coverage need review; this is not model fine-tuning. See [the examination-source notes](../Docs/Learn/EXAM-SOURCES.md) for precise access limits and the original-question policy.

## Build and check

The generated `Content/Learn/app.js` is committed, like the existing grid assets. After editing Learn sources, run `node Learn/build.mjs` with the Grid esbuild dependency installed. Then run:

```
node --test Learn/learning.test.mjs
swiftc Sources/LearningCore.swift Sources/CoursePack.swift Tests/learning-client-test.swift -o .build/learning-client-test
.build/learning-client-test
python3 Tests/test_learning_examples.py
./build.sh
```

The build creates `StatsDirect Viewer.app` with its original calculation engine unchanged. The icon script extracts no new art; it packages the Windows symbol for macOS.

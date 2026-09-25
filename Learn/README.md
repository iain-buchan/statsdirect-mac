# StatsDirect Learning (macOS prototype 0.3.1)

Open **Help → Learning** or **Help → Learning Options**. This is an integrated closable Mac document: original Windows artwork, seven lessons, five learner pathways, 30 original draft MCQs, local persistence, real StatsDirect analysis forms and seven runnable base-R examples with plots. Epidemiology and causal inference are shared foundations. Options include learning needs, named exams/qualifications, prior knowledge, R experience, target date, priorities and teaching style.

## Shared conversational tutor

Learners do not enter an OpenAI key or choose a model. The Mac connects to a StatsDirect/course-managed service and automatically creates a limited learning session when the learner first sends a question. Its service token stays in macOS Keychain. The administrator holds the OpenAI credential on the server and controls the model, teaching policy and usage allowance. No provider credential is accepted by the Mac or included in its bundle.

This build includes the client and the [deployable .NET service](../TutorService/README.md). Hosting and an administrator's OpenAI credential have not yet been configured, so the shipped prototype shows **Awaiting service activation**. It does not silently substitute an offline guide for a live AI answer. Once a publisher embeds the service's HTTPS address, learners can simply type and Send. Existing pilot builds can import a public connection file through **Tutor connection**; this is not an API-key file.

Each explicit Send shares bounded recent conversation (up to 40 messages / 60,000 characters), the lesson, learning options and retrieved course excerpts with the chosen service and OpenAI. Review identity fields and other open worksheets are not automatically attached. The service uses the [Responses API](https://developers.openai.com/api/docs/guides/text), `store:false`, fixed teaching instructions and no tools. Provider [data controls](https://developers.openai.com/api/docs/guides/your-data) apply; `store:false` is not a promise of zero retention. Replies are escaped text/code, and model-generated code is never auto-executed.

Offline service/client tests use a simulated provider. Live network credentials, quality, latency and deployment testing remain outstanding until the service is hosted and activated. The service includes persistent daily caps; these are request allowances, not monetary budgets or learner identity verification.

## Teaching and records

Supported practice gives feedback after each answer, recording hints and in-app assistance. Independent practice disables in-app tutoring and withholds keys/results until completion or early termination. First answers, reasoning, confidence, question snapshots and provisional scores are saved, together with the complete teaching conversation, activity log and reflection. Existing sessions freeze their question version when created. This is unsupervised practice, not a secure examination. Fixed answer keys score MCQs; free-text reasoning and AI explanations are not independently marked.

**My learning record** previews the exact attachment, exports TXT or JSON and opens a native Mail draft addressed to the learner's choice of support@statsdirect.com or chil@liverpool.ac.uk. Sending is completed in Mail. If no Mail sharing service is available, Finder reveals the attachment for manual email. The app cannot verify dispatch, delivery, independent review or CPD accreditation. No email is sent during automated verification.

Records and course packs are stored in `~/Library/Application Support/<bundle-id>/Learning/` with private file permissions. A malformed existing record is not overwritten. Browser preview uses separate browser-local storage and does not connect to the managed service. Test builds use a separate bundle ID and storage.

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

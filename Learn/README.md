# StatsDirect Learning (macOS prototype 0.3.4)

Open **Help → Learning** or **Help → Learning Options**. This is an integrated closable Mac document: original Windows artwork, seven lessons, five learner pathways, 30 original draft MCQs, local persistence, real StatsDirect analysis forms and seven runnable base-R examples with plots. Epidemiology and causal inference are shared foundations. Options include learning needs, named exams/qualifications, prior knowledge, R experience, target date, priorities and teaching style.

## Use my ChatGPT

Choose **Use my ChatGPT**, complete sign-in in your browser, then return to Learning and press **Send**. No API key, separate Codex installation or StatsDirect hosting account is needed. The connected account and sign-out are available through **Tutor connection**. Signing out leaves the local portfolio and other apps' accounts unchanged. A pending sign-in can be reopened or cancelled without losing the draft question.

The app bundles OpenAI's official **Codex App Server 0.157.1** for Apple silicon and uses its managed ChatGPT browser authentication. Access depends on the learner's ChatGPT plan, Codex entitlement, workspace policy and available usage allowance. This does not import existing ChatGPT chats, create a ChatGPT website conversation, or turn a ChatGPT subscription into an API key. See the official [app-server authentication protocol](https://learn.chatgpt.com/docs/app-server) and [authentication guidance](https://learn.chatgpt.com/docs/auth).

Each Send shares bounded recent conversation (up to 40 messages / 60,000 characters), bundled lesson context, learning options and relevant course excerpts with OpenAI. Review identity fields are not automatically attached. Application context is controlled by the selector described below. The learner's ChatGPT/Codex account data controls apply; API `store:false` settings from the separate managed-service prototype do not apply to this connection. Replies are escaped text/code and generated code is never automatically executed.

The native process owns login and token refresh. Credentials are kept by the runtime in macOS Keychain, under a separate StatsDirect runtime home; neither tokens nor login URLs enter the web view or portfolio. Runtime setup is private to `~/Library/Application Support/<bundle-id>/ChatGPT Tutor/`. It does not reuse `~/.codex`, personal API keys or project configuration. Each reply uses an ephemeral thread with **no selected computer environment**, no connected apps/plugins, shell, browser or image tools; approval requests are rejected. Only the six registered StatsDirect host tools are available; these cannot access arbitrary files, execute R/shell commands or send email. Learning conversation history is managed by the existing local portfolio. The runtime's default available model is used, rather than hardcoding an entitlement-dependent model name.

The runtime is pinned because its app-server interface contains experimental fields, including disabling environment access and dynamic host tools. `Scripts/bundle-chatgpt.py` verifies the official archive's SHA-256, includes its Apache licence and notice, and signs the embedded executables. Contract tests exercise the exact pinned binary. A runtime upgrade must repeat those tests. This remains an unsigned-for-distribution Mac prototype; release signing/notarisation is still outstanding.

Native tests cover browser authentication setup/cancel with the real signed-out runtime, and completed login, answers, usage errors, cancellation/retry and logout with a local protocol fixture. A live model response requires the learner to finish browser sign-in. The optional [managed service prototype](../TutorService/README.md) remains in the repository for future institutional use; it is not the shipped tutor connection.

## Working with open data and results

The tutor sees an inventory of documents open when Send is pressed, with worksheet headings and selections. **Tutor context** follows the last active document, can be pinned to a particular document, or set to **Lessons only**. That last preference persists across launches. It does not remove earlier conversation messages. Context/status updates preserve the draft text.

The six host tools list the workspace, read exact worksheet ranges, read open forms/reports/help/R scripts and output, retrieve bundled method help, calculate a supported method, or open another normal analysis form. The native host supplies data from the live grid, rather than asking the model to transcribe or reconstruct it. Dataset IDs refer to a per-question snapshot; edited/closed worksheets are rejected before calculation. New documents opened during a question are not silently added to that question's scope. The embedded grids in analysis forms are readable too.

Direct calculations currently support paired and unpaired t tests, univariate and quick summaries, chi-square 2×2, Fisher's exact test, Wilcoxon signed ranks, Spearman correlation, agreement and normality. The engine supplies defaults and validates inputs; chi-square study design must be specified instead of guessed. Other methods open their ordinary forms for further input. Results go into the existing active report, with engine-generated SVG and the existing R link. A repeated calculation request for the same dataset/method within a question reuses its report entry.

Reads are limited to 4,000 cells across at most 32 columns and 50,000 characters, with no silent sampling or truncation. Missing-cell positions and selected column order are retained. Stale formula caches and Excel errors cannot be calculated. Large documents/R output are explicitly bounded excerpts. Replies show the sources actually used, which are also included in the learning record. The teacher is instructed to inspect available data before asking the learner to paste it, and to distinguish open workbooks from each lesson's fictional example.

## Teaching and records

Supported practice gives feedback after each answer, recording hints and in-app assistance. Independent practice disables in-app tutoring and withholds keys/results until completion or early termination. First answers, reasoning, confidence, question snapshots and provisional scores are saved, together with the complete teaching conversation, activity log and reflection. Existing sessions freeze their question version when created. This is unsupervised practice, not a secure examination. Fixed answer keys score MCQs; free-text reasoning and AI explanations are not independently marked.

**My learning record** previews the exact attachment, exports TXT or JSON and opens a native Mail draft addressed to the learner's choice of support@statsdirect.com or chil@liverpool.ac.uk. Sending is completed in Mail. If no Mail sharing service is available, Finder reveals the attachment for manual email. The app cannot verify dispatch, delivery, independent review or CPD accreditation. No email is sent during automated verification.

Records and course packs are stored in `~/Library/Application Support/<bundle-id>/Learning/` with private file permissions. A malformed existing record is not overwritten. Browser preview uses separate browser-local storage and does not sign in or connect to ChatGPT. Test builds use a separate bundle ID and storage.

## Course packs and sources

See [the tutor pack guide](../Docs/Learn/CoursePack/README.md) and its JSON template. Import searchable PDF, UTF-8 Markdown/text or JSON. Retrieval uses local keyword ranking, so relevance and source coverage need review; this is not model fine-tuning. See [the examination-source notes](../Docs/Learn/EXAM-SOURCES.md) for precise access limits and the original-question policy.

## Build and check

The generated `Content/Learn/app.js` is committed, like the existing grid assets. After editing Learn sources, run `node Learn/build.mjs` with the Grid esbuild dependency installed. Then run:

```
node --test Learn/learning.test.mjs Grid/tutor-data.test.mjs
swiftc Sources/ChatGPTTutor.swift Tests/chatgpt-tutor-driver.swift -o .build/chatgpt-tutor-test
.build/chatgpt-tutor-test Tests/mock-chatgpt-server.py .build/chatgpt-mock Content/Tutor mock
.build/chatgpt-tutor-test .build/codex-runtime/bin/codex-app-server .build/chatgpt-probe Content/Tutor probe
python3 Tests/probe-chatgpt-runtime.py .build/codex-runtime/bin/codex-app-server Content/Tutor
swiftc Sources/LearningCore.swift Sources/CoursePack.swift Tests/learning-client-test.swift -o .build/learning-client-test
.build/learning-client-test
python3 Tests/test_learning_examples.py
swiftc Sources/ChatGPTTutor.swift Sources/TutorTools.swift Sources/RScriptGenerator.swift Tests/tutor-engine-driver.swift -o .build/tutor-engine-test
.build/tutor-engine-test "$PWD"
Scripts/test-learning-workspace.sh
./build.sh
```

The build creates `StatsDirect Viewer.app` with its original calculation engine unchanged. The icon script extracts no new art; it packages the Windows symbol for macOS.

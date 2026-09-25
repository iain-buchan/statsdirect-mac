# StatsDirect Learn — feasibility and pilot proposal

25 September 2026 · Research and an interactive concept, not a released feature.

A conversational **Learn** document is feasible within the existing Mac shell. The strongest version would connect explanation, assessment and practical work: a learner discusses a concept, answers a question, explores its data in StatsDirect and receives a specific plan for further study. Reviewed feedback could then become evidence in their CPD portfolio.

The technical fit is good: `Sources/main.swift` already creates independent WKWebView documents, `Sources/OperationHost.swift` starts engine operations, and reports already link to help and R scripts. A future `LearnHost.swift` can use these boundaries without changing the calculation engine. Learn development is independent of numerical engine updates and does not modify calculation routines.

## What is here to try

Open `index.html` through a local web server. It demonstrates three paths, each with four original five-option questions, hints, explanations, confidence ratings, optional reasoning, a test mode that delays feedback, a learning plan and JSON export of a local review record. The conversation is explicitly **scripted**, not connected to a language model. Nothing is emailed or submitted, and no real learner identity is collected. Responses live only in page memory until exported or the page closes.

From the repository root:

```sh
python3 -m http.server 8766 --bind 127.0.0.1
# Open http://127.0.0.1:8766/Docs/Learn/
```

These are teaching drafts that need subject-expert review. This concept does not estimate exam readiness, issue credits, replicate a secure exam, persist a portfolio or connect to the live StatsDirect engine. The answer keys are intentionally inspectable in the local source. Free-text reasoning is retained, not automatically graded. The proposal below describes the additional work.

## Public examination sources and what they tell us

| Audience | Public primary source examined | Implication for Learn |
|---|---|---|
| UK medical undergraduates | [Medical Schools Council practice materials](https://www.medschools.ac.uk/for-students/medical-licensing-assessment/practice-exam-for-the-ms-akt/) and its [Paper 2 with explanations](https://www.medschools.ac.uk/wp-content/uploads/2026/01/MS-AKT-Practice-MLA-Paper-2-with-answers-and-justifcations.pdf), notably question 17 on NNT | Short clinical contexts, one best answer and an explanation of the calculation. |
| Postgraduate physicians | [MRCP(UK) official sample-question access](https://www.thefederation.uk/examinations/part-1/part-1-sample-questions) | A useful exam-style reference. The practice platform requests registration; no registration was made and its gated questions were not inspected. |
| Postgraduate general practice | [RCGP preparation guidance](https://www.rcgp.org.uk/mrcgp-exams/applied-knowledge-test/akt-preparing), [November 2025 sample questions](https://www.rcgp.org.uk/getmedia/dca96621-2599-4e6e-9a99-7a1ab2affff9/AKT-Example-Questions-(with-answers)-November-2025.pdf) and [data-interpretation teaching material](https://www.rcgp.org.uk/getmedia/e2ba263c-385f-4e3c-9fc4-7bd13beeca40/data-interpretation-AKT.pdf) | Include interpretation of charts, predictive values, absolute and relative risk, NNT and forest plots. RCGP describes mainly single-best-answer items alongside other formats. |
| Public-health postgraduates | [FPH DFPH structure](https://www.fph.org.uk/training-careers/the-diplomate-dfph-and-final-membership-examination-mfph/the-diplomate-examination-dfph/structure-of-the-diplomate-examination-dfph/) and [specimen-paper listing](https://www.fph.org.uk/training-careers/the-diplomate-dfph-and-final-membership-examination-mfph/the-diplomate-examination-dfph/the-diplomate-examination-dfph-preparation/) | MCQs cover only part of the need. Add calculations, short explanations, critical appraisal and communication of findings. The listing identifies 2025/2026 specimens; direct retrieval of FPH material intermittently returned 403, so this is not a review of every specimen paper. |
| Additional medical-exam examples | [USMLE Step 1 biostatistics example](https://www.usmle.org/exam-resources/step-1-materials/step-1-sample-test-questions) and [Step 3 examples](https://www.usmle.org/exam-resources/step-3-materials/step-3-formats-questions) | Public examples test recognition of study design and the relationship between prior probability and predictive value. |

These sources support the topic and format choices, not a claim that our draft bank reproduces an official blueprint. Official questions should be linked for reference. The MSC paper restricts redistribution beyond personal educational non-commercial use, so inclusion in a commercial product would require appropriate permission. Use original, reviewed questions or explicitly licensed items; do not import recalled live examinations or paid question banks.

## Proposed learning experience

Add **Learn → Start learning**, **Practise a topic**, and **My learning record**. Each session opens as an ordinary closable document alongside worksheets, help, reports and R. Its setup asks for learning level, topic and whether the learner wants teaching or assessment.

In teaching mode, the tutor asks the learner to explain their reasoning, offers graduated hints, works through a calculation and explains misconceptions behind distracting options. It can open the relevant StatsDirect help page and, after learner selection, create a synthetic example worksheet or run an approved demonstration analysis. The learner can alter values and see how the effect, confidence interval or chart changes.

In test mode, freeze the question version and scoring rules before starting. Record first answers, optional confidence and working, with no hints or live correctness feedback until the test ends. Confidence informs feedback but does not change the raw MCQ score. An assisted practice score must be labelled separately from an unassisted score. Four draft items are not a psychometrically valid examination or a measure of readiness.

Feedback should identify a specific misunderstanding, explain it in plain language, link a worked example, set a fresh problem and invite a short reflection. Record a learner-chosen follow-up date and a practical action. For example: “I confused the population with disease with the population testing positive; next I will build two diagnostic tables with different prevalences.” A subsequent new problem tests transfer rather than recall of the same answer.

## Starting question bank

The interactive concept includes these original drafts, with answer rationales, distractor explanations, a learning objective, a version and a StatsDirect help mapping in `bank.mjs`:

| Path | Topics |
|---|---|
| Medical undergraduate | Sensitivity; absolute benefit/NNT; P-value interpretation; paired versus independent data |
| Postgraduate medicine | Predictive value and prevalence; confidence intervals crossing the null; risk versus odds; precision and sample size |
| Public health postgraduate | Direct age standardisation; confounding; cluster design effect; standardised mortality ratio |

For a first teaching pilot, expand to about 60 expert-reviewed items, distributed across these topics and study design, bias, contingency tables, effect measures, regression, survival analysis and meta-analysis. Add the short-answer tasks below. Exact allocation should follow the intended course and examination objectives; this is a proposed pilot size, not a validated test length.

## Short-answer tasks to add for public-health candidates

| Original task | Proposed analytic rubric |
|---|---|
| A cluster-randomised trial reports an unadjusted individual-level analysis. Explain two concerns and an appropriate next analysis. | One point each for recognising dependence, its effect on uncertainty, a suitable cluster-aware method, and checking the number/size of clusters and design assumptions. Accept equivalent valid approaches. |
| A screening programme has many false positives despite high sensitivity. Explain this to a non-specialist using a small hypothetical population. | Credit correct denominators, a valid numeric example, a clear role for prevalence and a balanced explanation of what a positive result means. |
| An observational risk ratio attenuates after adjustment. Explain what can and cannot be concluded. | Credit the possible role of confounding, appropriate treatment of uncertainty, the limits of measured adjustment and avoidance of a causal claim based on adjustment alone. |

Rubrics and exemplars need academic approval. The marking service must accept valid alternative reasoning, distinguish arithmetic from interpretation errors and escalate ambiguous answers. Spelling, stylistic fluency and confidence should not become hidden scoring criteria.

## Marking and the University review

For MCQs, a deterministic scorer compares the answer with the approved, versioned key. For calculations, the same tested engine supplies reference results, with independent R checks when authoring and explicit rules for units and rounding. A language model explains results; it is not the source of numerical truth. New generated questions remain drafts until an expert has checked correctness, ambiguity and distractors.

The University review should be a separate service contract. Give it the frozen question, rubric, submitted answer and independently verifiable calculations. Ask it to assess these before comparing its view with the provisional result, reducing anchoring. Save its decision, reasons, evidence references and model/rubric versions. Two language models can share the same error: agreement is useful evidence, not proof or institutional approval. Disagreements, unavailable services and invalid responses remain **pending review** and go to an authorised reviewer.

Liverpool's [current public guidance, updated July 2026](https://www.liverpool.ac.uk/about/the-university/reports-policies-and-governance/ai-at-liverpool/policies-and-guidance/guidance-learning-teaching-and-assessment/) allows support for low-stakes questions and feedback, but lists AI-generated grades/final assessment decisions as unacceptable and places assessment with the teacher. **My recommendation is therefore formative self-checking with AI support, followed by accountable academic review for any formal University assessment or endorsed CPD outcome.** The responsible University team must determine the applicable policy and any approved service arrangements. A second AI response alone must not display “University approved”.

No University AI API, credentials, service owner or assessment-authorisation protocol has been identified for this project. The public [CHIL contact page](https://www.liverpool.ac.uk/civic-health-innovation-labs/about/) confirms the address the user supplied; it does not establish that the inbox is a marking service.

## Submission, email and return of feedback

Proposed sequence:

1. The learner finishes a test and previews the record: item versions, choices, working, assistance, provisional result and reflection. A verified reply address is needed only if they choose submission.
2. The app submits the approved record to a secure review service, receives a submission identifier and shows **Received — awaiting review**. A failed or offline request must not be labelled submitted.
3. In the initial pilot, email a concise result summary and authenticated review link to **support@statsdirect.com**. Later, enable routing to **chil@liverpool.ac.uk** after the University connection is agreed; do not silently begin copying learners' records to a new recipient.
4. The configured University reviewer checks the marking and feedback. A named authorised academic handles final assessment decisions and disagreements under the agreed workflow.
5. Email the learner a notification when feedback is released, with a protected link to the reviewed record. It contains the score and its limits, specific explanations, learning actions, reflection and review date/status. Offer a route to query a mark.

The emails can contain the requested result summary, while detailed answers and transcripts remain in the protected record. Email is notification and correspondence, not the queue or source of truth. An authenticated service should hold the state, retry delivery safely, track bounces and prevent duplicate submissions/replies. A server-controlled recipient list prevents learner or model text from changing the destination. Mailbox and model credentials must never be embedded in the Mac app.

## Implementation boundary

| Component | Proposed responsibility |
|---|---|
| `LearnHost.swift` and HTML/TypeScript content | Native document lifecycle; accessible chat and questions; local draft; explicit worksheet/help/report actions |
| .NET engine | Approved synthetic example calculations, preserving the existing serialised engine execution boundary |
| Hosted learning service, naturally implementable in C#/ASP.NET | Authentication, question versions, deterministic scoring, submission state, audit trail, model access and mail queue |
| Tutor-provider interface | Exchange bounded conversational messages and structured tool requests with a configured model; permit provider replacement |
| University-review interface | Asynchronous review request/result with evidence, decision and reviewer identity; no invented approval while disconnected |
| Academic review view | Read answers and independent evidence, resolve disagreement, release or return feedback and record the reason |

The tutor's allowed actions should be narrow: retrieve an approved help passage, present an approved item, explain a reference calculation, or prepare a submission preview. It should not execute arbitrary R/shell code, read unrelated worksheets, send email or change marks and approval flags. Student prose and retrieved text are untrusted content, not instructions to the grading or delivery service. Assessment answers and private keys stay server-side in an assessment deployment. Approved help and bank versions provide stable citations; live web search is useful for authors, not a shifting answer key during an attempt.

Before collecting real student records, agree the controller/processor roles, access, retention/deletion, hosting and international-transfer arrangements, and the permitted model use of data. Keep learner identity separate from pseudonymous assessment records where possible; do not send patient records for these synthetic learning exercises. Explain recipients and AI use at collection. This follows the relevant themes in the [ICO's AI guidance](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/artificial-intelligence/); the University's specific arrangements require its own review. Do not assume that a ChatGPT or university chat subscription includes an application API or permission to process student assessment data.

## A staged route to a pilot

1. **Local Learn pilot:** approve the topic map, review an initial bank, embed the concept in a Mac document and connect selected teaching examples to engine/help/R. Acceptance: every numeric key independently checked; hints and test mode remain separate; saved attempts survive restart; keyboard and accessibility flows work.
2. **Hosted conversational tutor:** select an approved model service; add grounded explanations, session persistence and an instructor evaluation set. Acceptance: valid citations, no unsupported marking claims, misconception handling and reliable abstention/escalation on uncertain questions.
3. **Closed review pilot:** agree the University service and owner; add the authenticated review queue and notifications to the specified inboxes. Acceptance: duplicate/retry/offline tests, learner preview, review provenance, disagreement handling and successful feedback retrieval. Test email delivery with synthetic records before onboarding students.
4. **CPD evaluation:** run with volunteer learners and academic oversight. Compare marking with independently double-marked examples; examine item difficulty, discrimination, distractor performance, accessibility and feedback usefulness. Measure learning on fresh follow-up items. Formal credits, certificates or assessment decisions require the applicable academic/accreditation process.

The desktop document is the relatively small part. The main effort is a trustworthy bank, an evaluated tutor, and the institutional review/feedback service. This exploration establishes a practical route; it does not promise a production date without those dependencies.

## Verification of this concept

`node --test Docs/Learn/learn.test.mjs` checks the item bank's links and operation names, completion/scoring boundaries, assisted practice, independent-test restrictions and truthful export status. A base R cross-check covers every numerical draft answer. Browser checks cover the guided and unassisted paths, review display and local export. These checks verify the prototype's behaviour; academic item validation remains outstanding.

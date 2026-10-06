# Curated learning library

Content revision: **1 October 2026**. Twelve original lessons, 35 fixed-key practice questions (five added in this revision), 24 discussion prompts and 12 runnable base-R examples. The original seven lessons retain their IDs, core examples and challenge history. Added lessons cover population rates and standardisation, trial appraisal, missing data, prediction validation and meta-analysis.

## Authoritative content

Edit `Learn/lessons.json`, then publish with `python3 Learn/create-lessons.py` and bundle with `node Learn/build.mjs`. `Content/Learn/lessons.json` is the shipped copy. Both browser and practice bundles use that copy, avoiding duplicate catalogues in the generated JavaScript. No new database, online resource fetching or learner URL-management form is introduced.

Each lesson keeps its existing `id`, `title`, `topic`, `objective`, `summary`, `challenge`, `steps`, engine `operation`, local `help`, worksheet `columns` and executable `r`. The additive `knowledgeSchemaVersion: 1` fields are:

| Field | Purpose |
|---|---|
| `contentVersion`, `review` | Revision date, original authorship and honest review status. |
| `prerequisites` | Other stable lesson IDs; the graph must be acyclic. These guide teaching rather than locking learners out. |
| `learningObjectives`, `keyConcepts` | Concrete outcomes and explained terminology. |
| `misconceptions` | Plausible mistaken claims paired with explicit corrections. |
| `workedExample` | Design assumptions and an interpretation tied to the actual example. |
| `teachingPrompts` | Beginner/advanced prompts and expected reasoning for formative conversation. |
| `rProgression` | Menu use, reading corresponding R, then changing or writing code. |
| `sources` | Stable reference IDs, titles, URLs, scope, access date and intended editorial use. |
| `assessmentIds`, `practiceQuestions` | Links to existing questions and newly authored fixed-key questions. |

The lesson guide displays these explanations and references inside its existing collapsed panel, preserving space for the conversation. Expected discussion answers and MCQ keys are supplied to the tutor, not exposed as answers in the guide. Independent practice still disables the tutor and withholds keys until the attempt ends; it remains unsupervised practice, not a secure examination.

`LearningLibrary.context` supplies the selected enrichment as complete JSON, with a 6,500-character content budget checked for every bundled lesson. The host reserves context space for the workspace and method catalogue. Legacy provider lessons may omit the new fields. The reply and exported portfolio retain the supplied lesson ID and content version. Editorial URLs are clearly distinguished from pages actually fetched in a conversation; the tutor must not claim to have read a linked book.

`Learn/bank.mjs` adds the five JSON-authored questions to the established practice engine. Questions carry versions and per-choice explanations. Existing attempts retain their frozen question snapshots; this revision never inserts questions into an attempt already started. Increment a question's version when changing its wording or key, and increment the bank version. Preserve previous challenge wording when changing a study-guide prompt.

## Editorial basis and limits

Primary references include OHID's current [rates](https://fingertips.phe.org.uk/static-reports/public-health-technical-guidance/Basic_statistics/Rates.html), [direct](https://fingertips.phe.org.uk/static-reports/public-health-technical-guidance/Standardisation/DSRs.html) and [indirect](https://fingertips.phe.org.uk/static-reports/public-health-technical-guidance/Standardisation/ISRatios.html) standardisation guidance; Harrell's [regression and validation chapter](https://hbiostat.org/bbr/reg); Van Buuren's [missingness mechanisms](https://stefvanbuuren.name/fimd/sec-MCAR.html) and [simple methods](https://stefvanbuuren.name/fimd/sec-simplesolutions.html); and Cochrane's [trial bias](https://www.cochrane.org/authors/handbooks-and-manuals/handbook/current/chapter-08) and [meta-analysis](https://www.cochrane.org/authors/handbooks-and-manuals/handbook/current/chapter-10) chapters. The JSON records further references and their scope, including the What If author landing page rather than an assertion of a full-book audit.

These references inform original explanatory text and invented examples. Source chapters, proprietary checklists and official examination items are not copied into the library. Reading access is not treated as redistribution permission. DFPH preparation includes written interpretation and appraisal alongside any MCQ practice. No examination body, university or training provider endorsement is claimed.

Review is AI-assisted editorial and numerical checking, **not external subject-expert approval**. Statistical priorities include denominators, unit of observation, effect direction, uncertainty, design assumptions, causation and the distinction between illustrative calculations and validated methods. Causal foundations remain available to beginners; advanced labels describe depth rather than academic status.

## Verification

- Node learning, provider, library and lesson-context checks passed: 24 test executions, including repeated imported numerical checks. They cover metadata, references, prerequisites, source/guide escaping, practice scoring, frozen old attempts, provider compatibility and all 12 actual R scripts with independent numerical assertions and plot generation.
- Native Swift context checks passed for all 12 complete enrichment objects and legacy pack fallback.
- The native WKWebView workflow displayed all 12 enriched guides and references. A local protocol fixture verified that the selected missing-data lesson, its fixed answer key and reference metadata reached the tutor request, and that the lesson version was retained with the reply. Existing provider import, saved work, assessment, export and restore checks passed. This is not a live-model teaching evaluation.
- The unchanged Windows calculation core ran all 12 lesson examples through the Mac host. Additional checks reproduced the stated layouts, point estimates and meta-analysis interval below. The full engine suite was not rerun for this content/host change.
- The rebuilt local Mac app passed strict signature verification. Visual inspection confirmed the enriched guide and 35-question count; the conversation layout was adjusted so expanding a guide keeps Send visible.
- All five new R plots were rendered and inspected. Trial bounds are labelled as bounds rather than confidence limits; calibration is compared with the identity line; the meta-analysis uses the stated effect direction and zero reference.

| Example | Independent numerical check |
|---|---|
| Rates | Crude rates 840 and 360; both directly standardised rates 400 per 100,000 person-years with 75%/25% weights. |
| Trial appraisal | Observed-data RR 5/6; full-group programme risk bounds 20%–40%, yielding ARR bounds −10 to +10 percentage points. |
| Missing scores | Six observed values sum to 140; responder mean 23.333; full-eight mean bounds 17.5–27.5 for a 0–40 scale. |
| Prediction | Original RMSE √2.5; shifted RMSE √102.5; unchanged correlation and mean error changing from 0 to +10. |
| Meta-analysis | Weights 2500, 625, 2500; pooled risk difference −0.04, SE 1/75, 95% normal limits −0.0661328531 to −0.0138671469; Q = 1.25. |

No assessment email or live AI request was sent during verification. Provider accreditation remains an external decision.

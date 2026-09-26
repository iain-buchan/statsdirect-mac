# Educational content audit — 26 September 2026

The bundled teaching material has been reviewed and corrected in Mac build **0.3.9**. All 30 fixed MCQ keys remain correct; 14 items required clearer wording or assumptions. All seven lesson guides and R examples were revised. This is an AI-assisted subject-content audit with source checks and numerical verification, not independent human academic approval.

## Scope and method

Reviewed every current lesson's title, objective, summary, challenge, procedure instructions, fictional data and R script; every MCQ stem, option, key, distractor explanation, hint and teaching explanation; both tutor instruction sets; the sample course pack; the archived scripted teaching prototype; learning/exam-source descriptions; the R handoff manifest, generator and all 16 recipe/helper files. Imported Windows help and core numerical algorithms were outside this authored-content audit and were not modified.

For each teaching statement, the review checked the observational unit, study design, estimand, comparison direction, denominator, time horizon, independence, distributional assumptions and interpretation. Numerical teaching results were recomputed using base R and the actual StatsDirect engine. The review distinguished incorrect or ambiguous wording from useful additional precision. Sources below are methodological references; exam samples remain topic/format inspiration, not authorities for statistical correctness.

## Main corrections

- The paired guide now explicitly establishes the same people or matching, independence between pairs, and small-sample assumptions on **differences**. Different unmatched patients are not automatically paired or independent. The clinic diagnosis-count question remains under epidemiology; saved earlier guides retain their actual topic.
- The risk R script previously reported positive control-minus-programme risk reduction beside a programme-minus-control interval. Both now use the same direction. The base-R 95% reduction interval is **−0.001042731 to 0.121042731**; the engine's interval is **−0.001445058 to 0.123548112**. Both span zero. NNT **17** is a point estimate, with uncertainty extending through infinity into benefit and harm. The explanation now counts people with at least one admission, not repeated admissions. This interpretation follows [Cochrane's NNT guidance](https://www.cochrane.org/authors/handbooks-and-manuals/handbook/current/chapter-15#section-15-4-4) and R's [two-proportion interval definition](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/prop.test.html).
- The risk-grid instructions previously referred to group totals despite the form taking four event/non-event counts. The cohort guide now gives rows **30, 15 / 270, 285**; the age example gives **44, 26 / 156, 174**. Diagnostic grid orientation is also explicit.
- The precision challenge now states the common-population, independence and fixed finite-variance assumptions behind halving SE when quadrupling n. The 12 skewed waiting times no longer present a t interval without an assumption warning.
- Confounding explanations no longer diagnose causality simply from a change after adjustment. Effect modification is scale-specific; mediator adjustment does not automatically identify a direct effect; collider conditioning **can** induce association. The age example adds common-population standardisation, without treating equal adjusted risks as causal proof. See [Hernán and Robins](https://miguelhernan.org/whatifbook), chapters 6–8 and 23.
- The regression example explicitly contains eight **services**, not patients; its coefficient intervals are distinguished from predictions and individual causal effects. Diagnostic intervals are labelled by their target parameter. Ratio questions specify an adverse outcome before calling a lower ratio beneficial.
- R handoff comments now distinguish agreement limits from confidence limits, observed-direction tails from prespecified one-sided tests, rank tests from unrestricted median comparisons, and the conditional discordant-pair interval from a risk-difference interval.

## Seven lessons

| Lesson | Result of review and numerical verification |
|---|---|
| Epidemiological foundations | Initially disease-free cohort, complete one-year follow-up and comparable ascertainment stated; first cases 30/300 and 15/300, RR 2, difference 0.05. Risk, incidence rate and prevalence separated. |
| From association to causal questions | Baseline age and one-year follow-up stated. Crude RR 22/13, difference 0.09; younger risks both 0.10, older both 0.25; common 50/50 standardisation gives 0.175 in both groups. No causal conclusion from equality alone. |
| Comparing paired measurements | Eight exact aligned pairs; before-minus-after mean 5.25, df 7, t 5.3712631000, two-sided P 0.0010400979673, 95% CI 2.9387601501–7.5612398499. Engine and R agree. |
| Variation, precision and uncertainty | n 12, sum 232, mean 19.3333, median 17.5; sample variance and CI calculations checked. Small skewed-sample assumptions and influential waits discussed. |
| Interpreting a diagnostic test | TP 72, FN 18, FP 81, TN 729; sensitivity 0.8, specificity 0.9, PPV 8/17, NPV 81/83. Labelled sensitivity CI, reference diagnosis and transportability assumptions. |
| Absolute and relative benefit | Programme risk 0.08, control 0.14; reduction 0.06, RR 4/7, rounded NNT 17. Consistent interval direction and benefit/harm uncertainty; methods need not have identical interval endpoints. |
| Association is not causation | Eight service-level observations; regression slope checked against a separate centred cross-product calculation. Model assumptions, residuals, 10–24-minute observed range and coefficient-versus-prediction intervals stated. |

## All 30 fixed questions

“Retained” means the key, stem, distractors and explanation were reviewed and did not require a substantive change. Revised items have question version 2; the bank is `learn-draft-2026-09-26`.

| ID | Key | Review result |
|---|---|---|
| UG-SENS-01 | C | Retained; 72/90 = 80%; alternative denominators checked. |
| UG-NNT-01 | D | Revised; distinct participants, complete follow-up, point-estimate uncertainty; NNT 17. |
| UG-PVAL-01 | B | Retained; conditional null-model interpretation, not posterior probability. |
| UG-PAIR-01 | D | Retained; independent people, paired differences and causal limitation are explicit. |
| PG-PPV-01 | C | Retained; applicable sensitivity/specificity stipulated; 90/(90+495) = 15.3846%. |
| PG-CI-01 | B | Revised; specifies an adverse outcome before interpreting benefit; 42% reduction to 3% increase includes null RR 1. |
| PG-RROR-01 | A | Revised distractor removes an overly absolute rare-outcome claim; RR 1.5, OR 2.25. |
| PG-SE-01 | D | Retained; fixed SD, independent common-population observations; SE ratio 0.5. |
| PH-STAND-01 | C | Retained; common age weights yield annual standardised mortality rate 400 per 100,000. |
| PH-CONF-01 | A | Revised; baseline causal role stated, pattern consistent with confounding, no causal proof from adjustment; effect scale explicit. |
| PH-CLUST-01 | C | Retained; approximate variance design effect 1.76, SE factor is its square root. |
| PH-SMR-01 | C | Revised; age-specific person-time and implicit-weight comparability; 55/44 = 1.25. |
| AN-MED-01 | B | Retained; median/IQR resistant to extremes, but long waits remain relevant. |
| AN-PCT-01 | A | Retained; 10% to 8% is 2 percentage points and 20% relative reduction. |
| AN-CAUS-01 | B | Retained; illness severity is a plausible alternative explanation, not established causality. |
| AN-PREC-01 | B | Revised; same confidence level and binomial interval method; underlying proportion distinguished. R confirms larger-denominator interval is narrower. |
| RS-PAIR-01 | B | Retained; normality concerns differences, not separate marginal measurements. |
| RS-MULT-01 | D | Revised; independence belongs to tests, with actual false-positive probability 0.05; 1−0.95^20 = 64.1514%. |
| RS-MISS-01 | C | Retained; possible bias and precision loss, without assuming the direction or automatically declaring MNAR. |
| RS-CI-01 | B | Retained; target repeated-sampling coverage under assumptions. |
| PG-ROC-01 | B | Revised feedback; on fixed observations a higher positive threshold cannot decrease specificity; unchanged if nobody switches. |
| PG-LR-01 | C | Retained; prior odds 1/9, posterior odds 2/3, posterior probability 0.4. |
| PG-FOREST-01 | B | Revised; adverse outcome and corresponding null test stated. Significance in one study alone does not prove a difference between studies. |
| AN-RATE-01 | C | Retained; referral rate 24 versus 18 per 1,000 does not determine absolute counts or quality. This is an operational service rate, not a person-time incidence rate. |
| PH-CASEMIX-01 | C | Revised; define whether discharge pathways are part of the target service effect before adjustment. |
| RS-LEAD-01 | B | Retained; earlier diagnosis with unchanged death time increases measured survival without postponing death. |
| CORE-DESIGN-01 | B | Revised; exposure OR calculation distinguished from target parameter, which depends on control sampling and analysis. No automatic rare-disease requirement. |
| CORE-RATE-01 | A | Revised; specifically an **incidence** rate uses time at risk; 12/600 = 2 per 100 person-years. |
| CORE-MEDIATOR-01 | B | Revised; regression adjustment for a mediator does not automatically identify a causal direct effect. |
| CORE-SELECTION-01 | B | Revised explanation; selection on a common consequence can induce association, rather than necessarily doing so. |

## Tutor, history and maintenance

Both tutor instruction sets now require explicit design, denominators, comparison direction and assumptions; distinguish causal reasoning from statistical adjustment; and guard against the misconceptions above. Native prompt version is `statsdirect-chatgpt-tutor-v3`; the optional managed service has corresponding v3 instructions. Tool availability remains different between those hosts.

The course-pack sample now explains that direct effects need additional identification assumptions. Its review guidance remains formative. Course material is reference content rather than permission to override statistical reasoning or award accreditation.

The old Python generator contained superseded paired-guide text. `Learn/lessons.json` is now the canonical source; publishing copies it into the app. The archived prototype imports its original twelve questions from the maintained bank. Tests catch divergence. Changed challenge text is retained solely to identify historical prompts. Existing quiz attempts retain their original wording, keys and scores; review export now consistently uses those frozen snapshots. No learner history was rewritten.

These checks cover fixed bundled content and instructions. Future model-generated explanations and user-supplied course packs are not thereby verified. Formal assessment validity, blueprint coverage and external accreditation require separate review. No live tutor conversation was submitted as part of this audit.

## Verification

- 16 learning/history/archive tests passed, including R execution and plot creation for all seven lessons, numerical-option checks, preserved scoring and topic attribution.
- All seven lesson workflows ran through the unchanged engine; numerical checks cover paired inference, diagnostic measures, NNT direction/uncertainty, cohort risk and both age strata. Descriptive and regression workflows completed; their lesson calculations were also checked in R.
- The generated-R suite passed all 37 operation fixtures plus selected-range, missing-pair, confidence-level, result-table and contingency handoff cases.
- Swift compiled; build 0.3.9 passed strict local signature verification. Its engine binary is identical to 0.3.8.
- An isolated native app verified Help → Learning, the revised paired challenge, collapse/attribution of the earlier epidemiology guide, and the expanded risk guide with consistent direction and NNT uncertainty. The test app was then closed; the user’s open app and documents were left running.

## Methodological references

- [NIST: paired observations](https://www.itl.nist.gov/div898/handbook/prc/section3/prc311.htm) and [regression assumptions](https://itl.nist.gov/div898/handbook/pri/section2/pri245.htm): pairing, difference-based inference and regression assumptions.
- [CDC: measures of disease frequency](https://archive.cdc.gov/www_cdc_gov/csels/dsepd/ss1978/lesson3/section2.html): risk, incidence rates, time at risk and prevalence.
- [ASA: P-value statement](https://www.amstat.org/asa/files/pdfs/p-valuestatement.pdf): null-model interpretation, magnitude, uncertainty and limitations of threshold-based claims.
- [Cochrane chapter 15](https://www.cochrane.org/authors/handbooks-and-manuals/handbook/current/chapter-15): effect interpretation and NNT intervals spanning benefit/harm; [chapter 23](https://training.cochrane.org/handbook/current/chapter-23): cluster design effects.
- [R: prop.test](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/prop.test.html): two-proportion direction and approximate interval semantics; local R documentation and execution for the other base-R examples.
- [CDC surveillance guidance](https://www.cdc.gov/mmwr/preview/mmwrhtml/00001769.htm): diagnostic denominators and predictive values.
- [Hernán and Robins: Causal Inference: What If](https://miguelhernan.org/whatifbook): author-linked 19 August 2026 text, relevant sections of chapters 6–8 and 23 inspected for adjustment, selection and mediation assumptions. The old Harvard download links failed; the author-hosted PDF was obtained successfully.
- [Pearce: What does the odds ratio estimate in a case-control study?](https://pubmed.ncbi.nlm.nih.gov/8144304/) and [Labrecque et al.: case-control estimands](https://pmc.ncbi.nlm.nih.gov/articles/PMC7850067/): sampling determines interpretation; a disease-risk OR is not interchangeable with all case-control exposure OR calculations.
- [NCI: screening overview](https://www.cancer.gov/about-cancer/screening/hp-screening-overview-pdq): lead-time bias and screening outcomes.

The detailed pre-existing [exam-source access record](EXAM-SOURCES.md) is retained. This audit does not claim access to gated MRCP questions or previously unavailable FPH PDFs.

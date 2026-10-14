# Learning content refinements — 12 October 2026

The risk/NNT, diagnostic, precision and meta-analysis lessons now have content version `2026-10-12`. The library still contains twelve lessons and **35** fixed-key questions: the original 30 plus five `LIB-*` questions. No question wording, keys or versions changed, and saved attempts retain their snapshots.

## Methods and interpretation

- **Risk and NNT:** the fictional trial was deliberately chosen near the conventional 5% significance boundary. Its ARR is 0.06 and NNT for benefit is 17. The R example now explicitly inverts the **Miettinen–Nurminen score** with the finite-sample variance correction, matching StatsDirect. It replaces the former two-sample `prop.test()` Wald interval. The 95% limits are **−0.00144505772741457 to 0.123548112373396** on the risk-difference scale. They include zero and possible harm; reciprocals cannot be described as one ordinary finite NNT interval. Method choice must follow the design, not the desired significance. The base-R helper handles zero/all events, unequal groups and either direction, and fails if the root search does not converge.
- **Diagnostic sensitivity:** StatsDirect and `binom.test()` use **Clopper–Pearson exact binomial** limits. For 72/90, the 95% interval is **0.702457549867273 to 0.876944453989086**, explained as about **70.2% to 87.7%**. This is a sensitivity interval, not a PPV interval; exact binomial coverage can be conservative.
- **Mean waiting time:** StatsDirect and `t.test()` use the **Student t** interval with 11 degrees of freedom. The narrative now reports mean **19.3 minutes** and interval **13.8 to 24.8 minutes**, retaining computational precision in R. Agreement does not establish the assumptions for twelve skewed observations, nor remove selection bias.
- **Meta-analysis:** the narrative reports pooled risk difference **−4 percentage points**, with normal 95% limits about **−6.6 to −1.4 percentage points**. An optional R extension explains conventional Q-based I²: Q = 1.25 and df = 2 give a truncated estimate of 0%. Three studies provide little information about heterogeneity; zero does not prove identical underlying effects, and model choice must not depend solely on Q's P value or I².

There is no method that is universally most accurate for every design. These examples explicitly select and explain the appropriate stated method instead of accepting a different default. They do not change the user's R installation or global R behaviour.

## Primary references

- [StatsDirect NNT help](https://www.statsdirect.com/help/clinical_epidemiology/nnt.htm) identifies Miettinen–Nurminen risk-difference limits. The pinned engine's `MathDbl.uppci` and `RptMiscNumberNeededToTreat` implementation were also checked.
- [R binom.test documentation](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/binom.test.html) names Clopper–Pearson limits; [R t.test documentation](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/t.test.html) describes the t interval.
- [Cochrane Handbook chapter 10](https://www.cochrane.org/authors/handbooks-and-manuals/handbook/current/chapter-10) informs the original heterogeneity explanation and its limitations.

References keep their individual access dates. The guide distinguishes these from the lesson's editorial review date; updating wording does not pretend that every earlier reference was read again.

## Verification

R **4.6.1**, with the unchanged StatsDirect **5.1.0** engine pinned at `3cc4cbc92ab779880d7fc8f04d1a94ee47e2b620`.

- All twelve actual bundled R scripts run without additional packages, satisfy numerical assertions and produce plots. The optional I² block is tested both for the supplied example and a more heterogeneous set of effects.
- All twelve lesson examples run through the Mac host's calculation engine. Diagnostic and NNT confidence limits are checked alongside the existing paired-t and meta-analysis numerical comparisons.
- The actual lesson's MN helper matches the Windows calculation core in **36** cases at 90%, 95% and 99% confidence: ordinary, rare and zero/all events, equal and unequal groups, and extreme differences. Reversing groups and complementing outcomes reverse the limits; intervals widen with confidence; invalid counts and confidence levels fail.
- Numerical answer checks now cover the five added `LIB-*` questions as well as the original numerical questions. All 35 stems, keys, options and feedback were reviewed; no further correction was identified.
- Learning tests retain frozen historical attempts, independent-practice answer withholding, safe references and legacy provider-pack compatibility. Native context checks ensure each complete curated enrichment remains within the 6,500-character budget.
- The Mac tutor receives the full R helper, with the overall context budget unchanged. Library diagnostics report the newest lesson revision rather than the first lesson's revision.
- **28** learning test executions and **8** worksheet/tutor privacy tests passed, together with the Swift context checks. The native WKWebView suite displayed all twelve complete interpretations, ran the revised risk lesson in the R pane and verified the full script in a local mock tutor request. Provider import, assessment, saved evidence, export and restore also passed. No live-model reply or assessment email was sent.
- The updated local release build is `.build/lesson-refinements/StatsDirect.app`. It passed strict signature verification and has matching native debug symbols. It uses the previously validated, unchanged engine bundle; the running user app was not replaced.

Reproduce with `node --test Learn/*.test.mjs`, `node --test Grid/tutor-data.test.mjs Grid/tutor-privacy.test.mjs`, `python3 Tests/test_learning_examples.py`, the Swift library check documented in `Learn/README.md`, and `bash Scripts/test-provider-learning.sh <base-app>`.

This remains **AI-assisted editorial and numerical review**. The other AI's review is additional evidence, not an external human subject-expert sign-off. The pending-review notice has been removed from the learner interface, exported records and lesson metadata. No accreditation or CPD award is inferred.

The changes are in the Mac learning content, guide and Mac host metadata. The shared calculation engine, shared report editor and Windows application are unchanged.

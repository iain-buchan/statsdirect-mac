(() => {
  // Learn/bank.mjs
  var bankVersion = "learn-draft-2026-09-25";
  var tracks = {
    foundation: { title: "Medical undergraduate", description: "Understand the question, choose the method, interpret the result." },
    medicine: { title: "Postgraduate medicine", description: "Interpret diagnostic evidence, treatment effects and uncertainty." },
    publicHealth: { title: "Public health postgraduate", description: "Work with population comparisons, bias and study design." }
  };
  var options = (...rows) => rows.map(([text, feedback2], i) => ({ id: String.fromCharCode(65 + i), text, feedback: feedback2 }));
  var questions = [
    {
      id: "UG-SENS-01",
      version: 1,
      track: "foundation",
      topic: "Sensitivity",
      objective: "Choose the denominator for sensitivity.",
      stem: "In a fictional diagnostic study, 90 people have the condition and 810 do not. The test is positive in 72 of the 90 people with the condition and in 81 of the 810 without it. What is the sensitivity?",
      options: options(["20%", "This is the false-negative proportion: 18/90."], ["47.1%", "This is the positive predictive value: 72/(72+81)."], ["80%", "Use the people with the condition as the denominator: 72/90."], ["90%", "This is the specificity: 729/810."], ["97.6%", "This is the negative predictive value: 729/(729+18)."]),
      correct: "C",
      hint: "Start with the people known to have the condition. How many did the test detect?",
      lesson: "Sensitivity asks: among people with the condition, what proportion test positive? Positive predictive value reverses the question: among people with a positive result, what proportion have the condition?",
      explanation: "Sensitivity = true positives / (true positives + false negatives) = 72/90 = 80%. The 81 false positives matter for specificity and predictive values, not for this denominator.",
      calculation: { kind: "sensitivity", tp: 72, fn: 18, expected: 0.8 },
      help: "clinical_epidemiology/diagnostic.htm",
      operation: "MiscDiagnostic"
    },
    {
      id: "UG-NNT-01",
      version: 1,
      track: "foundation",
      topic: "Absolute benefit and NNT",
      objective: "Calculate NNT and retain the follow-up period.",
      stem: "Over one year, a randomised trial records an unplanned admission in 16 of 200 people receiving a new programme and 28 of 200 receiving usual care. Using these point estimates, what is the number needed to treat to prevent one admission over one year, rounded up to a whole person?",
      options: options(["6", "Six percentage points is the absolute risk reduction, not its reciprocal."], ["7", "The absolute reduction is 0.06, so its reciprocal is larger than 7."], ["12", "Twelve is the difference in event counts, not NNT."], ["17", "1/(0.14\u22120.08) = 16.67, rounded up to 17."], ["43", "About 43% is the relative risk reduction; NNT uses absolute risk reduction."]),
      correct: "D",
      hint: "Calculate the two event risks, subtract them, then take the reciprocal of that absolute difference.",
      lesson: "NNT connects an absolute reduction in risk to the number of people treated. It depends on baseline risk, the outcome and the follow-up period. A point estimate alone does not describe its uncertainty.",
      explanation: "Usual-care risk is 28/200 = 0.14. Programme risk is 16/200 = 0.08. The absolute reduction is 0.06, so NNT = 16.67, conventionally rounded up to 17, for this outcome over one year.",
      calculation: { kind: "nnt", controlEvents: 28, controlN: 200, treatmentEvents: 16, treatmentN: 200, expected: 17 },
      help: "clinical_epidemiology/nnt.htm",
      operation: "MiscNumberNeededToTreat"
    },
    {
      id: "UG-PVAL-01",
      version: 1,
      track: "foundation",
      topic: "P values",
      objective: "Interpret a P value conditional on a null model.",
      stem: "A prespecified two-sided analysis gives P = 0.03. Which interpretation is most accurate?",
      options: options(["The null hypothesis has a 3% probability of being true.", "A P value is not a posterior probability for the null hypothesis."], ["If the null model and its assumptions hold, a test statistic at least as extreme as this has probability 3%.", "This is the repeated-sampling interpretation under the specified null model."], ["The treatment has a 97% probability of working.", "A P value does not give the probability that a treatment works."], ["The estimated treatment effect is clinically important.", "Clinical importance depends on the effect size, uncertainty, harms and context."], ["There is a 3% probability that the study contains any bias.", "P values do not measure the probability of bias."]),
      correct: "B",
      hint: "Which statement starts by assuming the null model, rather than assigning a probability to it?",
      lesson: "A P value measures compatibility with a specified null model using a chosen test statistic. It does not determine clinical importance or rule out bias. Read it alongside the effect estimate and confidence interval.",
      explanation: "The probability refers to possible test statistics under the null model and its assumptions. It is not the probability that the null is true, that the finding is a chance accident, or that the effect matters clinically.",
      help: "basics/p_values.htm",
      operation: null
    },
    {
      id: "UG-PAIR-01",
      version: 1,
      track: "foundation",
      topic: "Choosing a paired analysis",
      objective: "Match a comparison to its paired structure.",
      stem: "Eighteen independently sampled adults each have a measurement before and after an intervention. Their within-person differences are approximately normally distributed, with no major outliers. Which test directly assesses whether the population mean change is zero?",
      options: options(["Unpaired t test", "Treating the observations as independent loses the within-person pairing."], ["Pearson chi-square test", "This is not a comparison of categorical counts."], ["Mann\u2013Whitney test", "This test is for independent groups, not paired observations."], ["Paired t test", "The paired t test is a one-sample t test of the within-person differences."], ["Pearson correlation test", "Correlation measures association, not whether the mean change is zero."]),
      correct: "D",
      hint: "What single value could you compute for each participant?",
      lesson: "Subtract each person\u2019s before value from their after value, using the same direction for everyone. The paired t test operates on those differences. The normality assumption concerns the differences.",
      explanation: "Use a paired t test on the 18 within-person differences. A before\u2013after change alone does not establish that the intervention caused it; a causal claim needs an appropriate study design.",
      help: "parametric_methods/paired_t.htm",
      operation: "TPaired"
    },
    {
      id: "PG-PPV-01",
      version: 1,
      track: "medicine",
      topic: "Predictive value and prevalence",
      objective: "Combine prevalence, sensitivity and specificity.",
      stem: "A fictional screening test has sensitivity 90% and specificity 95%. Assume these apply in a population with prevalence 1%. Approximately what proportion of positive results would be true positives?",
      options: options(["1%", "Prevalence is the probability before seeing the test result."], ["5%", "This is the false-positive rate among people without the condition."], ["15.4%", "For 10,000 people, expect 90 true positives and 495 false positives: 90/585."], ["90%", "Sensitivity conditions on having the condition, not on a positive test."], ["95%", "Specificity conditions on not having the condition."]),
      correct: "C",
      hint: "Imagine 10,000 people. Work out true positives and false positives separately.",
      lesson: "At low prevalence, people without the condition greatly outnumber those with it. Even a modest false-positive rate can therefore produce many false positives. Keep sensitivity and predictive value separate.",
      explanation: "Among 10,000 people, 100 have the condition, producing 90 true positives. The other 9,900 produce 495 false positives. PPV = 90/(90+495) = 15.38%.",
      calculation: { kind: "ppv", prevalence: 0.01, sensitivity: 0.9, specificity: 0.95, expected: 0.15384615384615385 },
      help: "clinical_epidemiology/diagnostic.htm",
      operation: "MiscDiagnostic"
    },
    {
      id: "PG-CI-01",
      version: 1,
      track: "medicine",
      topic: "Confidence intervals",
      objective: "Distinguish inconclusive evidence from evidence of no effect.",
      stem: "A trial estimates a risk ratio of 0.76 with a 95% confidence interval from 0.58 to 1.03. Which conclusion best describes these results?",
      options: options(["The trial proves that the intervention has no effect.", "Including 1 does not prove the absence of an effect."], ["The results are compatible with appreciable benefit and a small increase in risk; they do not exclude no effect.", "The interval spans a 42% reduction through a 3% increase and includes a risk ratio of 1."], ["There is a 95% probability that this particular interval contains the true effect.", "That is not the frequentist repeated-sampling interpretation of a confidence interval."], ["The intervention reduces risk by exactly 24% in every patient.", "A group-level point estimate is uncertain and is not an individual guarantee."], ["Increasing the sample size would guarantee a statistically significant benefit.", "A larger sample can improve precision but cannot guarantee that conclusion."]),
      correct: "B",
      hint: "For a ratio, what value represents no difference? What range of effects does the interval allow?",
      lesson: "For risk ratios the null value is 1; for risk differences it is 0. An interval that includes the null can also include important benefit or harm. Its width tells you about precision.",
      explanation: "The estimate favours benefit, but the interval includes no effect and a small increase in risk. Interpret the magnitude and precision together; clinical decisions also require harms, costs and other evidence.",
      help: "basics/confidence_interval.htm",
      operation: "PropUnPaired"
    },
    {
      id: "PG-RROR-01",
      version: 1,
      track: "medicine",
      topic: "Risk and odds",
      objective: "Recognise that odds ratios and risk ratios differ for common outcomes.",
      stem: "In a fictional cohort, an outcome occurs in 120 of 200 exposed people and 80 of 200 unexposed people. Which pair gives the exposed-to-unexposed risk ratio and odds ratio?",
      options: options(["Risk ratio 1.50; odds ratio 2.25", "Risks are 0.6 and 0.4; odds are 120/80 and 80/120."], ["Risk ratio 2.25; odds ratio 1.50", "These two statistics have been exchanged."], ["Risk ratio 1.50; odds ratio 1.50", "The odds ratio only approximates the risk ratio when the outcome is sufficiently rare."], ["Risk ratio 0.67; odds ratio 0.44", "These compare unexposed with exposed, reversing the requested direction."], ["Risk ratio 0.20; odds ratio 0.20", "0.20 is the absolute risk difference."]),
      correct: "A",
      hint: "Risk divides events by everyone in the group. Odds divides events by non-events.",
      lesson: "Always identify the reference group. Risks and odds are different quantities; with common outcomes, an odds ratio can be much further from 1 than the corresponding risk ratio.",
      explanation: "RR = (120/200)/(80/200) = 1.5. OR = (120/80)/(80/120) = 2.25. These observational comparisons do not by themselves establish causation.",
      calculation: { kind: "riskOdds", a: 120, b: 80, c: 80, d: 120, expected: [1.5, 2.25] },
      help: "clinical_epidemiology/risk_prospective.htm",
      operation: "MiscRelRisk"
    },
    {
      id: "PG-SE-01",
      version: 1,
      track: "medicine",
      topic: "Precision and sample size",
      objective: "Apply the square-root relationship between sample size and standard error.",
      stem: "For independent observations from the same population, assume the standard deviation stays fixed. If the sample size increases from 100 to 400, what happens to the standard error of the sample mean?",
      options: options(["It is unchanged.", "The standard error depends on sample size even when the population standard deviation is unchanged."], ["It becomes one quarter as large.", "Standard error falls with the square root of sample size, not sample size itself."], ["It doubles.", "A larger independent sample makes the mean more precise."], ["It becomes half as large.", "SE = SD/\u221An, so the ratio is \u221A(100/400) = 0.5."], ["It becomes zero.", "Finite samples retain sampling uncertainty."]),
      correct: "D",
      hint: "Use SE = SD divided by the square root of n.",
      lesson: "Standard deviation describes variation between observations; standard error describes sampling variation in an estimate. Quadrupling an independent sample halves the standard error when the standard deviation stays fixed.",
      explanation: "SE(new)/SE(old) = \u221A100/\u221A400 = 0.5. Dependence or clustering changes the calculation, and systematic bias is not removed by increasing sample size.",
      calculation: { kind: "seRatio", oldN: 100, newN: 400, expected: 0.5 },
      help: "basics/precision.htm",
      operation: "UnivariateSummary"
    },
    {
      id: "PH-STAND-01",
      version: 1,
      track: "publicHealth",
      topic: "Direct standardisation",
      objective: "Apply common population weights to age-specific rates.",
      stem: "A district has annual mortality rates of 200 per 100,000 in its younger age group and 1,000 per 100,000 in its older group. A standard population contains 75% younger and 25% older people. What is the directly age-standardised annual rate per 100,000?",
      options: options(["200", "This uses only the younger group."], ["300", "The weighted contribution of the older group alone is 250, in addition to 150 from the younger group."], ["400", "0.75 \xD7 200 + 0.25 \xD7 1,000 = 400."], ["600", "This would use equal weights rather than the supplied standard population."], ["1,200", "Adding the rates ignores the population weights."]),
      correct: "C",
      hint: "Multiply each age-specific rate by its share of the standard population, then add.",
      lesson: "Direct standardisation applies each population\u2019s stratum-specific rates to a common set of weights. The resulting rate is a comparison summary, not necessarily the population\u2019s observed crude rate.",
      explanation: "The younger contribution is 150 and the older contribution is 250, giving 400 per 100,000 per year. Use the same standard weights when comparing districts.",
      calculation: { kind: "weightedRate", rates: [200, 1e3], weights: [0.75, 0.25], expected: 400 },
      help: "rates/direct_standardization.htm",
      operation: "RateDirectScreen"
    },
    {
      id: "PH-CONF-01",
      version: 1,
      track: "publicHealth",
      topic: "Confounding",
      objective: "Interpret a change between crude and stratified associations.",
      stem: "An observational comparison gives a crude risk ratio of 2.0. The exposed group is older. In every age stratum the risk ratio is 1.0, with adequate data and accurate measurement. Which explanation is most consistent with this pattern?",
      options: options(["Age confounding explains the crude association.", "Different age distributions can create a crude association when no association remains within age strata."], ["Age is certainly a mediator of the exposure effect.", "The information does not establish a causal pathway through age."], ["There must be strong effect modification by age.", "The stated stratum-specific risk ratios do not vary with age."], ["The exposure has been proved harmless in every setting.", "Removing this observed association does not establish universal safety or remove other biases."], ["The crude risk ratio is necessarily an arithmetic error.", "A correctly computed crude ratio can differ from stratum-specific ratios."]),
      correct: "A",
      hint: "Distinguish imbalance in a third variable from variation of the effect across strata.",
      lesson: "Confounding can mix the effect of an exposure with differences in other determinants of the outcome. Effect modification instead describes variation in the association across strata. A causal diagram and design knowledge help decide what to adjust for.",
      explanation: "The equal stratum-specific ratios and different age distributions support age confounding as the explanation offered here. The conclusion is conditional on the stated data quality; it does not prove that all sources of bias are absent.",
      help: "basics/confounding.htm",
      operation: "MantelHaenszelScreen"
    },
    {
      id: "PH-CLUST-01",
      version: 1,
      track: "publicHealth",
      topic: "Clustered observations",
      objective: "Recognise the loss of precision from within-cluster correlation.",
      stem: "A survey uses equal clusters of 20 people. For its outcome, the intracluster correlation is 0.04. Using the approximation DE = 1 + (m \u2212 1)\u03C1, what is the design effect relative to simple random sampling?",
      options: options(["1.04", "The correlation is multiplied by m\u22121, not added just once."], ["1.20", "Insert m = 20 and \u03C1 = 0.04 into the stated formula."], ["1.76", "1 + 19 \xD7 0.04 = 1.76."], ["2.00", "The supplied values give a smaller variance inflation."], ["20.00", "A design effect of 20 under this formula would require perfect within-cluster correlation."]),
      correct: "C",
      hint: "Here m is the number of people in each cluster, not the number of clusters.",
      lesson: "People in one cluster may provide partly overlapping information. This approximation multiplies the variance by the design effect; standard errors are multiplied by its square root. Unequal cluster sizes and few clusters need more careful planning.",
      explanation: "DE = 1 + (20\u22121) \xD7 0.04 = 1.76. Under this approximation, nominal sample size divided by 1.76 gives an effective sample size; it is not a substitute for a full cluster-design calculation.",
      calculation: { kind: "designEffect", m: 20, rho: 0.04, expected: 1.76 },
      help: "basics/precision.htm",
      operation: null
    },
    {
      id: "PH-SMR-01",
      version: 1,
      track: "publicHealth",
      topic: "Standardised mortality ratio",
      objective: "Interpret observed relative to expected events.",
      stem: "A population has 55 observed deaths over the study period. Applying reference age-specific rates to its age distribution gives 44 expected deaths. What is the standardised mortality ratio, expressed as a ratio rather than a percentage?",
      options: options(["0.20", "This is neither the observed-to-expected ratio nor its reciprocal."], ["0.80", "This reverses observed and expected."], ["1.25", "55/44 = 1.25."], ["11", "Eleven is the difference in counts."], ["125", "125 is the SMR expressed on a percentage scale, not the requested ratio scale."]),
      correct: "C",
      hint: "Use observed deaths divided by expected deaths.",
      lesson: "An SMR compares observed with expected events based on reference stratum-specific rates. Always state whether you use a ratio scale (null 1) or percentage scale (null 100), and include uncertainty.",
      explanation: "SMR = 55/44 = 1.25, or 25% more deaths than expected on this reference. The point estimate alone does not establish statistical significance or causation.",
      calculation: { kind: "smr", observed: 55, expectedDeaths: 44, expected: 1.25 },
      help: "rates/smr.htm",
      operation: "RateSmrScreen"
    }
  ];
  tracks.analyst = { title: "Healthcare / business analyst", description: "Describe services, compare performance and communicate uncertainty." };
  tracks.researcher = { title: "Researcher / degree module", description: "Choose methods, check assumptions and interpret research evidence." };
  questions.push(
    { id: "AN-MED-01", version: 1, track: "analyst", topic: "Skewed service data", objective: "Choose a resistant description of a typical waiting time.", stem: "Most clinic waits are 10\u201325 minutes, but a few exceed two hours. Which summary is least affected by these unusually long waits when describing a typical patient\u2019s wait?", options: options(["Mean and standard deviation", "Both are influenced by unusually large values."], ["Median and interquartile range", "The median describes the middle observation and the IQR the middle half."], ["Maximum only", "The maximum describes an extreme, not a typical observation."], ["Standard error only", "This concerns precision of an estimate, not a typical wait."], ["P value", "This does not describe the distribution."]), correct: "B", hint: "Consider a measure based on ordered positions rather than the sum.", lesson: "Use a histogram with median and IQR for a resistant summary, while retaining the long waits as operationally important observations.", explanation: "Median and IQR resist the influence of extreme waits. They do not make long waits irrelevant: report tail performance separately when it matters.", help: "basic_descriptive_statistics/univariate_summary.htm", operation: "UnivariateSummary" },
    { id: "AN-PCT-01", version: 1, track: "analyst", topic: "Percentage points", objective: "Distinguish an absolute percentage-point change from a relative change.", stem: "The non-attendance rate falls from 10% to 8%. Which statement correctly describes both the absolute and relative reduction?", options: options(["2 percentage points; 20% relative reduction", "(0.10\u22120.08)/0.10 = 0.20."], ["2 percentage points; 2% relative reduction", "The relative reduction divides by the starting risk."], ["20 percentage points; 2% relative reduction", "This reverses and mis-scales the changes."], ["8 percentage points; 80% relative reduction", "These describe the new rate or its ratio, not the reduction."], ["No reduction", "The rate decreased."]), correct: "A", hint: "Subtract for the absolute change; divide that change by the starting value for the relative change.", lesson: "State both absolute and relative changes, and include denominators and time periods.", explanation: "The absolute fall is 0.02, or two percentage points. Relative to the original 0.10 it is a 20% reduction. These rates alone do not establish what caused the reduction.", help: "clinical_epidemiology/risk_prospective.htm", operation: "MiscRelRisk" },
    { id: "AN-CAUS-01", version: 1, track: "analyst", topic: "Association and causation", objective: "Recognise confounding in service comparisons.", stem: "Hospitals with more specialist staff also have higher mortality. They receive the most severely ill patients. What is the best first interpretation?", options: options(["Specialists cause deaths", "The observational comparison does not support this causal claim."], ["Severity may confound the association", "Severity can affect staffing needs and mortality."], ["More staff must prevent every death", "This is not supported either."], ["Mortality cannot be compared statistically", "Comparisons are possible, with careful design and adjustment."], ["A small P value would eliminate confounding", "Statistical significance does not remove systematic bias."]), correct: "B", hint: "What differs between the patients cared for by these hospitals?", lesson: "Case mix is essential to interpreting service comparisons. Adjustment needs design knowledge and measured relevant variables.", explanation: "Severity is a plausible confounder. Compare like with like where possible and describe remaining limitations; an adjusted model alone does not prove causation.", help: "basics/confounding.htm", operation: null },
    { id: "AN-PREC-01", version: 1, track: "analyst", topic: "Precision of a rate", objective: "Relate denominators to uncertainty.", stem: "Two services both observe a 10% event rate. One records 10 events among 100 people, the other 100 among 1,000. Assuming independent comparable observations, which usually has the narrower confidence interval?", options: options(["The service with 100 people", "It has less information about the population rate."], ["The service with 1,000 people", "A larger independent denominator improves precision at the same observed rate."], ["Both must have identical intervals", "Equal point estimates can have different uncertainty."], ["Neither can have an interval", "A confidence interval can be calculated for either rate."], ["The service with the smaller P value, regardless of denominator", "The question concerns precision of an estimated rate."]), correct: "B", hint: "Consider the standard error \u221A(p(1\u2212p)/n).", lesson: "Show denominators and uncertainty alongside performance rates.", explanation: "At the same rate, a larger independent sample generally gives a narrower interval. Clustering, bias and different case mix can complicate real comparisons.", help: "basics/confidence_interval.htm", operation: null },
    { id: "RS-PAIR-01", version: 1, track: "researcher", topic: "Paired assumptions", objective: "Identify the relevant distributional assumption for a paired t test.", stem: "Which distribution should be checked for major departures from normality when using a paired t test with a small sample of independent pairs?", options: options(["The pooled before and after measurements", "Pooling ignores pairing."], ["The within-pair differences", "The test is a one-sample t test of these differences."], ["The participant identification numbers", "Identifiers have no relevant distribution."], ["The P values", "These are outputs rather than the observations being modelled."], ["Only the before measurements", "The test operates on differences."]), correct: "B", hint: "What single observation enters the test for each pair?", lesson: "Check differences and the independence of pairs; investigate outliers and whether the study design supports the intended inference.", explanation: "The paired t test models within-pair differences. It does not require the two original measurement distributions individually to be normal.", help: "parametric_methods/paired_t.htm", operation: "TPaired" },
    { id: "RS-MULT-01", version: 1, track: "researcher", topic: "Multiple testing", objective: "Recognise false-positive risk across many tests.", stem: "Twenty independent null hypotheses are all true. Each is tested at a 5% significance level. What is the probability of at least one false positive, approximately?", options: options(["5%", "This is the level for one test, not the whole family."], ["10%", "Use the probability of no false positives across all tests."], ["36%", "This is approximately the probability of no false positives."], ["64%", "1\u22120.95^20 is approximately 0.642."], ["100%", "A false positive is not guaranteed."]), correct: "D", hint: "The chance of no false positives is 0.95 multiplied by itself twenty times.", lesson: "Prespecify analyses and distinguish confirmatory from exploratory work. Multiplicity affects interpretation.", explanation: "Under the stated independence assumption, P(at least one) = 1\u22120.95^20 \u2248 64.2%. Dependence changes this calculation.", help: "basics/p_values.htm", operation: null },
    { id: "RS-MISS-01", version: 1, track: "researcher", topic: "Missing data", objective: "Recognise bias from outcome-related missingness.", stem: "Participants with the worst symptoms are more likely to miss their follow-up visit. What is the main concern with analysing only complete records?", options: options(["It necessarily removes all bias", "Removing missing records does not fix selective follow-up."], ["It always gives the same result as full follow-up", "Missingness can depend on outcomes."], ["It may produce a biased estimate as well as lose precision", "Complete cases may systematically differ from those missing."], ["It proves the symptoms improved", "Non-attendance is not an observed improvement."], ["A larger sample guarantees no bias", "More observations do not remove systematic selection."]), correct: "C", hint: "Are the observed participants representative of everyone originally enrolled?", lesson: "Describe missingness, investigate its causes and justify assumptions for sensitivity analyses or imputation.", explanation: "Outcome-related missingness can make complete cases unrepresentative. The direction and size of bias depend on the setting and missingness process.", help: "basics/bias.htm", operation: null },
    { id: "RS-CI-01", version: 1, track: "researcher", topic: "Confidence interval interpretation", objective: "Interpret repeated-sampling coverage.", stem: "What does a 95% frequentist confidence procedure aim to achieve under its assumptions?", options: options(["95% of individual observations lie in every interval", "This confuses a parameter interval with a range of observations."], ["95% of intervals from repeated samples contain the fixed population parameter", "Coverage refers to the procedure across repeated samples."], ["The null hypothesis is true with probability 95%", "This is not a posterior probability."], ["95% of future studies give exactly the same estimate", "Estimates vary between samples."], ["Bias is eliminated in 95% of studies", "Coverage relies on model and design assumptions."]), correct: "B", hint: "Imagine repeating the sampling and interval calculation many times.", lesson: "A confidence interval reports precision under assumptions; it does not protect against every source of bias.", explanation: "The 95% refers to long-run coverage of the fixed parameter by the interval procedure, provided the relevant assumptions hold.", help: "basics/confidence_interval.htm", operation: null }
  );
  questions.push(
    { id: "PG-ROC-01", version: 1, track: "medicine", topic: "Diagnostic thresholds", objective: "Recognise the sensitivity\u2013specificity trade-off.", stem: "In a fictional study, a blood marker is considered positive above a chosen cut-off. Researchers raise that cut-off while keeping the same participants and reference diagnoses. Which change in classification is possible?", options: options(["Some previously negative results become positive", "Raising the cut-off cannot do this on the same data."], ["Some true positives and false positives become negative", "A higher cut-off can reduce both true-positive and false-positive counts."], ["Sensitivity must increase", "A higher cut-off cannot capture additional positive cases on the same data."], ["Specificity must decrease", "Fewer false positives usually mean greater specificity."], ["Both denominators change automatically", "Disease status is fixed by the reference diagnoses in this study."]), correct: "B", hint: "Think about people whose marker lies between the old and new cut-offs.", lesson: "Choosing a threshold changes the balance of missed cases and false alarms. Inspect sensitivity and specificity together; predictive values also depend on the setting.", explanation: "Values between the two cut-offs change from positive to negative. This can lower sensitivity and raise specificity; if nobody falls between the cut-offs the classifications stay unchanged.", help: "clinical_epidemiology/diagnostic.htm", operation: "MiscDiagnostic", inspiration: "Public MRCP-style diagnostic threshold examples; original scenario and options." },
    { id: "PG-LR-01", version: 1, track: "medicine", topic: "Pre-test and post-test probability", objective: "Update odds with a likelihood ratio.", stem: "For a fictional test, the positive likelihood ratio is 6. Before testing, the probability of the condition is 10%. What is the approximate probability after a positive result, assuming the likelihood ratio applies in this setting?", options: options(["6%", "The likelihood ratio is a multiplier of odds, not a probability."], ["16%", "Adding a likelihood ratio to a probability is not valid."], ["40%", "Prior odds 1/9 become 6/9; probability is (6/9)/(1+6/9) = 0.4."], ["60%", "Multiply odds, rather than multiplying the probability by 6."], ["100%", "A positive test does not guarantee the condition."]), correct: "C", hint: "First convert the 10% probability to odds p/(1\u2212p).", lesson: "Likelihood ratios update odds. Convert back to a probability after multiplication.", explanation: "Pre-test odds = 0.1/0.9 = 1/9. Post-test odds = 6/9 = 2/3. Post-test probability = (2/3)/(1+2/3) = 0.4, or 40%.", help: "clinical_epidemiology/diagnostic.htm", operation: "MiscDiagnostic", inspiration: "Public MRCP-style diagnostic evidence teaching; independently constructed numerical question." },
    { id: "PG-FOREST-01", version: 1, track: "medicine", topic: "Interpreting effect estimates", objective: "Distinguish effect size from statistical evidence.", stem: "Two fictional studies estimate risk ratios. Study A: 0.40 (95% CI 0.10\u20131.60). Study B: 0.85 (95% CI 0.80\u20130.91). Assuming valid corresponding two-sided tests, which interpretation is best?", options: options(["Study A has stronger evidence solely because its ratio is further from 1", "Effect magnitude alone does not measure statistical evidence."], ["Study B excludes no effect at the 5% level, while Study A does not", "Study B\u2019s interval excludes 1; Study A\u2019s includes it."], ["Study A proves there is no benefit", "Its wide interval includes both substantial benefit and harm."], ["Study B necessarily has the more important clinical benefit", "Clinical importance needs context and absolute risks."], ["Both intervals exclude no effect", "Study A includes the null ratio of 1."]), correct: "B", hint: "Inspect whether each confidence interval includes the null ratio of 1.", lesson: "Read the point estimate and interval together. A large but imprecise estimate does not automatically provide stronger evidence than a smaller, precise one.", explanation: "Only Study B\u2019s interval excludes 1. This does not settle clinical importance, bias, comparability or a direct difference between the two studies.", help: "basics/confidence_interval.htm", operation: null, inspiration: "RCGP November 2025 data-interpretation samples, especially Q41; new example separating magnitude from evidence." },
    { id: "AN-RATE-01", version: 1, track: "analyst", topic: "Rates versus counts", objective: "Avoid inferring absolute totals from a rate alone.", stem: "A chart shows Clinic A with 24 referrals per 1,000 registered patients and Clinic B with 18 per 1,000 during the same quarter. Their registered populations are not supplied. Which conclusion is justified by these values alone?", options: options(["Clinic A made more referrals in total", "The population denominators are unknown."], ["Clinic B has fewer registered patients", "The rates do not reveal population sizes."], ["Clinic A has the higher referral rate", "24 per 1,000 exceeds 18 per 1,000."], ["Clinic A\u2019s referrals were less appropriate", "No appropriateness data are supplied."], ["Clinic B provides better care", "A rate alone does not establish quality."]), correct: "C", hint: "What does \u201Cper 1,000\u201D tell you, and what does it leave unknown?", lesson: "Read the axis units and distinguish counts from rates. Rates support comparison but do not by themselves explain quality or total workload.", explanation: "Only the rate comparison follows. Total referrals also depend on population size; appropriateness and quality require additional evidence.", help: "rates/incidence_and_prevalence.htm", operation: null, inspiration: "RCGP November 2025 Q3 and Q20: interpretation of plotted rates; original referral scenario." },
    { id: "PH-CASEMIX-01", version: 1, track: "publicHealth", topic: "Case mix and service comparisons", objective: "Identify what is needed before attributing a difference to performance.", stem: "A rehabilitation unit has a higher average length of stay than another unit. It also receives more people with complex disability and has longer waits for supported housing. Which is the most defensible next step?", options: options(["Conclude that its clinical team is inefficient", "The crude average mixes performance with patient needs and discharge circumstances."], ["Delete every stay longer than the median", "Arbitrary exclusion loses relevant information and may bias the comparison."], ["Examine the distribution, case mix and discharge pathways before judging performance", "All can explain differences in the crude mean."], ["Compare only the two largest stays", "Extremes alone cannot characterise the services."], ["Ignore all service comparisons", "Careful comparisons can be useful."]), correct: "C", hint: "What factors beyond treatment quality influence how long someone stays?", lesson: "Combine descriptive statistics with service context. Investigate skew, recording conventions, patient needs and discharge support.", explanation: "Distribution, case mix and the wider care pathway matter. Adjusted comparisons still require appropriate data and assumptions; a crude mean alone cannot attribute causation.", help: "basic_descriptive_statistics/univariate_summary.htm", operation: "UnivariateSummary", inspiration: "FPH DFPH Specimen Paper B Q1: interpretation and case mix; new setting and single-best-answer format." },
    { id: "RS-LEAD-01", version: 1, track: "researcher", topic: "Screening and lead-time bias", objective: "Distinguish earlier diagnosis from longer life.", stem: "A fictional screening programme diagnoses a disease two years earlier, but people die at the same age they would have without screening. Measured survival from diagnosis rises. What explains this rise?", options: options(["A demonstrated reduction in mortality", "Death timing has not changed."], ["Lead-time bias", "Earlier diagnosis starts the survival clock sooner without postponing death."], ["Randomisation", "The scenario does not describe random allocation."], ["A guaranteed treatment benefit", "Longer measured survival alone does not establish benefit."], ["A fall in disease incidence", "No such change is stated."]), correct: "B", hint: "Which event starts the survival clock?", lesson: "Screening evaluation needs outcomes that distinguish earlier detection from improved health. Consider harms and appropriate comparisons.", explanation: "Lead-time bias extends observed time from diagnosis to death when diagnosis happens earlier but death does not. Mortality and other patient-relevant outcomes are needed to assess benefit.", help: "basics/bias.htm", operation: null, inspiration: "FPH critical-appraisal and screening specimens: original bias question." }
  );
  questions.push(
    { id: "CORE-DESIGN-01", version: 1, track: "core", topic: "Study design and denominators", objective: "Recognise outcome-based sampling in a case-control study.", stem: "Researchers select 120 people with a disease and 240 without it, then compare previous exposure. Which statement best describes what can be estimated directly from this sampling design?", options: options(["The population incidence, using 120/360", "The numbers with and without disease were selected by design."], ["An exposure odds ratio, with suitable control selection and assumptions", "Case-control sampling can estimate an odds ratio; it does not directly give population risk from these group sizes."], ["The population prevalence, using 120/360", "The investigator fixed the case-control ratio."], ["The causal risk difference with no further assumptions", "Causal interpretation needs design and confounding assumptions."], ["The number needed to treat from case counts alone", "Absolute treatment risks are not supplied."]), correct: "B", hint: "Were participants sampled before or after their outcome status was known?", lesson: "Study design determines which denominators and measures have meaning. Recognise case-control, cohort and experimental designs before choosing a statistic.", explanation: "The investigator chooses cases and controls, so their proportion in the sample is not population incidence or prevalence. With appropriate controls, the odds ratio can estimate an association; its causal interpretation requires additional assumptions.", help: "clinical_epidemiology/risk_retrospective.htm", operation: "MiscRetroRisk" },
    { id: "CORE-RATE-01", version: 1, track: "core", topic: "Incidence rate and person-time", objective: "Distinguish an incidence rate from a cumulative risk.", stem: "A fictional cohort contributes 600 person-years while participants are at risk, with 12 new events. What is the incidence rate?", options: options(["2 events per 100 person-years", "12/600 = 0.02 events per person-year."], ["2% of participants, regardless of follow-up", "Person-time is not a count of participants."], ["12% per participant", "The participant denominator is not given."], ["50 events per person-year", "This inverts the rate."], ["600 events per year", "600 is follow-up time, not event count."]), correct: "A", hint: "Divide events by total time at risk, then state the units.", lesson: "A rate uses person-time. A risk uses people initially at risk over a specified period, with appropriate treatment of incomplete follow-up.", explanation: "12/600 = 0.02 events per person-year, or 2 per 100 person-years. This cannot automatically be read as a two-percent one-year risk.", help: "rates/incidence_and_prevalence.htm", operation: null },
    { id: "CORE-MEDIATOR-01", version: 1, track: "core", topic: "Confounders and mediators", objective: "Match adjustment to the causal effect of interest.", stem: "A randomised exercise intervention can affect blood pressure partly by changing body weight. To estimate the total intervention effect on blood pressure, why might routinely adjusting for weight measured after the intervention be inappropriate?", options: options(["Post-intervention weight is necessarily a baseline confounder", "It is measured after treatment and may be affected by it."], ["It can block part of the pathway through which the intervention acts", "That pathway contributes to the total effect."], ["Adjustment always increases bias in every analysis", "Appropriate adjustment depends on the target effect and causal structure."], ["Randomisation proves that weight is irrelevant", "Weight may still mediate treatment effects."], ["A smaller P value decides which variables to adjust for", "Variable choice should follow the causal question and assumptions."]), correct: "B", hint: "Distinguish a variable that precedes treatment from one affected by treatment.", lesson: "For a total effect, mediators are part of the causal pathway. Direct effects ask a different question and require additional assumptions.", explanation: "Adjusting for a mediator can remove part of the total effect and may introduce other bias. Define the estimand and causal structure before deciding what to adjust for.", help: "basics/confounding.htm", operation: null },
    { id: "CORE-SELECTION-01", version: 1, track: "core", topic: "Selection and collider bias", objective: "Recognise bias caused by conditioning on a common consequence.", stem: "In a fictional population, exposure E and illness Y both influence whether someone attends a specialist clinic. A study includes only clinic attendees. Even if E and Y were otherwise unrelated, what problem could this selection create?", options: options(["It guarantees a representative population sample", "Attendance selects people through both variables."], ["It may create an association by conditioning on a common consequence", "Attendance can act as a collider between E and Y."], ["It eliminates confounding automatically", "Selection does not guarantee comparability."], ["It proves E causes Y", "The selection process can create a non-causal association."], ["It can only reduce random error", "It can introduce systematic bias."]), correct: "B", hint: "Consider the arrows E \u2192 attendance \u2190 Y.", lesson: "Conditioning on a common consequence can open a non-causal association. Eligibility, recruitment, follow-up and analysis restrictions can all matter.", explanation: "Selecting on clinic attendance conditions on a potential collider, creating an association between its causes. The direction and magnitude depend on the data-generating process.", help: "basics/bias.htm", operation: null }
  );

  // Learn/quiz.mjs
  function createSession(track, mode, id = crypto.randomUUID()) {
    if (!tracks[track] || !["learn", "test"].includes(mode)) throw new Error("Choose a valid learning path and mode.");
    return {
      id,
      track,
      mode,
      bankVersion,
      startedAt: (/* @__PURE__ */ new Date()).toISOString(),
      completedAt: null,
      questionIds: questions.filter((q) => q.track === track || q.track === "core").map((q) => q.id),
      questionSnapshots: structuredClone(questions.filter((q) => q.track === track || q.track === "core")),
      answers: [],
      hints: [],
      explanations: [],
      reflection: ""
    };
  }
  function recordAssistance(session, questionId, kind) {
    if (session.mode !== "learn" || session.completedAt) throw new Error("Assistance is unavailable in this test.");
    if (!session.questionIds.includes(questionId) || !["hints", "explanations"].includes(kind)) throw new Error("Invalid assistance request.");
    if (!session[kind].includes(questionId)) session[kind].push(questionId);
  }
  function recordAnswer(session, questionId, choice, confidence, reasoning = "") {
    const q = sessionQuestion(session, questionId);
    if (session.completedAt || session.questionIds[session.answers.length] !== questionId) throw new Error("This question is not awaiting an answer.");
    if (!q.options.some((o) => o.id === choice) || !["unsure", "fairly", "confident"].includes(confidence)) throw new Error("Choose an answer and your confidence.");
    session.answers.push({
      questionId,
      questionVersion: q.version,
      choice,
      confidence,
      reasoning: String(reasoning).slice(0, 1500),
      correct: choice === q.correct,
      answeredAt: (/* @__PURE__ */ new Date()).toISOString(),
      assisted: session.hints.includes(questionId) || session.explanations.includes(questionId)
    });
    if (session.answers.length === session.questionIds.length) session.completedAt = (/* @__PURE__ */ new Date()).toISOString();
  }
  function learnerResult(session) {
    if (!session.completedAt) throw new Error("Finish the session to see the result.");
    const score = session.answers.filter((a) => a.correct).length;
    const revisit = session.answers.filter((a) => !a.correct || a.confidence === "unsure" || a.assisted);
    return {
      score,
      total: session.questionIds.length,
      assisted: session.answers.filter((a) => a.assisted).length,
      revisit: revisit.map((a) => {
        const q = sessionQuestion(session, a.questionId);
        return {
          topic: q.topic,
          objective: q.objective,
          help: q.help,
          reason: !a.correct ? a.confidence === "confident" ? "Confident but incorrect" : "Incorrect answer" : a.assisted ? "Answered with teaching support" : "Correct, but uncertain"
        };
      })
    };
  }
  function sessionQuestion(session, id) {
    return session.questionSnapshots?.find((q) => q.id === id) ?? questions.find((q) => q.id === id);
  }

  // Learn/portfolio.mjs
  var stages = { menus: "Start with menus", bridge: "Connect menus to R", coding: "Practise R coding" };
  function newPortfolio() {
    return { schemaVersion: 2, id: crypto.randomUUID(), startedAt: (/* @__PURE__ */ new Date()).toISOString(), profile: "foundation", stage: "menus", lesson: "epidemiology", view: "study", identity: { name: "", email: "", goal: "" }, learning: { needs: "", qualifications: "", priorKnowledge: "", targetDate: "", focus: ["epidemiology", "causal"], style: "Worked examples and questions" }, conversation: [], activities: [], attempts: [], quiz: null, reflection: "", draft: "" };
  }
  function restorePortfolio(value) {
    const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
    const strings = (v, keys) => object(v) && keys.every((k) => typeof v[k] === "string");
    const validQuestion = (q) => strings(q, ["id", "topic", "stem", "correct", "explanation", "hint", "lesson", "help"]) && Array.isArray(q.options) && q.options.length === 5 && q.options.every((o) => strings(o, ["id", "text", "feedback"])) && q.options.filter((o) => o.id === q.correct).length === 1;
    const validSession = (s) => {
      if (!strings(s, ["id", "track", "mode", "startedAt"]) || !tracks[s.track] || !["learn", "test"].includes(s.mode) || !Array.isArray(s.questionIds) || !s.questionIds.length || new Set(s.questionIds).size !== s.questionIds.length || !Array.isArray(s.answers) || s.answers.length > s.questionIds.length || !["hints", "explanations"].every((k) => Array.isArray(s[k]) && s[k].every((id) => s.questionIds.includes(id)))) return false;
      if (s.questionSnapshots !== void 0 && (!Array.isArray(s.questionSnapshots) || s.questionSnapshots.length !== s.questionIds.length || !s.questionSnapshots.every(validQuestion) || new Set(s.questionSnapshots.map((q) => q.id)).size !== s.questionIds.length)) return false;
      if (!s.questionIds.every((id) => typeof id === "string" && validQuestion(sessionQuestion(s, id)))) return false;
      if (!["completedAt", "endedAt"].every((k) => s[k] === void 0 || s[k] === null || typeof s[k] === "string") || Boolean(s.completedAt) !== (s.answers.length === s.questionIds.length)) return false;
      return s.answers.every((a, i) => strings(a, ["questionId", "choice", "confidence", "reasoning", "answeredAt"]) && a.questionId === s.questionIds[i] && ["unsure", "fairly", "confident"].includes(a.confidence) && typeof a.assisted === "boolean" && typeof a.correct === "boolean" && sessionQuestion(s, a.questionId).options.some((o) => o.id === a.choice) && a.correct === (a.choice === sessionQuestion(s, a.questionId).correct));
    };
    const defaults = newPortfolio();
    const learning = value?.learning === void 0 ? defaults.learning : value.learning;
    if (!strings(value, ["id", "startedAt", "profile", "stage", "lesson", "view", "reflection", "draft"]) || value.schemaVersion !== 2 || !tracks[value.profile] || !stages[value.stage] || !["study", "options", "sources", "practice", "record"].includes(value.view) || !strings(value.identity, ["name", "email", "goal"]) || !strings(learning, ["needs", "qualifications", "priorKnowledge", "targetDate", "style"]) || !Array.isArray(learning.focus) || !learning.focus.every((x) => typeof x === "string") || !Array.isArray(value.conversation) || !value.conversation.every((c) => strings(c, ["id", "at", "role", "text", "source"]) && ["user", "assistant"].includes(c.role) && ["lessonId", "lessonTitle"].every((k) => c[k] === void 0 || typeof c[k] === "string") && (c.lessonPrompt === void 0 || typeof c.lessonPrompt === "boolean") && (!c.workspaceSources || Array.isArray(c.workspaceSources) && c.workspaceSources.every((s) => typeof s === "string")) && (!c.courseSources || Array.isArray(c.courseSources) && c.courseSources.every((s) => strings(s, ["id", "title"])))) || !Array.isArray(value.attempts) || !value.attempts.every(validSession) || value.quiz !== null && !validSession(value.quiz) || !Array.isArray(value.activities) || !value.activities.every((a) => strings(a, ["at", "text"]))) throw new Error("The saved learning record is incompatible. It has not been overwritten.");
    return { ...defaults, ...value, learning: { ...learning, focus: [.../* @__PURE__ */ new Set(["epidemiology", "causal", ...learning.focus])] } };
  }
  function transcriptEntry(state2, role, text, source = "study guide", details = {}) {
    const entry = { id: crypto.randomUUID(), at: (/* @__PURE__ */ new Date()).toISOString(), role, text, source, ...details };
    state2.conversation.push(entry);
    return entry;
  }
  function reviewRecord(state2) {
    const attempts = [...state2.attempts, ...state2.quiz ? [state2.quiz] : []].map((session) => ({
      ...structuredClone(session),
      answers: session.answers.map((a) => {
        const copy = structuredClone(a);
        if (session.mode === "test" && !session.completedAt && !session.endedAt) delete copy.correct;
        return copy;
      }),
      result: session.completedAt ? learnerResult(session) : null,
      questionSnapshots: session.questionIds.map((id) => {
        const q = structuredClone(sessionQuestion(session, id));
        if (session.mode === "test" && !session.completedAt && !session.endedAt) {
          delete q.correct;
          delete q.explanation;
          delete q.hint;
          delete q.lesson;
          q.options = q.options.map(({ id: id2, text }) => ({ id: id2, text }));
        }
        return q;
      }),
      status: session.completedAt ? "completed" : session.endedAt ? "ended early" : "in progress"
    }));
    return {
      schemaVersion: 2,
      exportedAt: (/* @__PURE__ */ new Date()).toISOString(),
      portfolioID: state2.id,
      startedAt: state2.startedAt,
      learner: structuredClone(state2.identity),
      learningOptions: structuredClone(state2.learning),
      pathway: tracks[state2.profile].title,
      rExperience: stages[state2.stage],
      bankVersion,
      questionSource: "Original StatsDirect teaching drafts; subject-expert review pending. Not official examination questions.",
      marking: "Provisional fixed-key MCQ scoring: 1 correct, 0 otherwise. First answers retained. Confidence and free-text reasoning are not graded. Independent practice is unsupervised and cannot certify exam readiness.",
      reviewStatus: "Not independently reviewed. No accreditation or CPD points awarded. Email preparation does not confirm delivery or acceptance.",
      attempts,
      conversation: structuredClone(state2.conversation),
      activities: structuredClone(state2.activities),
      reflection: state2.reflection
    };
  }
  function reviewText(record) {
    const lines = ["STATSDIRECT \u2014 LEARNING RECORD", "External review request", `Prepared: ${record.exportedAt}`, `Record: ${record.portfolioID}`, `Started: ${record.startedAt}`, "", `Learner: ${record.learner.name || "(not supplied)"}`, `Reply email: ${record.learner.email || "(not supplied)"}`, `Learning goal: ${record.learner.goal || "(not supplied)"}`, `Pathway: ${record.pathway}`, `R experience: ${record.rExperience}`, `Exams / qualifications: ${record.learningOptions?.qualifications || "(not supplied)"}`, `Learning needs: ${record.learningOptions?.needs || "(not supplied)"}`, `Prior knowledge: ${record.learningOptions?.priorKnowledge || "(not supplied)"}`, `Target date: ${record.learningOptions?.targetDate || "(not supplied)"}`, `Focus: ${(record.learningOptions?.focus || []).join(", ")}`, `Preferred teaching style: ${record.learningOptions?.style || ""}`, "", record.questionSource, record.marking, record.reviewStatus, "", "PRACTICE ATTEMPTS"];
    for (const a of record.attempts) {
      lines.push("", `${tracks[a.track].title} \u2014 ${a.mode === "test" ? "Independent practice (unsupervised)" : "Supported practice"} \u2014 ${a.status}`, `Started: ${a.startedAt} | Completed: ${a.completedAt || "not completed"}`, a.result ? `Provisional score: ${a.result.score}/${a.result.total}; ${a.result.assisted} answers flagged as assisted` : `Answered: ${a.answers.length}/${a.questionIds.length}`);
      for (const q of a.questionSnapshots) {
        const answer = a.answers.find((x) => x.questionId === q.id);
        lines.push("", `${q.id} v${q.version} \u2014 ${q.topic}`, q.stem, ...q.options.map((o) => `${o.id}. ${o.text}`), `First answer: ${answer?.choice || "not answered"} | Key: ${q.correct || "withheld until the attempt ends"}`, `Confidence: ${answer?.confidence || "not recorded"} | Assisted: ${answer?.assisted ?? false}`, `Reasoning: ${answer?.reasoning || "(none)"}`, `Feedback: ${q.explanation || "withheld until the attempt ends"}`, `Help: https://www.statsdirect.com/help/${q.help}`);
      }
    }
    lines.push("", "COMPLETE LEARNING CONVERSATION");
    for (const c of record.conversation) lines.push("", `[${c.at}] ${c.role === "user" ? "Learner" : "Tutor"} \u2014 ${c.source}${c.lessonTitle ? " \xB7 " + c.lessonTitle : ""}${c.model ? " / " + c.model : ""}`, c.text, ...(c.courseSources ?? []).map((s) => "Course reference: " + s.id + " \u2014 " + s.title), ...(c.workspaceSources ?? []).map((s) => "StatsDirect context: " + s));
    lines.push("", "LEARNING ACTIVITIES");
    for (const a of record.activities) lines.push(`[${a.at}] ${a.text}`);
    lines.push("", "LEARNER REFLECTION", record.reflection || "(not supplied)");
    return lines.join("\n");
  }
  function practiceContext(state2) {
    const q = state2.quiz;
    if (!q || q.mode === "test" && !q.completedAt) return "";
    const item = sessionQuestion(q, q.questionIds[Math.min(q.answers.length, q.questionIds.length - 1)]);
    return item ? `${item.stem}
${item.options.map((x) => x.id + ". " + x.text).join("\n")}
Teaching rationale: ${item.explanation}` : "";
  }

  // Learn/exam-sources.mjs
  var examSources = [
    { title: "MRCP(UK): official Part 1 sample examination", url: "https://www.thefederation.uk/examinations/part-1/part-1-sample-questions", note: "Official best-of-five practice access. Registration is required; the questions behind that step were not reviewed for this build." },
    { title: "MRCP-style diagnostic questions: published practice examples", url: "https://www.pastpaperhero.com/resources/rcp-mrcp-statistics-epidemiology-and-evidence-based-medicine-sensitivity-specificity-and-predictive-values?content=article", note: "Independent publisher, not a Royal College source. Public questions cover diagnostic denominators, prevalence and threshold changes. Used for topic inspiration only." },
    { title: "MRCGP AKT: official sample questions and answers", url: "https://www.rcgp.org.uk/getmedia/dca96621-2599-4e6e-9a99-7a1ab2affff9/AKT-Example-Questions-(with-answers)-November-2025.pdf", note: "November 2025 samples include chart interpretation, event risk and uncertainty (questions 3, 10, 20, 24 and 41). The app uses new fictional examples." },
    { title: "DFPH: official specimen papers and marking schemes", url: "https://www.fph.org.uk/training-careers/the-diplomate-dfph-and-final-membership-examination-mfph/the-diplomate-examination-dfph/the-diplomate-examination-dfph-preparation/", note: "Written interpretation and critical appraisal are important. The published Paper B includes interpretation of length of stay and case mix. These are not MCQ papers." },
    { title: "MFPH: final membership assessment", url: "https://www.fph.org.uk/training-careers/the-diplomate-dfph-and-final-membership-examination-mfph/the-faculty-of-public-health-final-membership-examination/marking-results-and-feedback/", note: "Final membership assesses practical competencies across six stations. Use the conversational explanation exercise below alongside MCQ practice." }
  ];
  var communicationPrompt = "Practise a short public-health communication scenario with me. You are a fictional service manager asking whether a clinic with longer average waiting times is performing poorly. Give me a small original data example, ask me to explain it in plain language, and wait for my reply. Then give formative feedback on interpretation, case mix, uncertainty and clarity. Do not assign an official examination grade.";

  // Learn/lesson-context.mjs
  function labelStudyGuides(state2, lessons) {
    for (const entry of state2.conversation) {
      if (entry.source !== "Study guide" || entry.role !== "assistant") continue;
      const origin = lessons.find((l) => l.challenge === entry.text || (l.previousChallenges ?? []).includes(entry.text));
      if (origin) {
        entry.lessonId = origin.id;
        entry.lessonTitle = origin.title;
        entry.lessonPrompt = true;
      }
    }
  }
  function ensureLessonPrompt(state2, lessons) {
    labelStudyGuides(state2, lessons);
    const current = lessons.find((l) => l.id === state2.lesson);
    if (!current) return false;
    const latest = state2.conversation.findLast((c) => c.lessonPrompt === true);
    if (latest?.lessonId === current.id && latest.text === current.challenge) return false;
    transcriptEntry(state2, "assistant", current.challenge, "Study guide", { lessonId: current.id, lessonTitle: current.title, lessonPrompt: true });
    return true;
  }
  function guidePresentation(entry, currentLesson) {
    if (entry.lessonPrompt !== true) return { label: entry.lessonTitle ? `${entry.source} \xB7 ${entry.lessonTitle}` : entry.source, earlier: false };
    const earlier = entry.lessonId !== currentLesson.id || entry.text !== currentLesson.challenge;
    return { label: `${earlier ? "Earlier study guide" : "Study guide"} \xB7 ${entry.lessonTitle}`, earlier };
  }
  function conversationForTutor(state2) {
    return state2.conversation.slice(-40).map((c) => ({ role: c.role, text: c.lessonTitle ? `[Lesson context: ${c.lessonTitle}]
${c.text}` : c.text }));
  }

  // Content/Learn/lessons.json
  var lessons_default = [
    {
      id: "epidemiology",
      title: "Epidemiological foundations",
      topic: "People, populations and study design",
      objective: "Define the population, outcome, denominator and time period before choosing an analysis.",
      summary: "Begin with who is being studied, how they were selected, what counts as an outcome and when it is measured. Distinguish prevalence from incidence, risk from rates, and descriptive comparisons from causal questions. A cohort, case-control study and randomised trial answer different questions and have different sources of bias.",
      challenge: "A clinic sees twice as many new diagnoses this year. Which population, testing and time-period information would you need before concluding that disease risk has doubled?",
      steps: "A fictional one-year cohort has 30 events among 300 exposed people and 15 among 300 unexposed people. In the risk calculation form enter the event counts and group totals using the field labels. The observed risks are 10% and 5%, with risk ratio 2. This observational comparison alone does not establish an exposure effect.",
      operation: "MiscRelRisk",
      help: "clinical_epidemiology/risk_prospective.htm",
      columns: [],
      r: '# Fictional one-year cohort. Risks need people initially at risk and a time horizon.\nevents <- c(30,15); at_risk <- c(300,300)\nprint(data.frame(Group=c("Exposed","Unexposed"),Events=events,At_risk=at_risk,Risk=events/at_risk))\nprint(c(risk_ratio=(30/300)/(15/300),risk_difference=30/300-15/300))\nbarplot(events/at_risk,names.arg=c("Exposed","Unexposed"),ylim=c(0,0.15),ylab="One-year risk",main="Observed association, not a causal estimate")\n# If follow-up durations differ, examine person-time and censoring; do not label these risks incidence rates.\n'
    },
    {
      id: "causal",
      title: "From association to causal questions",
      topic: "Causal inference basics",
      objective: "Recognise confounding and define the assumptions behind a causal comparison.",
      summary: "Ask what would happen to the same target population under two well-defined alternatives. Because both outcomes cannot be observed for one person at the same time, we need a defensible comparison. Study design and causal knowledge matter: adjustment is not a substitute for knowing which variables precede exposure, mediate effects or create selection bias.",
      challenge: "Age can affect both treatment choice and outcome. Why might adjusting for age help, while adjusting for a consequence of treatment change the effect we are trying to estimate?",
      steps: "Fictional data illustrate confounding. Exposed: 44 events among 200 people; unexposed: 26 among 200. Within the younger group the risks are 4/40 and 16/160; within the older group they are 40/160 and 10/40. Open the risk calculation to explore the crude counts; Explore in R shows the stratum-specific comparisons. The crude difference arises from age imbalance in this constructed example.",
      operation: "MiscRelRisk",
      help: "basics/confounding.htm",
      columns: [],
      r: '# Fictional age-confounding example. Counts are constructed for teaching.\ndata <- data.frame(Age=c("Younger","Older"),Exposed_events=c(4,40),Exposed_total=c(40,160),Unexposed_events=c(16,10),Unexposed_total=c(160,40))\ndata$Exposed_risk <- data$Exposed_events/data$Exposed_total\ndata$Unexposed_risk <- data$Unexposed_events/data$Unexposed_total\nprint(data)\nprint(c(crude_RR=(44/200)/(26/200)))\nprint(data.frame(Age=data$Age,Within_age_RR=data$Exposed_risk/data$Unexposed_risk))\nbarplot(rbind(data$Exposed_risk,data$Unexposed_risk),beside=TRUE,names.arg=data$Age,legend.text=c("Exposed","Unexposed"),ylab="Observed risk",main="Same within-age risks; different age mix")\n# Within-stratum agreement is not proof that every source of bias has been removed.\n'
    },
    {
      id: "paired",
      title: "Comparing paired measurements",
      topic: "Change within a person",
      objective: "Recognise pairing, analyse differences and interpret a confidence interval.",
      summary: "Paired measurements come from the same people measured twice, or from explicitly matched pairs. Analyse the within-pair differences. Measuring different, unmatched patients before and after does not create pairing just because they attend the same clinic. For a paired t test, assess the distribution of the differences.",
      challenge: "The same eight people have a measurement taken before and after an intervention, with each person's two values on the same row. Why are these paired observations? How would the analysis change if different people were measured in the two periods?",
      steps: "Choose Analysis \u2192 Parametric Methods \u2192 Paired Student t test. This example selects Before and After. Use the displayed difference direction consistently. Interpret the estimated difference and 95% confidence interval before the P value. The worksheet contains eight fictional participants.",
      operation: "TPaired",
      help: "parametric_methods/paired_t.htm",
      columns: [
        {
          title: "Before",
          values: [
            142,
            136,
            151,
            145,
            139,
            148,
            132,
            155
          ]
        },
        {
          title: "After",
          values: [
            135,
            134,
            143,
            141,
            136,
            140,
            130,
            147
          ]
        }
      ],
      r: '# Fictional paired measurements: same eight people, same row order.\nbefore <- c(142,136,151,145,139,148,132,155)\nafter <- c(135,134,143,141,136,140,130,147)\ndata <- data.frame(Before=before, After=after)\nprint(data)\n# StatsDirect uses first minus second for this selection.\nchange <- before - after\nprint(t.test(before, after, paired=TRUE, conf.level=0.95))\nplot(before, after, pch=19, xlab="Before", ylab="After", main="Fictional paired measurements")\nabline(0,1,lty=2)\n# Try: change one after value, rerun, and explain the change in the interval.\n',
      previousChallenges: [
        "If the average measurement falls after an intervention, what else would you need before claiming the intervention caused the change?"
      ]
    },
    {
      id: "precision",
      title: "Variation, precision and uncertainty",
      topic: "Describing data",
      objective: "Separate standard deviation from standard error and confidence intervals.",
      summary: "Standard deviation describes differences between observations. Standard error describes the precision of an estimated mean. A 95% confidence interval is produced by a method that covers the population value in 95% of repeated samples under its assumptions.",
      challenge: "Why would collecting four times as many independent observations halve the standard error but not necessarily change the standard deviation?",
      steps: "Open the descriptive summary for the fictional waiting times. Compare the mean, median, standard deviation and confidence interval. Investigate the long wait before deciding which summary best answers your service question.",
      operation: "UnivariateSummary",
      help: "basic_descriptive_statistics/univariate_summary.htm",
      columns: [
        {
          title: "Waiting time (minutes)",
          values: [
            12,
            15,
            14,
            18,
            21,
            16,
            19,
            13,
            45,
            17,
            20,
            22
          ]
        }
      ],
      r: '# Fictional clinic waits; no patient data.\nwait <- c(12,15,14,18,21,16,19,13,45,17,20,22)\nprint(data.frame(Waiting_minutes=wait))\nprint(c(mean=mean(wait), median=median(wait), SD=sd(wait), SE=sd(wait)/sqrt(length(wait))))\nprint(t.test(wait, conf.level=0.95)$conf.int)\nhist(wait, breaks=8, main="Fictional clinic waiting times", xlab="Minutes")\n# Try: explain why mean and median differ; inspect the outlier without silently deleting it.\n'
    },
    {
      id: "diagnostic",
      title: "Interpreting a diagnostic test",
      topic: "Sensitivity and predictive value",
      objective: "Choose the right denominator for sensitivity, specificity and predictive value.",
      summary: "Sensitivity starts with people who have the condition. Positive predictive value starts with people whose test is positive. Keeping these denominators distinct is central to interpreting diagnostic evidence.",
      challenge: "If the condition becomes rarer while sensitivity and specificity stay the same, what happens to the proportion of positive results that are false positives?",
      steps: "In the diagnostic test form enter true positives 72, false negatives 18, false positives 81 and true negatives 729, using the field labels. These fictional counts give sensitivity 80%, specificity 90% and positive predictive value about 47.1%.",
      operation: "MiscDiagnostic",
      help: "clinical_epidemiology/diagnostic.htm",
      columns: [],
      r: '# Fictional diagnostic study. Rows: test result; columns: disease status.\ntp <- 72; fn <- 18; fp <- 81; tn <- 729\ncounts <- matrix(c(tp,fp,fn,tn),nrow=2,byrow=TRUE,dimnames=list(Test=c("Positive","Negative"),Disease=c("Present","Absent")))\nprint(counts)\nprint(c(sensitivity=tp/(tp+fn), specificity=tn/(tn+fp), PPV=tp/(tp+fp), NPV=tn/(tn+fn)))\nprint(binom.test(tp,tp+fn,conf.level=0.95)$conf.int)\nbarplot(counts, beside=TRUE, legend.text=TRUE, main="Fictional diagnostic counts", ylab="People")\n'
    },
    {
      id: "risk",
      title: "Absolute and relative benefit",
      topic: "Risk, treatment effects and NNT",
      objective: "Interpret absolute risk reduction, relative risk and the follow-up period.",
      summary: "Relative effects do not describe absolute benefit on their own. A change from 14% to 8% is a six percentage point absolute reduction and a relative risk of about 0.57. The number needed to treat is linked to a particular outcome and follow-up period.",
      challenge: "Would the same relative risk imply the same absolute benefit in a population with a much lower baseline risk?",
      steps: "For the number-needed-to-treat form use 16 events among 200 treated participants and 28 among 200 controls, over one year. Follow the field labels for numerator and denominator. Explain the benefit and its uncertainty; the NNT point estimate rounds up to 17.",
      operation: "MiscNumberNeededToTreat",
      help: "clinical_epidemiology/nnt.htm",
      columns: [],
      r: '# Fictional randomised programme, one-year follow-up.\nevents <- c(16,28); totals <- c(200,200)\nrisk <- events/totals\nprint(data.frame(Group=c("Programme","Usual care"),Events=events,Total=totals,Risk=risk))\narr <- risk[2]-risk[1]\nprint(c(absolute_reduction=arr,relative_risk=risk[1]/risk[2],NNT=ceiling(1/arr)))\n# This base-R comparison uses its own interval method, which can differ from StatsDirect.\nprint(prop.test(events,totals,correct=FALSE,conf.level=0.95))\nbarplot(risk,names.arg=c("Programme","Usual care"),ylim=c(0,0.2),ylab="One-year event risk")\n'
    },
    {
      id: "regression",
      title: "Association is not causation",
      topic: "Regression and study design",
      objective: "Interpret a regression slope without confusing prediction with causation.",
      summary: "A fitted line describes an association under a model. It cannot establish causation by itself. Think about confounding, the sampling design, residuals and the range of data before interpreting the slope or making predictions.",
      challenge: "A service with longer appointment slots has higher satisfaction. What alternative explanations could produce this association?",
      steps: "Use the fictional service data in simple linear regression. Select Satisfaction as the dependent variable and Appointment minutes as the independent variable. Examine the scatterplot and residuals. Do not extrapolate beyond the observed range without justification.",
      operation: "SimpleLinearRegression",
      help: "regression_and_correlation/simple_linear.htm",
      columns: [
        {
          title: "Satisfaction",
          values: [
            58,
            61,
            60,
            67,
            65,
            73,
            71,
            78
          ]
        },
        {
          title: "Appointment minutes",
          values: [
            10,
            12,
            14,
            16,
            18,
            20,
            22,
            24
          ]
        }
      ],
      r: '# Fictional service-level observations, not a causal experiment.\ndata <- data.frame(Satisfaction=c(58,61,60,67,65,73,71,78),Minutes=c(10,12,14,16,18,20,22,24))\nprint(data)\nfit <- lm(Satisfaction ~ Minutes, data=data)\nprint(summary(fit))\nprint(confint(fit,level=0.95))\nplot(data$Minutes,data$Satisfaction,pch=19,xlab="Appointment minutes",ylab="Satisfaction",main="Association in fictional service data")\nabline(fit)\n# Try: plot(fitted(fit),residuals(fit)); explain a potential confounder.\n'
    }
  ];

  // Learn/app.mjs
  var $ = (id) => document.getElementById(id);
  var esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  var state = newPortfolio();
  var loaded = false;
  var settings = { configured: false, service: "", label: "Not connected" };
  var pending = null;
  var revision = 0;
  var feedback = null;
  var reviewApproved = false;
  var coursePack = null;
  var workspace = { choice: "", choices: [], label: "Open documents are available to the tutor" };
  var native = Boolean(window.webkit?.messageHandlers?.statsDirectLearn);
  var post = (body) => window.webkit?.messageHandlers?.statsDirectLearn?.postMessage(body);
  var lesson = () => lessons_default.find((x) => x.id === state.lesson) ?? lessons_default[0];
  var independent = () => state.quiz?.mode === "test" && !state.quiz.completedAt;
  var notice = (text) => {
    $("notice").textContent = text;
    $("notice").hidden = !text;
  };
  function save() {
    if (!loaded) return;
    state.updatedAt = (/* @__PURE__ */ new Date()).toISOString();
    revision++;
    reviewApproved = false;
    $("saveStatus").textContent = "Saving\u2026";
    if (native) post({ action: "save", state, revision });
    else {
      try {
        localStorage.setItem("statsdirect-learning-preview", JSON.stringify(state));
        $("saveStatus").textContent = "Saved in this browser";
      } catch {
        $("saveStatus").textContent = "Not saved \u2014 export before closing";
      }
    }
  }
  function activity(text) {
    state.activities.push({ at: (/* @__PURE__ */ new Date()).toISOString(), text });
    save();
  }
  function teachingSupport() {
    if (state.quiz?.mode === "learn" && !state.quiz.completedAt) recordAssistance(state.quiz, state.quiz.questionIds[state.quiz.answers.length], "explanations");
  }
  function welcome() {
    if (!state.conversation.length) transcriptEntry(state, "assistant", "Welcome. We can start with a clinical, service or research question, work through an example in StatsDirect, then connect each step to R when you are ready.\n\nFirst, tell me the population and question you want to understand. Are you describing what happens, predicting an outcome, or asking whether something causes it?", "Study guide");
  }
  function render() {
    document.body.classList.toggle("study-mode", state.view === "study");
    $("workspaceContext").hidden = state.view !== "study";
    $("profile").innerHTML = Object.entries(tracks).map(([id, t]) => `<option value="${id}" ${state.profile === id ? "selected" : ""}>${esc(t.title)}</option>`).join("");
    $("stage").innerHTML = Object.entries(stages).map(([id, t]) => `<option value="${id}" ${state.stage === id ? "selected" : ""}>${esc(t)}</option>`).join("");
    $("profile").disabled = Boolean(state.quiz && !state.quiz.completedAt) || Boolean(pending);
    $("stage").disabled = independent() || Boolean(pending);
    $("lessons").innerHTML = lessons_default.map((l, i) => `<button data-lesson="${l.id}" class="${state.view === "study" && state.lesson === l.id ? "current" : ""}" ${independent() || pending ? "disabled" : ""}>${i + 1}. ${esc(l.title)}</button>`).join("");
    $("practiceNav").classList.toggle("current", state.view === "practice");
    $("practiceNav").disabled = Boolean(pending);
    $("recordNav").classList.toggle("current", state.view === "record");
    $("sourcesNav").classList.toggle("current", state.view === "sources");
    $("sourcesNav").disabled = independent();
    $("practiceNav").querySelector("span").textContent = questions.length;
    $("options").disabled = independent() || Boolean(pending);
    $("settings").disabled = Boolean(pending);
    if (state.view === "options") renderOptions();
    else if (state.view === "sources") renderSources();
    else if (state.view === "practice") renderPractice();
    else if (state.view === "record") renderRecord();
    else renderStudy();
  }
  function bodyHTML(text) {
    return text.split(/```(?:[A-Za-z0-9_-]+)?\n?/).map((s, i) => i % 2 ? `<pre><code>${esc(s)}</code></pre>` : esc(s)).join("");
  }
  function renderStudy() {
    const l = lesson();
    if (ensureLessonPrompt(state, lessons_default)) save();
    $("main").innerHTML = `<section class="intro"><div class="eyebrow">${esc(l.topic)}</div><h1>${esc(l.title)}</h1></section><div class="actions"><button class="primary" data-action="example">Try in StatsDirect</button><button data-action="r">Explore in R</button><button class="link-button" data-action="help">Read help \u2197</button></div><details class="lesson-guide"><summary>Lesson guide and worked example</summary><p>${esc(l.summary)}</p><p>${esc(l.steps)}</p></details><section class="chat"><div class="chat-heading"><strong>Your biostatistics tutor</strong><span id="tutorBadge" class="badge">${esc(settings.label)}</span></div><div id="messages" class="messages" role="log" aria-label="Learning conversation"></div><div class="composer"><label for="question">Ask a question, explain your thinking, or paste a small R example</label><textarea id="question" rows="2" maxlength="4000" placeholder="For example: why do we analyse the differences?" ${pending ? "disabled" : ""}>${esc(state.draft)}</textarea><div class="composer-bottom"><small id="connectionPrivacy">${settings.configured ? "Send shares learning context, up to 40 recent messages and requested open document content with OpenAI. Choose Lessons only to exclude documents. Avoid identifiers." : "Connect your ChatGPT account to talk with the tutor here. No API key is needed. Your account\u2019s Codex access and usage allowance apply."}</small><button id="send" class="primary" ${pending ? "disabled" : ""}>${settings.configured ? "Send" : settings.signingIn ? "Finish sign-in" : "Use my ChatGPT"}</button>${pending ? '<button id="stop">Stop</button>' : ""}</div><p class="small" id="chatStatus" role="status">${pending ? "The tutor is thinking\u2026" : ""}</p></div></section><div class="suggestions"><button data-prompt="Explain this without assuming I know any statistics.">Explain simply</button><button data-prompt="Ask me one original exam-style question on this topic, then wait for my answer.">Test my understanding</button><button data-prompt="Walk me through the bundled R example line by line, and suggest one small change I can try.">Help me learn R</button></div>`;
    $("messages").innerHTML = state.conversation.map((c) => {
      const guide = guidePresentation(c, l);
      const content = `<div class="message-body">${bodyHTML(c.text)}</div>${c.workspaceSources?.length ? `<div class="small context-used">Used: ${c.workspaceSources.map(esc).join("; ")}</div>` : ""}`;
      if (guide.earlier) return `<details class="earlier-guide"><summary>${esc(guide.label)}</summary>${content}</details>`;
      return `<article class="message ${c.role === "user" ? "user" : ""}"><div class="message-label">${c.role === "user" ? "YOU" : esc(guide.label.toUpperCase())}${c.model ? " \xB7 " + esc(c.model) : ""}</div>${content}</article>`;
    }).join("");
    renderWorkspace();
    $("messages").scrollTop = $("messages").scrollHeight;
    $("question").oninput = () => {
      state.draft = $("question").value;
      save();
    };
    $("question").onkeydown = (e) => {
      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        send();
      }
    };
    $("send").onclick = () => settings.configured ? send() : configure();
    if ($("stop")) $("stop").onclick = () => {
      const id = pending;
      pending = null;
      post({ action: "cancel", id });
      render();
    };
    document.querySelectorAll("[data-action]").forEach((b) => b.onclick = () => openActivity(b.dataset.action));
    document.querySelectorAll("[data-prompt]").forEach((b) => {
      b.disabled = Boolean(pending);
      b.onclick = () => {
        state.draft = b.dataset.prompt;
        save();
        renderStudy();
        $("question").focus();
      };
    });
  }
  function renderWorkspace() {
    const element = $("workspaceContext");
    if (!element) return;
    element.innerHTML = `<label for="workspaceChoice">Tutor context</label><div class="workspace-controls"><select id="workspaceChoice" ${pending || independent() ? "disabled" : ""}><option value="">Follow my active document</option><option value="__none__">Lessons only</option>${workspace.choices.map((d) => `<option value="${esc(d.id)}">${esc(d.title)}</option>`).join("")}</select><button id="refreshWorkspace" class="link-button" ${pending ? "disabled" : ""}>Refresh</button></div><small id="workspaceLabel" role="status" title="${esc(workspace.label)}">${esc(workspace.label)}</small>`;
    $("workspaceChoice").value = workspace.choice;
    $("workspaceChoice").onchange = () => post({ action: "workspace", choice: $("workspaceChoice").value });
    $("refreshWorkspace").onclick = () => post({ action: "workspace" });
  }
  function configure() {
    if (native) post({ action: "settings" });
    else notice("Choose Use my ChatGPT in the Mac application to sign in through your browser. No API key is needed.");
  }
  function openActivity(action) {
    if (independent()) return;
    teachingSupport();
    const l = lesson();
    activity(`${action === "r" ? "Opened bundled R example" : action === "help" ? "Opened help" : "Opened StatsDirect analysis"}: ${l.title}`);
    if (native) post({ action, lesson: l.id });
    else if (action === "help") window.open("../Help/" + l.help, "_blank");
    else notice("Open this learning window in the Mac application to start the " + (action === "r" ? "R session" : "StatsDirect analysis") + ".");
  }
  function send() {
    if (pending || independent()) return;
    const text = $("question")?.value.trim() || state.draft.trim();
    if (!text) return;
    if (!settings.configured) {
      configure();
      return;
    }
    teachingSupport();
    transcriptEntry(state, "user", text, "Learner", { lessonId: lesson().id, lessonTitle: lesson().title });
    state.draft = "";
    pending = crypto.randomUUID();
    save();
    render();
    post({ action: "ask", id: pending, lesson: lesson().id, profile: tracks[state.profile].title, stage: stages[state.stage], practiceContext: practiceContext(state), learningGoals: state.learning, messages: conversationForTutor(state) });
  }
  function startQuiz(mode) {
    if (pending || state.quiz && !state.quiz.completedAt) return;
    if (state.quiz) state.attempts.push(state.quiz);
    state.quiz = createSession(state.profile, mode);
    feedback = null;
    state.view = "practice";
    activity(`Started ${mode === "test" ? "independent" : "supported"} practice for ${tracks[state.profile].title}`);
    render();
  }
  function renderPractice() {
    const qz = state.quiz;
    $("main").innerHTML = `<div class="eyebrow">PRACTICE WITH PURPOSE</div><h1>Put your understanding to work</h1><p class="subtle">${esc(tracks[state.profile].title)} \xB7 ${questions.filter((q2) => q2.track === state.profile || q2.track === "core").length} original questions in this pathway. These short practice sets do not establish exam readiness.</p>`;
    if (!qz) {
      $("main").insertAdjacentHTML("beforeend", `<section class="card"><h2>Choose how to practise</h2><p>Supported practice gives feedback after each answer. Independent practice pauses the tutor and withholds feedback until the end.</p><div class="actions"><button class="primary" id="supported">Supported practice</button><button id="independent">Independent practice</button></div><p class="small">First answers are retained. Confidence and reasoning help you reflect; they do not alter the score. Question bank: teaching drafts awaiting expert review.</p></section>`);
      $("supported").onclick = () => startQuiz("learn");
      $("independent").onclick = () => startQuiz("test");
      return;
    }
    if (qz.completedAt) {
      const r = learnerResult(qz);
      $("main").insertAdjacentHTML("beforeend", `<section class="card"><div class="eyebrow">${qz.mode === "test" ? "INDEPENDENT PRACTICE \xB7 UNSUPERVISED" : "SUPPORTED PRACTICE"}</div><p class="score">${r.score}<small> / ${r.total} \xB7 provisional score</small></p><p>${r.assisted ? `${r.assisted} answer(s) used recorded teaching support.` : "No in-app assistance was recorded for these answers."}</p><p class="small">This score has not been independently verified. Prior exposure or help outside this app cannot be ruled out.</p>${qz.answers.map((a) => {
        const q2 = sessionQuestion(qz, a.questionId);
        return `<div class="review-line"><strong>${a.correct ? "\u2713" : "\u21BB"} ${esc(q2.topic)}</strong><p>Your answer: ${a.choice} \xB7 Key: ${q2.correct} \xB7 Confidence: ${esc(a.confidence)}${a.assisted ? " \xB7 Assisted" : ""}</p><p>${esc(q2.explanation)}</p></div>`;
      }).join("")}<div class="actions"><button id="reviewResults" class="primary">Review my learning record</button><button id="morePractice">New practice attempt</button><button id="discussResults">Discuss with the tutor</button></div></section>`);
      $("reviewResults").onclick = () => navigate("record");
      $("morePractice").onclick = () => {
        state.attempts.push(state.quiz);
        state.quiz = null;
        save();
        render();
      };
      $("discussResults").onclick = () => {
        state.draft = "Help me understand these provisional practice results and plan my next study step:\n" + qz.answers.map((a) => {
          const q2 = sessionQuestion(qz, a.questionId);
          return `${q2.topic}: chose ${a.choice}; key ${q2.correct}. ${q2.explanation}`;
        }).join("\n");
        navigate("study");
      };
      return;
    }
    const q = sessionQuestion(qz, qz.questionIds[qz.answers.length]);
    $("main").insertAdjacentHTML("beforeend", `<section class="card"><div class="eyebrow">${qz.mode === "test" ? "INDEPENDENT" : "SUPPORTED"} \xB7 QUESTION ${qz.answers.length + 1} OF ${qz.questionIds.length}</div><p class="question">${esc(q.stem)}</p><form id="answerForm"><div class="options">${q.options.map((o) => `<label class="option"><input type="radio" name="answer" value="${o.id}" required><span><b>${o.id}.</b> ${esc(o.text)}</span></label>`).join("")}</div><div class="form-row"><div><label for="confidence">How confident are you?</label><select id="confidence" required><option value="">Choose confidence</option value="unsure">Unsure</option><option value="fairly">Fairly confident</option><option value="confident">Confident</option></select></div><div><label for="reasoning">Your reasoning (optional)</label><textarea id="reasoning" rows="2" maxlength="1500" placeholder="What led you to this answer?"></textarea></div></div><div class="actions"><button class="primary" type="submit">Submit first answer</button>${qz.mode === "learn" ? '<button id="hint" type="button">Give me a hint</button><button id="teach" type="button">Explain the principle</button>' : ""}</div></form><div id="hintText" class="small"></div><button id="endPractice" class="link-button">End this attempt early</button></section><div id="feedback"></div>`);
    $("answerForm").onsubmit = (e) => {
      e.preventDefault();
      const choice = new FormData(e.target).get("answer");
      const confidence = $("confidence").value;
      const reasoning = $("reasoning").value;
      try {
        recordAnswer(qz, q.id, choice, confidence, reasoning);
        activity(`Answered ${q.id}: ${choice}; confidence ${confidence}${qz.mode === "learn" ? "; " + (choice === q.correct ? "correct" : "incorrect") : ""}`);
        if (qz.mode === "learn") {
          feedback = { q, choice };
          renderFeedback();
        } else render();
      } catch (error) {
        notice(error.message);
      }
    };
    if ($("hint")) $("hint").onclick = () => {
      recordAssistance(qz, q.id, "hints");
      $("hintText").textContent = q.hint;
      activity(`Hint shown for ${q.id}`);
    };
    if ($("teach")) $("teach").onclick = () => {
      recordAssistance(qz, q.id, "explanations");
      $("hintText").textContent = q.lesson;
      activity(`Teaching principle shown for ${q.id}`);
    };
    $("endPractice").onclick = () => {
      qz.endedAt = (/* @__PURE__ */ new Date()).toISOString();
      state.attempts.push(qz);
      state.quiz = null;
      activity("Practice attempt ended before completion");
      render();
    };
  }
  function renderFeedback() {
    const { q, choice } = feedback;
    const option = q.options.find((o) => o.id === choice);
    $("answerForm").querySelectorAll("input,select,textarea,button").forEach((x) => x.disabled = true);
    $("endPractice").disabled = true;
    $("feedback").innerHTML = `<div class="feedback ${choice === q.correct ? "" : "wrong"}"><h2>${choice === q.correct ? "Correct \u2014 now explain why" : "A useful point to revisit"}</h2><p>${esc(option.feedback)}</p><p>${esc(q.explanation)}</p><button id="nextQuestion" class="primary">${state.quiz.completedAt ? "See my results" : "Next question"}</button></div>`;
    $("nextQuestion").onclick = () => {
      feedback = null;
      render();
    };
    $("feedback").scrollIntoView({ block: "nearest" });
  }
  function renderRecord() {
    const record = reviewRecord(state), text = reviewText(record);
    reviewApproved = false;
    $("main").innerHTML = `<div class="eyebrow">YOUR LEARNING PORTFOLIO</div><h1>A record you can reflect on and share</h1><p class="subtle">Your answers, explanations, confidence, learning conversation and practical activities stay together. Prepare a review request when you are ready.</p><section class="card"><h2>About you and your learning</h2><div class="form-row"><div><label for="learnerName">Name for the reviewer</label><input id="learnerName" maxlength="120" value="${esc(state.identity.name)}" autocomplete="name"></div><div><label for="learnerEmail">Reply email</label><input id="learnerEmail" type="email" maxlength="180" value="${esc(state.identity.email)}" autocomplete="email"></div></div><label for="goal">Course, professional role or learning goal</label><input id="goal" maxlength="500" value="${esc(state.identity.goal)}"><label for="reflection">Reflection and next learning step</label><textarea id="reflection" rows="3" maxlength="3000" placeholder="What did you learn, and what will you practise next?">${esc(state.reflection)}</textarea><p class="small">Identity fields are kept locally and included in your review record. They are not automatically sent to the AI tutor.</p></section><section class="card"><h2>Review before sharing</h2><p>${record.attempts.filter((a) => a.completedAt).length} completed practice attempt(s) \xB7 ${state.conversation.length} conversation entries \xB7 ${state.activities.length} practical activities</p><p class="small">Original draft questions, provisional fixed-key scoring and AI teaching need external review. These are unsupervised learning records, not certificates. Neither recipient has reviewed this record; any accreditation or CPD award is their decision.</p><details><summary>Preview the complete record to be attached</summary><pre id="recordPreview" class="record-preview">${esc(text)}</pre></details><div class="actions"><button id="exportRecord">Export learning record\u2026</button></div><label for="recipient">Ask for external review</label><select id="recipient"><option>support@statsdirect.com</option><option>chil@liverpool.ac.uk</option></select><label id="mailConsent"><input id="consent" type="checkbox"><span>I have reviewed the record and want to include the full conversation and practice answers in an email to this recipient.</span></label><div class="actions"><button id="emailRecord" class="primary" disabled>Prepare email draft\u2026</button></div><p class="small">Opens Mail with the record attached. You review and send the message. No automatic submission, University marking service or CPD award is connected.</p></section>`;
    for (const [id, key] of [["learnerName", "name"], ["learnerEmail", "email"], ["goal", "goal"]]) $(id).oninput = () => {
      state.identity[key] = $(id).value;
      save();
      updatePreview();
    };
    $("reflection").oninput = () => {
      state.reflection = $("reflection").value;
      save();
      updatePreview();
    };
    $("exportRecord").onclick = exportRecord;
    $("consent").onchange = () => {
      reviewApproved = $("consent").checked;
      $("emailRecord").disabled = !reviewApproved;
    };
    $("recipient").onchange = () => {
      reviewApproved = false;
      $("consent").checked = false;
      $("emailRecord").disabled = true;
    };
    $("emailRecord").onclick = () => {
      if (!reviewApproved) return;
      if (!$("learnerEmail").checkValidity()) {
        $("learnerEmail").reportValidity();
        return;
      }
      const recipient = $("recipient").value;
      if (native) post({ action: "email", recipient, ...exportPayload() });
      else notice("Email drafts with attachments are available in the Mac application. Export the record here and attach it yourself.");
    };
  }
  function renderOptions() {
    const o = state.learning;
    $("main").innerHTML = `<div class="eyebrow">LEARNING OPTIONS</div><h1>Make this teaching fit your needs</h1><p class="subtle">Describe where you are starting and what you want to achieve. You can change these options as your confidence grows.</p><section class="card"><h2>Your goals and qualifications</h2><label for="optionProfile">Learning pathway</label><select id="optionProfile">${Object.entries(tracks).map(([id, t]) => `<option value="${id}" ${state.profile === id ? "selected" : ""}>${esc(t.title)}</option>`).join("")}</select><label for="qualifications">Exams, courses or qualifications you are studying for</label><textarea id="qualifications" rows="2" maxlength="1200" placeholder="For example: MRCP Part 1, MRCGP AKT, DFPH/MFPH, MPH, an undergraduate module, or a professional qualification">${esc(o.qualifications)}</textarea><label for="needs">What do you need help learning?</label><textarea id="needs" rows="3" maxlength="2500" placeholder="Describe concepts you find difficult, analyses you want to understand, and what you would like to be able to do.">${esc(o.needs)}</textarea><label for="priorKnowledge">Your previous experience with statistics and epidemiology</label><textarea id="priorKnowledge" rows="2" maxlength="1500" placeholder="A starting point helps the tutor pitch explanations at the right level.">${esc(o.priorKnowledge)}</textarea><div class="form-row"><div><label for="targetDate">Target exam or completion date (optional)</label><input id="targetDate" type="date" value="${esc(o.targetDate)}"></div><div><label for="optionStage">Confidence with R</label><select id="optionStage">${Object.entries(stages).map(([id, t]) => `<option value="${id}" ${state.stage === id ? "selected" : ""}>${esc(t)}</option>`).join("")}</select></div></div></section><section class="card"><h2>A course pack from your tutor</h2><p>Import course notes, learning outcomes, worked examples and terminology. The tutor will consult relevant extracts and cite their document or page.</p><p>${coursePack ? `<strong>${esc(coursePack.title)}</strong> \xB7 ${coursePack.documents.length} document(s) or pages imported` : "No course pack is attached."}</p>${coursePack ? `<details><summary>Included materials</summary><ul>${coursePack.documents.map((d) => `<li>${esc(d.title)}</li>`).join("")}</ul></details>` : ""}<button id="importCourse">${coursePack ? "Replace course pack\u2026" : "Import course pack\u2026"}</button><p class="small">PDF, Markdown, plain text or a StatsDirect JSON pack. Notes stay on this Mac; relevant text excerpts are included when you send a question to OpenAI using your ChatGPT account. Importing does not retrain the model or turn course marking guidance into accredited assessment.</p></section><section class="card"><h2>Foundations and priorities</h2><p>Epidemiological principles and causal inference are included in every learning pathway and practice set.</p><div class="focus-grid">${[["epidemiology", "Epidemiology and study design"], ["causal", "Causal inference and bias"], ["interpretation", "Interpreting results and uncertainty"], ["methods", "Choosing and checking statistical methods"], ["r", "R coding and reproducible analysis"], ["communication", "Explaining evidence to others"]].map(([id, title]) => `<label class="option"><input type="checkbox" name="focus" value="${id}" ${o.focus.includes(id) ? "checked" : ""} ${["epidemiology", "causal"].includes(id) ? "disabled" : ""}><span>${title}</span></label>`).join("")}</div><label for="style">How would you like the tutor to help?</label><select id="style">${["Worked examples and questions", "Step-by-step explanations", "Exam-style questions with feedback", "Discuss my reasoning", "Connect StatsDirect to R"].map((t) => `<option ${o.style === t ? "selected" : ""}>${t}</option>`).join("")}</select><p class="small">These learning needs and exam goals are included with questions you send to OpenAI using your ChatGPT account. Your name and reply email in the review record are not automatically attached.</p><div class="actions"><button id="applyOptions" class="primary">Save options and return to learning</button></div><p id="optionSaved" class="small" role="status">Changes are saved on this device as you edit.</p></section>`;
    for (const id of ["qualifications", "needs", "priorKnowledge", "targetDate", "style"]) $(id).oninput = () => {
      o[id] = $(id).value;
      save();
    };
    $("optionProfile").onchange = () => {
      state.profile = $("optionProfile").value;
      save();
    };
    $("optionStage").onchange = () => {
      state.stage = $("optionStage").value;
      save();
    };
    document.querySelectorAll("[name=focus]").forEach((el) => el.onchange = () => {
      o.focus = Array.from(document.querySelectorAll("[name=focus]:checked")).map((x) => x.value);
      save();
    });
    $("importCourse").onclick = () => {
      if (native) post({ action: "importCoursePack" });
      else notice("Course pack import is available in the Mac application.");
    };
    $("applyOptions").onclick = () => {
      activity("Updated learning needs and exam/qualification goals");
      navigate("study");
    };
  }
  function renderSources() {
    $("main").innerHTML = `<div class="eyebrow">EXAMINATION EXAMPLES</div><h1>Learn from the way questions are asked</h1><p class="subtle">Published examples inform our choice of topics and question styles. Our practice questions use original wording and fictional data; they are not endorsed by the examining bodies.</p><section class="card">${examSources.map((source) => `<div class="review-line"><h2><a href="${esc(source.url)}" target="_blank" rel="noopener">${esc(source.title)} \u2197</a></h2><p>${esc(source.note)}</p></div>`).join("")}</section><section class="card"><h2>Practise explaining a result</h2><p>For public-health examinations, build the ability to discuss evidence with a colleague or member of the public as well as answering knowledge questions. The tutor can role-play a fictional service manager and give formative feedback.</p><button id="communication" class="primary">Prepare a conversation exercise</button></section>`;
    $("communication").onclick = () => {
      state.draft = communicationPrompt;
      state.lesson = "precision";
      navigate("study");
    };
  }
  function updatePreview() {
    $("recordPreview").textContent = reviewText(reviewRecord(state));
    $("consent").checked = false;
    $("emailRecord").disabled = true;
  }
  function exportPayload() {
    const record = reviewRecord(state);
    return { record, text: reviewText(record) };
  }
  function exportRecord() {
    const payload = exportPayload();
    if (native) post({ action: "export", ...payload });
    else {
      const url = URL.createObjectURL(new Blob([payload.text], { type: "text/plain" }));
      const a = document.createElement("a");
      a.href = url;
      a.download = "StatsDirect-learning-record.txt";
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1e3);
    }
  }
  function navigate(view) {
    if (independent() && ["study", "options", "sources"].includes(view)) return;
    state.view = view;
    save();
    render();
  }
  $("settings").onclick = configure;
  $("options").onclick = () => navigate("options");
  $("profile").onchange = () => {
    state.profile = $("profile").value;
    activity("Learning pathway changed to " + tracks[state.profile].title);
    render();
  };
  $("stage").onchange = () => {
    state.stage = $("stage").value;
    activity("R learning stage changed to " + stages[state.stage]);
    render();
  };
  $("lessons").onclick = (e) => {
    const button = e.target.closest("[data-lesson]");
    if (!button || button.disabled) return;
    teachingSupport();
    state.lesson = button.dataset.lesson;
    state.view = "study";
    ensureLessonPrompt(state, lessons_default);
    activity("Opened lesson: " + lesson().title);
    render();
  };
  $("sourcesNav").onclick = () => navigate("sources");
  $("practiceNav").onclick = () => navigate("practice");
  $("recordNav").onclick = () => navigate("record");
  window.statsDirectLearn = {
    restore(value) {
      try {
        loaded = false;
        state = value ? restorePortfolio(value) : newPortfolio();
        if (!lessons_default.some((l) => l.id === state.lesson)) state.lesson = "epidemiology";
        labelStudyGuides(state, lessons_default);
        if (independent()) state.view = "practice";
        welcome();
        render();
        loaded = true;
        save();
      } catch (error) {
        this.loadError(error.message);
      }
    },
    loadError(message) {
      loaded = false;
      document.body.classList.remove("study-mode");
      $("workspaceContext").hidden = true;
      $("main").innerHTML = '<h1>The learning record needs attention</h1><p id="loadError"></p>';
      $("loadError").textContent = message;
      notice("The existing record has not been overwritten.");
    },
    settings(value) {
      const wasSigningIn = settings.signingIn;
      settings = value;
      $("settings").textContent = value.configured ? "Tutor connection" : value.signingIn ? "Finish ChatGPT sign-in" : "Use my ChatGPT";
      if ($("tutorBadge")) $("tutorBadge").textContent = value.label;
      if ($("send")) $("send").textContent = value.configured ? "Send" : value.signingIn ? "Finish sign-in" : "Use my ChatGPT";
      if ($("connectionPrivacy")) $("connectionPrivacy").textContent = value.configured ? "Send shares learning context, up to 40 recent messages and requested open document content with OpenAI. Choose Lessons only to exclude documents. Avoid identifiers." : "Connect your ChatGPT account to talk with the tutor here. No API key is needed. Your account\u2019s Codex access and usage allowance apply.";
      if (wasSigningIn && !value.signingIn) notice(value.configured ? "Connected to ChatGPT. Send your question when you are ready." : value.label);
    },
    workspace(value) {
      workspace = value;
      renderWorkspace();
    },
    toolActivity(value) {
      if (value.id === pending && $("chatStatus")) $("chatStatus").textContent = value.text;
    },
    saved(value) {
      if (value === revision) $("saveStatus").textContent = "Saved on this Mac";
    },
    notice,
    reply(value) {
      if (value.id !== pending) return;
      pending = null;
      if (value.workspaceSources?.length) activity("Tutor used: " + value.workspaceSources.join("; "));
      transcriptEntry(state, "assistant", value.text, "StatsDirect AI tutor", { lessonId: lesson().id, lessonTitle: lesson().title, model: value.model, responseID: value.responseID, promptVersion: value.promptVersion, courseSources: value.courseSources ?? [], workspaceSources: value.workspaceSources ?? [] });
      save();
      render();
    },
    tutorError(value) {
      if (value.id && value.id !== pending) return;
      pending = null;
      notice(value.message);
      render();
    },
    exportRecord,
    coursePack(value) {
      coursePack = value;
      if (loaded && state.view === "options") renderOptions();
    },
    showOptions() {
      if (loaded) navigate("options");
    }
  };
  if (native) post({ action: "ready" });
  else {
    try {
      const stored = localStorage.getItem("statsdirect-learning-preview");
      window.statsDirectLearn.restore(stored ? JSON.parse(stored) : null);
    } catch (error) {
      window.statsDirectLearn.loadError(error.message);
    }
    notice("Browser preview. Use the Mac app to sign in with ChatGPT, analyses, R sessions and email drafts.");
  }
})();

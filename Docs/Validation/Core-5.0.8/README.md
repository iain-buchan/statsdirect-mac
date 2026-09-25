# Windows core comparison before Mac acceptance

25 September 2026. This audit compiles the unchanged Windows numerical source under .NET 10 on Apple Silicon, independently of the Mac application, its host adaptations and renderer. It compares the previous engine revision `c956b122c9b77683f58c4d10c221390183968cd3` (5.0.7) with `dcc2af8f0ec55d736a98acac029297510195e2df` (5.0.8) and installed R 4.6.1. No calculation routine is replaced with R code.

## Results

| Check | Windows 5.0.7 | Windows 5.0.8 |
|---|---:|---:|
| Supported comparison cases | 4,590 | 4,902 |
| Agree with R within the screening tolerance | 3,309 | 4,580 |
| Flagged differences, including faults and timeouts | 1,281 | 322 |
| Reported nonzero fault codes | 171 | 0 |
| Exceeded the two-second per-case limit | 146 | 0 |
| Ordinary seeded cases agreeing with R | 400 / 400 | 400 / 400 |

The additional 312 cases exercise 5.0.8's new direct-tail/log-probability interfaces, including infinite degrees of freedom. The core's own separate regression suite also passed all **1,552** checks, including endpoints, invalid inputs, monotonicity and explicit non-convergence handling.

All **322** candidate/R discrepancies were then checked independently using **80-decimal-digit arithmetic**, integration of the beta density in log-odds coordinates, and closed forms where applicable. Every candidate result passed the stated value, inverse-bracket or floating-point overflow criterion. Ten representative cases were repeated at 100 digits, again with no unresolved case. The integration implementation also matched six F/Cauchy closed forms within 1e-40. These checks support accepting 5.0.8; they are not a claim that every output is accurate to 80 digits or that all statistical procedures have been certified.

## Why R disagreement is not automatically a defect

- F lower-tail quantile at probability 0.001 on 1 and 1,000,000 degrees of freedom: 5.0.8 gives `1.570797934662498e-6`; R gives `1.5707971492624904e-6`. Independent 80-digit inversion gives `1.57079793466249462848e-6`. The relative errors are approximately 2.1e-15 and −5.0e-7 respectively.
- F upper-tail quantile at probability 0.025 on 100,000,000 and 100,000,000 degrees of freedom: 5.0.8 gives `1.00039206963836`; R gives `1.0002771997074424`. Independent integration at those values gives upper tails `0.0250000000000095922` and `0.0829030034471892796` respectively.
- R's direct F tail can become zero at an argument of 1e308 although the result is representable. The reciprocal-F identity supplies a stable R cross-check. Other discrepancies concern underflow, quantiles close to distribution boundaries, heavy tails and small nonzero values returned for a mathematically zero median.

The comparison therefore records R output and warnings rather than treating them as an unquestionable answer key. R issued warnings in 14 cases, preserved in the raw results. The 5.0.7 discrepancies were counted but were not all independently adjudicated; this audit must not be read as proof that every disagreement from the older engine is a core error. Timeouts are an execution bound on this machine, not a calibrated performance benchmark.

## Scope and criteria

The deterministic grid covers beta ratios/inverses, F and t tails/quantiles, chi-square tails/quantiles and gamma tails. Shapes and degrees of freedom range from 0.01 to 1e12, with selected infinite-df limits; probabilities reach 1e-300, statistics reach 1e308, and log probabilities reach −1e12. Four hundred ordinary cases use random seed 508. Both versions receive identical inputs and use their original public functions and argument conventions.

The initial comparison uses relative tolerance 2e-10 and no absolute tolerance for ordinary nonzero values; log outputs use 2e-10 times `max(1, |reference|)`. Equal infinities and NaNs are distinguished from nonzero fault codes. Independent probability checks allow at most the larger of four ULPs and the same tolerance. Inverse checks bracket the requested probability within four ULPs or relative coordinate tolerance 2e-10; beta checks scale this by the smaller coordinate. Overflow is checked against the largest finite double. This makes the acceptance rule explicit and avoids silently accepting a lost small tail as zero.

The candidate was extracted from Git into an isolated scratch directory. Source hashes and exact revisions are in [summary.json](summary.json). The harness compiles `Numerics.cs` and its new beta/special-function dependencies directly; it contains no Mac UI code and no alternative distribution algorithm. Higher-precision integration exists only in the validation tool.

## Evidence and reproduction

The compressed TSV files preserve all input cases, both Windows outputs and fault statuses, R values/warnings, the screening differences, all 322 high-precision checks and the ten 100-digit repeats. They can be read with Python's `gzip` module or any gzip-compatible tool. No learner or patient data are included.

From the Mac repository root:

```sh
python3 Tests/CoreDistributions/compare.py --dotnet /path/to/dotnet
python3 -m venv .build/reference-python
.build/reference-python/bin/python -m pip install mpmath==1.4.1
.build/reference-python/bin/python Tests/CoreDistributions/adjudicate.py .build/core-distributions
.build/reference-python/bin/python Tests/CoreDistributions/adjudicate.py .build/core-distributions --dps 100 --ids 336,377,792,1810,3121,3672,3959,4251,4299,4365 --output high-precision-100.tsv
```

The comparison script reports differences without declaring them errors. The adjudication script exits unsuccessfully if a discrepancy remains unresolved. Rscript currently uses the installed macOS R framework path. Full engine integration and Mac report tests are recorded separately in [verification](../../../Tests/verification.md).

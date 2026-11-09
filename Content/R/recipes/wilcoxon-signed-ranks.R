# StatsDirect recipe: Wilcoxon signed ranks test with its exact probabilities and limits, as the help shows it in R.
# From the help's R code (nonparametric_methods/wilcoxon_signed_ranks.htm); the data and settings above come from the run.
# data: first, second
# settings: confidence = gamma
# hand-edited: the selected confidence level and complete pairs or differences come from the run

# Wilcoxon signed ranks test: the StatsDirect help example (Conover 1999) in R
pct <- paste0(100 * confidence, "%")
if (is.null(second)) {
  d <- first[!is.na(first)]                 # one column already contains differences
} else {
  keep <- complete.cases(first, second)
  d <- first[keep] - second[keep]
}
n <- length(d)
nz <- d[d != 0]
if (!length(nz)) stop("All differences are zero; at least one non-zero difference is required.")

# The standard R test after setting zero differences aside, as StatsDirect does.
# R 4.6 or later supports exact tied ranks. The report's explicit calculation
# below also works in older R versions, which otherwise approximate tied data.
print(wilcox.test(nz, exact = length(nz) <= 200, correct = FALSE))

# Number of non-zero differences and the sum of ranks for positive differences
r <- rank(abs(nz))                        # tied values share a mid-rank
Tplus <- sum(r[nz > 0])
cat("Number of non-zero differences ranked =", length(nz), "\n")
cat("Sum of ranks for positive differences =", format(Tplus, digits = 15, scientific = FALSE), "\n")

if (length(nz) <= 200) {
  # Exact sign assignments, allowing ties: double the mid-ranks to make integers.
  p <- 1
  for (v in 2 * r) p <- (c(p, numeric(v)) + c(numeric(v), p)) / 2
  w <- 2 * Tplus + 1
  lower <- sum(p[1:w])
  upper <- sum(p[w:length(p)])
  cat("Exact probability", if (anyDuplicated(abs(nz))) " (adjusted for ties)", ":\n", sep = "")
} else {
  # The report uses this normal approximation above 200 non-zero differences,
  # with no continuity correction and with the variance of the actual ranks.
  z <- sum(sign(nz) * r) / sqrt(sum(r^2))
  lower <- pnorm(z)
  upper <- pnorm(z, lower.tail = FALSE)
  cat("Normalised statistic", if (anyDuplicated(abs(nz))) " (adjusted for ties)",
      " = ", z, "\n", sep = "")
}
cat("Lower side P =", round(lower, 4), "  Upper side P =", round(upper, 4),
    "  Two sided P =", round(min(1, 2 * min(lower, upper)), 4), "\n")

# The confidence interval uses all pairs, including zero differences. Its limits
# are the Kth smallest and largest Walsh averages (each difference is also paired
# with itself). StatsDirect uses exact K below 200 pairs and normal K from 200.
# R's qsignrank can overflow for large n, so it is not used in that branch.
alpha <- (1 - confidence) / 2
K <- if (n < 4) 0 else if (n < 200) qsignrank(alpha, n) else
  floor(n * (n + 1) / 4 + qnorm(alpha) * sqrt(n * (n + 1) * (2 * n + 1) / 24)) + 1
a <- outer(d, d, "+") / 2
a <- sort(a[upper.tri(a, diag = TRUE)])
if (length(nz) >= 4 && K > 0) {
  # Exact attained coverage is available through 1,000 pairs. Beyond that the
  # report labels the selected coverage approximate; psignrank also overflows.
  coverage <- if (n <= 1000) 1 - 2 * psignrank(K - 1, n) else confidence
  cat(sprintf("%s%.1f%% confidence interval for difference between population medians:\n",
              if (n > 1000) "Approximate " else "", 100 * coverage))
  cat(sprintf("K = %.0f%s   Median difference = %g (%g to %g)\n",
              K, if (n >= 200) " (approx)" else "", median(a), a[K], rev(a)[K]))
} else {
  reason <- if (length(nz) < 4) "fewer than four non-zero differences" else "too few pairs at this confidence level"
  cat(sprintf("Median difference = %g (interval unavailable: %s)\n", median(a), reason))
}

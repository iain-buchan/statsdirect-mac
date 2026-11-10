# StatsDirect recipe: Spearman rank correlation with its exact probabilities, as the help shows it in R.
# From the help's R code (nonparametric_methods/spearman.htm); the data and settings above come from the run.
# data: career, psychology
# settings: confidence = gamma
# hand-edited: the confidence level and the data come from the run, as the header says

# Spearman's rank correlation: the StatsDirect help example (Armitage and Berry
# 1994, p. 466) in R
keep <- complete.cases(career, psychology)
career <- career[keep]
psychology <- psychology[keep]
if (is.null(confidence) || !is.finite(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95
pct <- paste0(100 * confidence, "%")
n <- length(career)

# R's standard test uses exact probabilities through nine pairs and AS89 for
# larger untied samples (an approximation). StatsDirect extends exact evaluation
# to ten pairs; that one extra case is counted below. With ties both use t.
tied <- anyDuplicated(career) > 0 || anyDuplicated(psychology) > 0
print(cor.test(career, psychology, method = "spearman", exact = !tied))

rx <- rank(career)
ry <- rank(psychology)
rho <- cor(rx, ry)
score <- (n^3 - n) * (1 - rho) / 6
cat("Spearman's score =", score, "\n")
ci <- NULL
if (n >= 4 && 1 - abs(rho) >= 1e-12) {
  ci <- tanh(atanh(rho) + c(-1, 1) * qnorm((1 + confidence) / 2) / sqrt(n - 3))
  cat(sprintf("Rho = %.6f   %s CI = %.6f to %.6f\n", rho, pct, ci[1], ci[2]))
} else cat("Rho =", rho, "(confidence interval unavailable)\n")

if (!tied && n == 10) {
  # Exact P for ten untied pairs: count, for every way of
  # pairing the ranks, the sum of squared differences. Pairs are added one at a
  # time; a row of 'ways' is the set of ranks of y already used and a column is
  # the sum so far.
  maxsum <- n * (n^2 - 1) / 3
  ways <- matrix(0, 2^n, maxsum + 1)
  ways[1, 1] <- 1
  for (set in 0:(2^n - 2)) {
    used <- bitwAnd(set, 2^(0:(n - 1))) > 0
    i <- sum(used) + 1                      # the next rank of x to be paired
    for (j in which(!used)) {
      s <- (i - j)^2
      to <- set + 2^(j - 1) + 1
      ways[to, (s + 1):(maxsum + 1)] <- ways[to, (s + 1):(maxsum + 1)] +
        ways[set + 1, 1:(maxsum + 1 - s)]
    }
  }
  score <- round(score)
  p <- ways[2^n, ] / factorial(n)           # P(score = 0, 1, ... maxsum)
  upper <- sum(p[1:(score + 1)])            # a small score is a large rho
  lower <- sum(p[(score + 1):(maxsum + 1)]) # each side includes the observed score
} else if (!tied && n > 1290) {
  # AS89 (Best & Roberts, 1975), from StatsDirect's MIT ExFortran.prho/bigprho.
  # cor.test switches to t above 1290 to avoid a historical integer overflow.
  # Double arithmetic retains the more accurate AS89 tail for large untied data.
  as89 <- function(score, lower.tail) {
    score <- 2 * ceiling(score / 2)
    if (score <= 0) return(if (lower.tail) 0 else 1)
    if (score > n * (n^2 - 1) / 3) return(if (lower.tail) 1 else 0)
    b <- 1 / n
    x <- (6 * (score - 1) * b / (n^2 - 1) - 1) * sqrt(n - 1)
    y <- x^2
    u <- x * b * (0.2274 + b * (0.2531 + 0.1745 * b) +
      y * (-0.0758 + b * (0.1033 + 0.3932 * b) - y * b *
      (0.0879 + 0.0151 * b - y * (0.0072 - 0.0831 * b + y * b * (0.0131 - 0.00046 * y)))))
    correction <- u * exp(-y / 2)
    p <- if (lower.tail) pnorm(x) - correction else pnorm(x, lower.tail = FALSE) + correction
    max(0, min(1, p))
  }
  score <- round(score)
  upper <- as89(score + 2, TRUE)
  lower <- as89(score, FALSE)
} else {
  upper <- cor.test(career, psychology, method = "spearman", exact = !tied,
                    alternative = "greater")$p.value
  lower <- cor.test(career, psychology, method = "spearman", exact = !tied,
                    alternative = "less")$p.value
}
cat("Upper side P =", round(upper, 4), "  Lower side P =", round(lower, 4),
    "  Two sided P =", round(min(1, 2 * min(upper, lower)), 4), "\n")

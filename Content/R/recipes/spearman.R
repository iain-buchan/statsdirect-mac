# StatsDirect recipe: Spearman rank correlation with its exact probabilities, as the help shows it in R.
# From the help's R code (nonparametric_methods/spearman.htm); the data and settings above come from the run.
# data: career, psychology
# settings: confidence = gamma
# hand-edited: the confidence level and the data come from the run, as the header says

# Spearman's rank correlation: the StatsDirect help example (Armitage and Berry
# 1994, p. 466) in R
pct <- paste0(100 * confidence, "%")
n <- length(career)

# R's standard test. Its S is the sum of squared differences between the ranks,
# which StatsDirect calls Spearman's score (52). With 10 or more pairs R takes
# P from a series approximation (two sided P = 0.0351 here); with fewer it is
# exact. StatsDirect's P is exact for 10 or fewer pairs (0.0347).
# Use alternative = "greater" for the upper side P and "less" for the lower.
print(cor.test(career, psychology, method = "spearman"))

# Rho, the score and a 95% confidence interval by Fisher's z transformation
rx <- rank(career)
ry <- rank(psychology)
rho <- cor(rx, ry)
score <- sum((rx - ry)^2)
ci <- tanh(atanh(rho) + c(-1, 1) * qnorm((1 + confidence) / 2) / sqrt(n - 3))
cat("Spearman's score =", score, "\n")
cat(sprintf("Rho = %.6f   %s CI = %.6f to %.6f\n", rho, pct, ci[1], ci[2]))

# Exact P, for data without ties and up to 12 pairs: count, for every way of
# pairing the ranks, the sum of squared differences. Pairs are added one at a
# time; a row of 'ways' is the set of ranks of y already used and a column is
# the sum so far.
stopifnot(!anyDuplicated(career), !anyDuplicated(psychology), n <= 12)
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
p <- ways[2^n, ] / factorial(n)           # P(score = 0, 1, ... maxsum)
upper <- sum(p[1:(score + 1)])            # a small score is a large rho
lower <- sum(p[(score + 1):(maxsum + 1)]) # each side includes the observed score
cat("Upper side P =", round(upper, 4), "  Lower side P =", round(lower, 4),
    "  Two sided P =", round(min(1, 2 * min(upper, lower)), 4), "\n")
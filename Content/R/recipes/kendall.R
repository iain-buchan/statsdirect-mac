# StatsDirect recipe: Kendall rank correlation with its exact probabilities, as the help shows it in R.
# From the help's R code (nonparametric_methods/kendall_correlation.htm); the data and settings above come from the run.
# data: career, psychology
# settings: confidence = gamma
# hand-edited: the confidence level and the data come from the run, as the header says; ties, the exact test and the limits of tau follow the report

# Kendall's rank correlation: the StatsDirect help example (Armitage and Berry
# 1994, p. 466) in R
keep <- complete.cases(career, psychology)
career <- career[keep]
psychology <- psychology[keep]
if (is.null(confidence) || !is.finite(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95
pct <- paste0(100 * confidence, "%")
n <- length(career)
tx <- tabulate(match(career, unique(career)))          # the sizes of the groups of tied values
ty <- tabulate(match(psychology, unique(psychology)))
tied_x <- sum(tx * (tx - 1) / 2)                        # pairs tied in each variable
tied_y <- sum(ty * (ty - 1) / 2)
tied <- tied_x + tied_y                                 # as the report counts tied pairs

# R's standard test. Its T is the number of concordant pairs (34). Without ties
# and with fewer than 50 pairs its P is exact, as is StatsDirect's; with ties R
# uses the normal approximation.
# Use alternative = "greater" for the upper side P and "less" for the lower.
print(cor.test(career, psychology, method = "kendall", exact = if (tied > 0) FALSE else NULL))

# The report's exact test takes no account of ties: P(S >= k) for n observations
# without ties, from the proportions of the orderings with each number of
# discordant pairs (inserting observation j adds 0 to j - 1 of them) through
# 1,000 observations, and from its Edgeworth series in S - 1 above
kendall_upper <- function(n) {
  pairs <- n * (n - 1) / 2
  if (n > 1000) {
    sd_s <- sqrt((2 * n^3 + 3 * n^2 - 5 * n - 6) / 18)
    return(function(k) {
      x <- (k - 1) / sd_s
      h <- numeric(15); h[1] <- x; h[2] <- x^2 - 1
      for (i in 3:15) h[i] <- x * h[i - 1] - (i - 1) * h[i - 2]
      r <- 1 / n
      sc1 <- h[3] * (-0.09 + r * (0.045 + r * (-0.5325 + r * 0.506)))
      sc2 <- h[5] * (0.036735 + r * (-0.036735 + r * 0.3214)) + h[7] * (0.00405 + r * (-0.023336 + r * 0.07787))
      sc3 <- h[9] * (-0.0033061 - r * 0.0065166) + h[11] * (-0.0001215 + r * 0.0025927) +
        r * (h[13] * 0.00014878 + h[15] * 0.0000027338)
      sc <- r * (sc1 + r * (sc2 + r * sc3))
      min(1, max(0, pnorm(x, lower.tail = FALSE) + sc * 0.398942 * exp(-0.5 * x^2)))
    })
  }
  p <- 1
  for (j in seq_len(n)[-1]) {
    cs <- cumsum(c(p, numeric(j - 1)))
    next_p <- (cs - c(numeric(j), cs)[seq_along(cs)]) / j
    half <- seq_len((length(next_p) + 1) %/% 2)
    next_p[length(next_p) + 1 - half] <- next_p[half]
    p <- pmax(0, next_p)
  }
  at_most <- pmin(1, cumsum(p))                         # P(D <= d) for d = 0, 1, ... pairs
  function(k) at_most[(pairs - k) %/% 2 + 1]            # S >= k is D <= (pairs - k) / 2
}

# Concordant and discordant pairs, Kendall's score and tau (tau b with ties)
q <- sign(outer(career, career, "-")) * sign(outer(psychology, psychology, "-"))
concordant <- sum(q[upper.tri(q)] > 0)
discordant <- sum(q[upper.tri(q)] < 0)
score <- concordant - discordant
upper_tail <- kendall_upper(n)
upper <- upper_tail(score)
lower <- upper_tail(-score)
cat(paste0(if (tied > 0) "Exact test (not adjusted for ties):" else "Exact test:", "  Upper side P ="),
    round(upper, 4), "  Lower side P =", round(lower, 4), "  Two sided P =",
    round(min(1, 2 * min(upper, lower)), 4), "\n")

# The variance of the score allows for ties when there are any
v0 <- n * (n - 1) * (2 * n + 5)
se <- sqrt(if (tied > 0) (v0 - sum(tx * (tx - 1) * (2 * tx + 5)) - sum(ty * (ty - 1) * (2 * ty + 5))) / 18 +
             sum(tx * (tx - 1) * (tx - 2)) * sum(ty * (ty - 1) * (ty - 2)) / (9 * n * (n - 1) * (n - 2)) +
             sum(tx * (tx - 1)) * sum(ty * (ty - 1)) / (2 * n * (n - 1)) else v0 / 18)
pairs <- n * (n - 1) / 2
tau <- score / sqrt((pairs - tied_x) * (pairs - tied_y))
cat("Concordant pairs =", concordant, "  Discordant pairs =", discordant,
    "  Tied pairs =", tied, "\n")
cat(sprintf("Kendall's score = %d   (standard error = %.5f)\n", score, se))
cat(sprintf("Gamma = %.6f\n", score / (concordant + discordant)))

# Approximate 95% confidence interval for tau: the method of Samara and Randles
# (1988) as given by Hollander and Wolfe (1999), kept within -1 and 1
ci <- rowSums(q)                                # each observation's own score
v <- 2 / (n * (n - 1)) *
  (2 * (n - 2) / (n * (n - 1)^2) * sum((ci - mean(ci))^2) + 1 - tau^2)
limits <- pmin(1, pmax(-1, tau + c(-1, 1) * qnorm((1 + confidence) / 2) * sqrt(v)))
cat(sprintf("Kendall's %s = %.6f   Approximate %s CI = %.6f to %.6f\n",
            if (tied > 0) "tau b" else "tau", tau, pct, limits[1], limits[2]))

# Approximate tests from the normal distribution, without and with a continuity
# correction (StatsDirect advises the exact test for a sample as small as this)
for (cc in c(0, 1)) {
  z <- (score - cc * sign(score)) / se
  cat(sprintf("z = %.6f   Upper side P = %.4f   Lower side P = %.4f   %s%.4f\n",
              z, 1 - pnorm(z), pnorm(z), "Two sided P = ", 2 * pnorm(-abs(z))))
}

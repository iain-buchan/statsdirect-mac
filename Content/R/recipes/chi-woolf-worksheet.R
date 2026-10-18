# StatsDirect recipe: Woolf chi-square analysis of a series of 2 by 2 tables, as the help shows it in R.
# From the help's R code (chi_square_tests/woolf.htm); the data and settings above come from the run.
# data: sn, sr, xn, xr
# settings: confidence = cco

# the fourfold table of each stratum, from the group sizes and the numbers with the outcome
a <- sr
b <- xr
c <- sn - sr
d <- xn - xr
# Woolf chi-square analysis of 2 by 2 series: the StatsDirect help example (Armitage
# and Berry 1994, p. 516, smoking among lung cancer patients and controls in ten
# studies; the test workbook's Meta worksheet columns Smokers total, Smokers cancer,
# Control total and Control cancer) in R
# a = Smokers cancer, b = Control cancer, c = Smokers total - a, d = Control total - b
pct <- paste0(100 * confidence, "%")
k <- length(a)

# Base R has no Woolf function, so the statistics are computed by Woolf's formulae: each
# table's log odds ratio is weighted by the reciprocal of its variance, the weighted
# mean is the pooled log odds ratio, and the weighted sum of squares about that mean
# is the chi-square for heterogeneity between the tables, as Woolf proposed
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
z <- qnorm((1 + confidence) / 2)
woolf <- function(lor, v) {
  w <- 1 / v
  mean_lor <- sum(w * lor) / sum(w)
  se <- sqrt(1 / sum(w))
  ci <- mean_lor + c(-1, 1) * z * se
  chi2 <- (mean_lor / se)^2
  het <- sum(w * lor^2) - sum(w * lor)^2 / sum(w)
  cat("Number of tables =", k, "\n")
  cat("Mean log odds ratio =", six(mean_lor), "giving odds ratio =",
      six(exp(mean_lor)), "\n")
  cat("Variance of mean log odds ratio =", six(se^2), " standard error =", six(se),
      "\n")
  cat("Approximate", pct, "CI for mean log odds ratio =", six(ci[1]), "to", six(ci[2]),
      "\n")
  cat("Giving odds ratio of", six(exp(ci[1])), "to", six(exp(ci[2])), "\n")
  cat("Chi-square for expected log odds ratio = 0 is", six(chi2), "Chi =",
      six(mean_lor / se), pv(pchisq(chi2, 1, lower.tail = FALSE)), "\n")
  cat("Chi-square for heterogeneity =", six(het), "DF =", k - 1,
      pv(pchisq(het, k - 1, lower.tail = FALSE)), "\n")
}

# Without the Haldane correction: log(ad/bc) with variance 1/a + 1/b + 1/c + 1/d,
# which needs every cell of every table to be greater than zero
cat("For combined tables without Haldane correction:\n")
woolf(log(a * d / (b * c)), 1 / a + 1 / b + 1 / c + 1 / d)

# With the Haldane correction: 0.5 is added to each cell for the log odds ratio, and
# its variance is 1/(a+1) + 1/(b+1) + 1/(c+1) + 1/(d+1)
cat("For combined tables with Haldane correction:\n")
woolf(log((a + 0.5) * (d + 0.5) / ((b + 0.5) * (c + 0.5))),
      1 / (a + 1) + 1 / (b + 1) + 1 / (c + 1) + 1 / (d + 1))

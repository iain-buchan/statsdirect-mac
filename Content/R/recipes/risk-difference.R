# StatsDirect recipe: Risk difference meta-analysis, as the help shows it in R.
# From the help's R code (meta_analysis/risk_difference.htm); the data and settings above come from the run.
# data: n1, a, n2, b, study
# settings: confidence = gamma, exact_meta = metaExact

# Keep only studies with all inputs needed for this analysis.
keep <- complete.cases(n1, a, n2, b)
if (any(!keep)) cat("(", sum(!keep), " other rows not used)\n", sep = "")
n1 <- n1[keep]
a <- a[keep]
n2 <- n2[keep]
b <- b[keep]
study <- study[keep]
if (is.null(study)) study <- paste("Study", seq_along(n1))
# Older records did not save this preference; their R recipe used score intervals.
if (is.null(exact_meta)) exact_meta <- TRUE
# Risk difference meta-analysis: the StatsDirect help example (Fleiss and Gross 1991,
# deaths after myocardial infarction in seven placebo-controlled trials of aspirin; the
# test workbook's Meta-analysis worksheet columns A to E) in R

# Base R has no meta-analysis function, so the statistics are computed from the tables
# as the formulae above give them
pct <- paste0(100 * confidence, "%")
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
one <- function(x) formatC(x, digits = 1, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
z <- qnorm((1 + confidence) / 2)
k <- length(a)
c <- n1 - a
d <- n2 - b
n <- n1 + n2
rd <- a / n1 - b / n2

# The 'near exact' confidence interval of Miettinen and Nurminen (1985) for each study:
# the values of the difference at which the score statistic reaches -1.96 and +1.96,
# with the two proportions estimated under the constraint that they differ by that
# value (the closed form of the constrained estimates, Newcombe 1998 method 10) and
# the variance multiplied by N / (N - 1). These tables have no empty cells; the counts
# of a table with one would have a continuity correction first for the weights and the
# variances further down (but not for its risk difference or for these limits).
mn_limits <- function(a, n1, b, n2) {
  N <- n1 + n2
  est <- a / n1 - b / n2
  score <- function(delta) {
    if (delta == est) return(0)
    if (abs(est) == 1) {
      # With one arm all successes and the other all failures, the likelihood
      # derivative has a linear numerator. Use its root within the feasible range.
      p2 <- if (est > 0) (n1 - n2 * delta) / N else n2 * (1 - delta) / N
      p2 <- max(0, -delta, min(1, 1 - delta, p2))
    } else {
      L3 <- N
      L2 <- (n1 + 2 * n2) * delta - N - a - b
      L1 <- (n2 * delta - N - 2 * b) * delta + a + b
      L0 <- b * delta * (1 - delta)
      q <- L2^3 / (3 * L3)^3 - L1 * L2 / (6 * L3^2) + L0 / (2 * L3)
      # At q = 0 the cubic still has a nonzero scale. sign(0) would lose that root.
      p <- (if (q < 0) -1 else 1) * sqrt(L2^2 / (3 * L3)^2 - L1 / (3 * L3))
      p2 <- 2 * p * cos((pi + acos(q / p^3)) / 3) - L2 / (3 * L3)
    }
    p1 <- p2 + delta
    v <- (p1 * (1 - p1) / n1 + p2 * (1 - p2) / n2) * N / (N - 1)
    (a / n1 - b / n2 - delta) / sqrt(v)
  }
  lower <- if (est <= -1 + 1e-9) -1 else
    uniroot(function(x) score(x) - z, c(-1 + 1e-9, est), tol = 1e-12)$root
  upper <- if (est >= 1 - 1e-9) 1 else
    uniroot(function(x) score(x) + z, c(est, 1 - 1e-9), tol = 1e-12)$root
  c(lower, upper)
}
if (isTRUE(exact_meta)) {
  ci <- t(mapply(mn_limits, a, n1, b, n2))
} else {
  se_rd <- sqrt(a * c / n1^3 + b * d / n2^3)
  ci <- cbind(rd - z * se_rd, rd + z * se_rd)
}

# Mantel-Haenszel weights (fixed effects) and the pooled difference of Greenland and
# Robins (1985), with their variance formula
w_mh <- n1 * n2 / n
rd_mh <- sum(w_mh * rd) / sum(w_mh)
var_mh <- sum((a * c * n2^3 + b * d * n1^3) / (n1 * n2 * n^2)) / sum(w_mh)^2
se_mh <- sqrt(var_mh)

# Cochran's Q about the pooled difference, with inverse variance weights from the
# binomial variances; the DerSimonian-Laird moment estimate of the between studies
# variance and the random effects weights
v_iv <- a * c / n1^3 + b * d / n2^3
w_iv <- 1 / v_iv
q <- sum(w_iv * (rd - rd_mh)^2)
tau2 <- max(0, (q - (k - 1)) / (sum(w_iv) - sum(w_iv^2) / sum(w_iv)))
w_dl <- 1 / (v_iv + tau2)
rd_dl <- sum(w_dl * rd) / sum(w_dl)
se_dl <- 1 / sqrt(sum(w_dl))

# The study table: risk differences, their intervals, their binomial variances and
# the percentage weights
tab <- data.frame(Study = study, `Risk difference` = six(rd), Lower = six(ci[, 1]),
                  Upper = six(ci[, 2]), Variance = six(v_iv),
                  `% fixed` = six(100 * w_mh / sum(w_mh)),
                  `% random` = six(100 * w_dl / sum(w_dl)), check.names = FALSE)
cat(pct, "study confidence intervals (",
    if (isTRUE(exact_meta)) "Miettinen" else "approximate", ")\n", sep = " ")
print(tab, row.names = FALSE)

cat("Fixed effects (Mantel-Haenszel, Greenland-Robins)\n")
cat("Pooled risk difference = ", six(rd_mh), " (", pct, "CI = ", six(rd_mh - z * se_mh),
    " to ", six(rd_mh + z * se_mh), ")\n", sep = "")
x2 <- (rd_mh / se_mh)^2
cat("Chi-square (test risk difference differs from 0) =", six(x2), " (df = 1) ",
    pv(pchisq(x2, 1, lower.tail = FALSE)), "\n")

# I-squared = (Q - df) / Q, with the interval StatsDirect gives by default (the 'exact'
# option, Hedges and Pigott 2001): Q is treated as non-central chi-square and its
# distribution function at the observed Q is inverted for the non-centrality parameter
# lambda, using the selected upper and lower tail probabilities (a limit is 0 when
# even the central distribution gives less); each limit is converted to
# I-squared as lambda / (df + lambda)
cat("Non-combinability of studies\n")
dfree <- k - 1
cat("Cochran Q =", six(q), paste0(" (df = ", dfree, ") "),
    pv(pchisq(q, dfree, lower.tail = FALSE)), "\n")
cat("Moment-based estimate of between studies variance =", six(tau2), "\n")
# I-squared interval: recorded exact/test-based choice.
# Older records have no preference: retain the non-central interval they used.
if (is.null(exact_meta)) exact_meta <- TRUE
df_i2 <- k - 1
i2 <- if (k < 2) NA_real_ else if (q == 0) 0 else max(0, 100 * (q - df_i2) / q)
i2_ci <- rep(NA_real_, 2)
if (k >= 2 && confidence > 0 && confidence < 1) {
  if (isTRUE(exact_meta)) {
    # Invert the non-central chi-square CDF (Hedges & Pigott, 2001).
    lambda <- function(p) {
      if (pchisq(q, df_i2) <= p) 0 else
        uniroot(function(l) pchisq(q, df_i2, ncp = l) - p,
                c(0, 10 * q + 100), tol = 1e-10)$root
    }
    lim <- c(lambda((1 + confidence) / 2), lambda((1 - confidence) / 2))
    i2_ci <- 100 * lim / (df_i2 + lim)
  } else if (k >= 3) {
    # Test-based log(H) interval (Higgins & Thompson, 2002), as in
    # StatsDirect's MIT Meta.IsquareNcc. H is at least one.
    h2 <- max(1, q / df_i2)
    se_log_h <- if (q > k) 0.5 * (log(q) - log(df_i2)) /
      (sqrt(2 * q) - sqrt(2 * k - 3)) else
      sqrt((1 - 1 / (3 * (k - 2)^2)) / (2 * (k - 2)))
    h_limits <- exp(log(sqrt(h2)) + c(-1, 1) * z * se_log_h)
    h_limits[1] <- max(1, h_limits[1])
    i2_ci <- 100 * (1 - 1 / h_limits^2)
  }
}
if (k < 2) cat("I-squared not calculated: at least two studies are required.\n") else if (anyNA(i2_ci))
  cat("I-squared (inconsistency) =", one(i2), "% (interval unavailable for this number of studies and confidence level)\n") else
  cat("I-squared (inconsistency) = ", one(i2), "% (", pct, "CI = ",
      one(i2_ci[1]), "% to ", one(i2_ci[2]), "%)\n", sep = "")
# End of I-squared interval.

cat("Random effects (DerSimonian-Laird)\n")
cat("Pooled risk difference = ", six(rd_dl), " (", pct, "CI = ", six(rd_dl - z * se_dl),
    " to ", six(rd_dl + z * se_dl), ")\n", sep = "")
x2_dl <- (rd_dl / se_dl)^2
cat("Chi-square (test risk difference differs from 0) =", six(x2_dl), " (df = 1) ",
    pv(pchisq(x2_dl, 1, lower.tail = FALSE)), "\n")

# Bias indicators, both from the binomial variances that the inverse variance weights
# are made from, whatever the method of the intervals of the studies. Begg and
# Mazumdar's test is Kendall's rank correlation between the standardised effects
# (deviations from the inverse variance pooled estimate) and the variances, with the
# exact P that cor.test gives for so few studies when no values tie (fewer than about
# ten gives the test little power). Egger's test regresses the standardised effect
# (estimate / se) on precision (1 / se) and asks whether the intercept is zero, with
# a 90% interval.
cat("Bias indicators\n")
se_iv <- sqrt(v_iv)
rd_iv <- sum(w_iv * rd) / sum(w_iv)
t_std <- (rd - rd_iv) / sqrt(v_iv - 1 / sum(w_iv))
begg <- cor.test(t_std, v_iv, method = "kendall", conf.level = confidence)
cat("Begg-Mazumdar: Kendall's tau =", six(begg$estimate), " ", pv(begg$p.value),
    "(low power)\n")
egger <- lm(I(rd / se_iv) ~ I(1 / se_iv))
bias <- coef(egger)[1]
cat("Egger: bias = ", six(bias), " (90% CI = ", six(confint(egger, level = 0.9)[1, 1]),
    " to ", six(confint(egger, level = 0.9)[1, 2]), ")  ",
    pv(summary(egger)$coefficients[1, 4]), "\n", sep = "")

# The charts that follow in the report: a bias assessment (funnel) plot of each risk
# difference against its standard error, with the fixed effects pooled estimate and
# the limits within which 95% of study estimates would fall at each standard error
top <- max(se_iv) * 1.05
plot(rd, se_iv, ylim = c(top, 0), xlim = range(rd, rd_mh + c(-1, 1) * z * top),
     xlab = "Risk difference", ylab = "Standard error", main = "Bias assessment plot")
abline(v = rd_mh)
lines(rd_mh + c(-1, 0, 1) * z * top, c(top, 0, top))

# Then a forest plot for each model: a circle per study sized by its weight, its
# interval as a line, the pooled estimate as a diamond, the line of no effect and a
# dashed line at the pooled estimate
forest <- function(weight, pooled, lower, upper, title, label) {
  rows <- k:1
  op <- par(mar = c(5, 8, 4, 9))
  plot(NA, xlim = range(ci, lower, upper, 0), ylim = c(0, k + 0.5), yaxt = "n",
       ylab = "", xlab = "risk difference (95% confidence interval)", main = title)
  axis(2, at = c(rows, 0), labels = c(study, label), las = 1, tick = FALSE)
  axis(4, at = c(rows, 0), tick = FALSE, las = 1, cex.axis = 0.8,
       labels = sprintf("%.3f (%.3f, %.3f)", c(rd, pooled), c(ci[, 1], lower),
                        c(ci[, 2], upper)))
  abline(v = 0)
  segments(pooled, 0, pooled, k, lty = 2)
  segments(ci[, 1], rows, ci[, 2], rows)
  points(rd, rows, pch = 16, col = "grey40", cex = 0.6 + 2 * sqrt(weight / max(weight)))
  polygon(c(lower, pooled, upper, pooled), c(0, 0.25, 0, -0.25), col = "grey60")
  par(op)
}
forest(w_mh, rd_mh, rd_mh - z * se_mh, rd_mh + z * se_mh,
       "Risk difference meta-analysis plot [fixed effects]", "combined [fixed]")
forest(w_dl, rd_dl, rd_dl - z * se_dl, rd_dl + z * se_dl,
       "Risk difference meta-analysis plot [random effects]", "combined [random]")

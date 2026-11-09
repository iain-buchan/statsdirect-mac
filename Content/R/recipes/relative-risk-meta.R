# StatsDirect recipe: Relative risk meta-analysis, as the help shows it in R.
# From the help's R code (meta_analysis/relative_risk.htm); the data and settings above come from the run.
# data: exposed_total, exposed_cases, control_total, control_cases, study
# settings: confidence = gamma, exact_meta = metaExact

# Keep only studies with all inputs needed for this analysis.
keep <- complete.cases(exposed_total, exposed_cases, control_total, control_cases)
if (any(!keep)) cat("(", sum(!keep), " other rows not used)\n", sep = "")
exposed_total <- exposed_total[keep]
exposed_cases <- exposed_cases[keep]
control_total <- control_total[keep]
control_cases <- control_cases[keep]
study <- study[keep]
if (is.null(study)) study <- paste("Study", seq_along(exposed_total))
# Older records did not save this preference; their R recipe used score intervals.
if (is.null(exact_meta)) exact_meta <- TRUE
# Relative risk meta-analysis: the StatsDirect help example (Fleiss and Gross 1991,
# deaths after myocardial infarction in seven placebo-controlled trials of aspirin;
# the test workbook's Meta-analysis worksheet columns A to E) in R

# Each study's fourfold table in the report's order: a = exposed cases, b = control
# cases, cx = exposed non-cases and d = control non-cases (cx, because c is R's
# function for making a vector)
pct <- paste0(100 * confidence, "%")
a <- exposed_cases
b <- control_cases
cx <- exposed_total - exposed_cases
d <- control_total - control_cases
n <- a + b + cx + d
k <- length(a)
z <- qnorm((1 + confidence) / 2)
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
one <- function(x) formatC(x, digits = 1, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}

# Base R has no meta-analysis function, so the report is built from the formulae.
# The relative risk of each study, with Koopman's (1984) likelihood score interval:
# at a trial value of the ratio the two risks are estimated under the constraint
# that they stand in that ratio (the root of a quadratic in the control risk), and
# the limits are the ratios at which the score statistic for the exposed count
# reaches plus and minus the normal deviate. This holds when every cell is filled;
# the program adjusts a total equal to its count by a half before solving.
rr <- (a / (a + cx)) / (b / (b + d))
koopman <- function(x1, n1, x0, n0) {
  score <- function(theta) {
    qa <- (n0 + n1) * theta
    qb <- -((x0 + n1) * theta + x1 + n0)
    qc <- x0 + x1
    p0 <- (-qb - sqrt(qb^2 - 4 * qa * qc)) / (2 * qa)
    p1 <- p0 * theta
    v <- 1 / ((1 - p0) / (n0 * p0) + (1 - p1) / (n1 * p1))
    (x1 - n1 * p1) / (1 - p1) / sqrt(v)
  }
  est <- (x1 / n1) / (x0 / n0)
  c(uniroot(function(t) score(t) - z, c(est / 100, est), tol = 1e-12)$root,
    uniroot(function(t) score(t) + z, c(est, est * 100), tol = 1e-12)$root)
}
if (isTRUE(exact_meta)) {
  ci <- t(mapply(koopman, a, a + cx, b, b + d))
} else {
  se_log_rr <- sqrt(1 / a + 1 / b - 1 / (a + cx) - 1 / (b + d))
  ci <- cbind(exp(log(rr) - z * se_log_rr), exp(log(rr) + z * se_log_rr))
}
cat("Stratum  Relative risk", pct, "CI (",
    if (isTRUE(exact_meta)) "Koopman" else "approximate", ")\n", sep = " ")
for (i in 1:k) cat(i, six(rr[i]), six(ci[i, 1]), six(ci[i, 2]), study[i], "\n")

# Fixed effects: the Mantel-Haenszel type pooled risk ratio of Rothman and Boice,
# with the Greenland-Robins variance of its log for the interval and chi-square
w_mh <- b * (a + cx) / n
rr_mh <- sum(a * (b + d) / n) / sum(w_mh)
v_mh <- sum(((a + b) * (a + cx) * (b + d) - a * b * n) / n^2) /
  (sum(a * (b + d) / n) * sum(w_mh))
x2 <- log(rr_mh)^2 / v_mh

# Cochran's Q about the pooled log risk ratio above, each study weighted by the
# inverse of the usual variance of its log relative risk; the DerSimonian-Laird
# moment estimate of the between studies variance then inflates each variance for
# the random effects weights
lrr <- log(rr)
v_i <- 1 / a + 1 / b - 1 / (a + cx) - 1 / (b + d)
w_i <- 1 / v_i
q <- sum(w_i * (lrr - log(rr_mh))^2)
tau2 <- max(0, (q - (k - 1)) / (sum(w_i) - sum(w_i^2) / sum(w_i)))
w_dl <- 1 / (tau2 + v_i)
rr_dl <- exp(sum(w_dl * lrr) / sum(w_dl))
dl_ci <- exp(sum(w_dl * lrr) / sum(w_dl) + c(-1, 1) * z / sqrt(sum(w_dl)))
x2_dl <- sum(w_dl * lrr)^2 / sum(w_dl)

# The report's second table: the log relative risk with its variance, and each
# study's share of the fixed and random weights
cat("Stratum  Standardized effect  Variance  % Weights (fixed, random)\n")
for (i in 1:k) {
  cat(i, six(lrr[i]), six(v_i[i]), six(100 * w_mh[i] / sum(w_mh)),
      six(100 * w_dl[i] / sum(w_dl)), study[i], "\n")
}

cat("Fixed effects (Mantel-Haenszel, Rothman-Boice)\n")
cat("Pooled relative risk = ", six(rr_mh), " (", pct, "CI = ",
    six(exp(log(rr_mh) - z * sqrt(v_mh))), " to ",
    six(exp(log(rr_mh) + z * sqrt(v_mh))), ")\n", sep = "")
cat("Chi2 (test relative risk differs from 1) =", six(x2), " (df = 1) ",
    pv(pchisq(x2, 1, lower.tail = FALSE)), "\n")

# I-squared = (Q - df) / Q, with the default interval that the heterogeneity topic attributes
# to Hedges and Pigott (2001): Q is treated as non-central chi-square and its
# distribution function at the observed Q is inverted for the non-centrality parameter
# lambda, using the selected upper and lower tail probabilities (a limit is 0 when
# even the central distribution gives less); each limit is converted to
# I-squared as lambda / (df + lambda)
cat("Non-combinability of studies\n")
cat("Cochran Q = ", six(q), "  (df = ", k - 1, ")  ",
    pv(pchisq(q, k - 1, lower.tail = FALSE)), "\n", sep = "")
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
if (k < 2) cat("I2 not calculated: at least two studies are required.\n") else if (anyNA(i2_ci))
  cat("I2 (inconsistency) =", one(i2), "% (interval unavailable for this number of studies and confidence level)\n") else
  cat("I2 (inconsistency) = ", one(i2), "% (", pct, "CI = ",
      one(i2_ci[1]), "% to ", one(i2_ci[2]), "%)\n", sep = "")
# End of I-squared interval.

cat("Random effects (DerSimonian-Laird)\n")
cat("Pooled relative risk = ", six(rr_dl), " (", pct, "CI = ", six(dl_ci[1]), " to ",
    six(dl_ci[2]), ")\n", sep = "")
cat("Chi2 (test relative risk differs from 1) =", six(x2_dl), " (df = 1) ",
    pv(pchisq(x2_dl, 1, lower.tail = FALSE)), "\n")

# Bias indicators. Begg and Mazumdar's rank correlation is Kendall's tau between
# each study's deviation from the inverse variance pooled log relative risk,
# standardised by its variance less the pooled variance, and that variance; with
# no ties among seven studies cor.test gives the exact two sided P, and fewer than
# eleven studies give the test little power
se_i <- sqrt(v_i)
dev <- (lrr - sum(w_i * lrr) / sum(w_i)) / sqrt(v_i - 1 / sum(w_i))
kt <- cor.test(dev, v_i, method = "kendall", conf.level = confidence)
cat("Bias indicators\n")
cat("Begg-Mazumdar: Kendall's tau =", six(kt$estimate), "", pv(kt$p.value),
    "(low power)\n")

# Egger's test regresses each study's standardised effect (log relative risk over
# its standard error) on its precision (one over that standard error); the bias
# is the intercept, judged by a t test on k - 2 degrees of freedom with a 90%
# interval, the level the test is conventionally reported at
egger <- function(y, x, label) {
  fit <- lm(y ~ x)
  bias <- coef(summary(fit))[1, ]
  ci <- confint(fit, level = 0.9)[1, ]
  cat(label, ": bias = ", six(bias["Estimate"]), " (90% CI = ", six(ci[1]),
      " to ", six(ci[2]), ") ", pv(bias["Pr(>|t|)"]), "\n", sep = "")
}
egger(lrr / se_i, 1 / se_i, "Egger")

# Harbord's modification (Harbord, Egger and Sterne 2006) uses the efficient score
# for the log relative risk and its Fisher information in place of the estimate and
# its standard error, which are far less correlated than the estimate and its standard
# error when effects are large or events few
score <- (a * n - (a + b) * (a + cx)) / (cx + d)
info <- (b + d) * (a + cx) * (a + b) / (n * (cx + d))
egger(score / sqrt(info), sqrt(info), "Harbord-Egger")

# The report's L'Abbe plot: the risk in the exposed group of each study against
# the risk in its control group, the symbol growing with the study size, with the
# line of equal risks and the line of the pooled relative risk
# the axes reach the largest risk, rounded up to a multiple of 5, from 25% up to 100%
labbe_top <- min(100, max(25, 5 * ceiling(max(c(100 * b / (b + d), 100 * a / (a + cx)), na.rm = TRUE) / 5)))
plot(100 * b / (b + d), 100 * a / (a + cx), cex = 0.5 + 2 * sqrt(n / max(n)),
     xlim = c(0, labbe_top), ylim = c(0, labbe_top), xlab = "control percent",
     ylab = "experimental percent",
     main = "L'Abbe plot (symbol size represents sample size)")
abline(0, 1)
abline(0, rr_mh, lty = 3)

# The two forest plots: each study's relative risk (the symbol growing with its
# weight) with its interval on a log scale, the line of no effect at 1 and the
# pooled estimate as a diamond at the foot
forest <- function(weights, pooled, lower, upper, title, label) {
  y <- rev(seq_len(k)) + 1
  par(mar = c(5, 8, 4, 8))
  plot(rr, y, log = "x", xlim = range(ci, lower, upper), ylim = c(0.5, k + 1.5),
       pch = 15, cex = 0.5 + 2 * sqrt(weights / max(weights)), yaxt = "n", ylab = "",
       xlab = "relative risk (95% confidence interval)", main = title)
  segments(ci[, 1], y, ci[, 2], y)
  polygon(c(lower, pooled, upper, pooled), c(1, 1.3, 1, 0.7), col = "grey")
  segments(pooled, 1, pooled, k + 1, lty = 3)
  abline(v = 1)
  axis(2, at = c(y, 1), labels = c(study, label), las = 1, tick = FALSE)
  axis(4, at = c(y, 1), las = 1, tick = FALSE,
       labels = sprintf("%.2f (%.2f, %.2f)", c(rr, pooled), c(ci[, 1], lower),
                        c(ci[, 2], upper)))
}
forest(w_mh, rr_mh, exp(log(rr_mh) - z * sqrt(v_mh)), exp(log(rr_mh) + z * sqrt(v_mh)),
       "Relative risk meta-analysis plot (fixed effects)", "combined [fixed]")
forest(w_dl, rr_dl, dl_ci[1], dl_ci[2],
       "Relative risk meta-analysis plot (random effects)", "combined [random]")

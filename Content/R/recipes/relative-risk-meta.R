# StatsDirect recipe: Relative risk meta-analysis, as the help shows it in R.
# From the help's R code (meta_analysis/relative_risk.htm); the data and settings above come from the run.
# data: exposed_total, exposed_cases, control_total, control_cases, study
# settings: confidence = gamma, exact_meta = metaExact, continuity = metaCC, delay_cc = delayContinuityCorrection

# Keep only studies with all inputs needed for this analysis.
keep <- complete.cases(exposed_total, exposed_cases, control_total, control_cases)
if (any(!keep)) cat("(", sum(!keep), " other rows not used)\n", sep = "")
exposed_total <- exposed_total[keep]
exposed_cases <- exposed_cases[keep]
control_total <- control_total[keep]
control_cases <- control_cases[keep]
study <- study[keep]
if (is.null(study)) study <- paste("Study", seq_along(exposed_total))
# A study whose label is blank has its place among the studies kept, as in the report.
blank <- is.na(study) | !nzchar(trimws(study))
study[blank] <- paste("stratum", which(blank))
# Older records did not save this preference; their R recipe used score intervals.
if (is.null(exact_meta)) exact_meta <- TRUE
# Nor the continuity correction: the program's default is the treatment arm
# correction, not delayed.
if (is.null(continuity)) continuity <- -9
if (is.null(delay_cc)) delay_cc <- FALSE
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
z <- qnorm((1 + confidence) / 2)
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
one <- function(x) formatC(x, digits = 1, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}

# A study is pooled when both of its groups have subjects and one of them has an
# event; the others are listed as excluded. k is the number pooled.
included <- a + cx > 0 & b + d > 0 & !(a == 0 & b == 0)
k <- sum(included)
# A pooled study with an empty cell has a continuity correction in every cell for
# its relative risk, variance and weights (its score limits use the cells as they
# are): the program's default, the treatment arm correction (Sweeting, Sutton and
# Lambert 2004), adds n1 / (n1 + n2) to the cells of the first group and
# n2 / (n1 + n2) to those of the second; a set correction between 0 and 1 is added
# to every cell, and any other value adds a half
correct <- function(a, b, cx, d) {
  x <- if (continuity == 0) 0.5 else continuity
  if (x == -9 && a + cx > 0 && b + d > 0) {
    r <- (b + d) / (a + cx)
    c(a + 1 / (r + 1), b + r / (r + 1), cx + 1 / (r + 1), d + r / (r + 1))
  } else c(a, b, cx, d) + if (x > 0 && x < 1) x else 0.5
}
cced <- included & (a <= 0 | b <= 0 | cx <= 0 | d <= 0)
corrected <- cbind(a, b, cx, d)
for (i in which(cced)) corrected[i, ] <- correct(a[i], b[i], cx[i], d[i])
a1 <- corrected[, 1]
b1 <- corrected[, 2]
c1 <- corrected[, 3]
d1 <- corrected[, 4]
note <- ifelse(!included, "* (excluded)", ifelse(cced, paste0("[CC = ",
  if (continuity == -9) "treatment arm" else format(continuity), "]"), ""))

# Base R has no meta-analysis function, so the report is built from the formulae.
# The relative risk of each study, with Koopman's (1984) likelihood score interval:
# at a trial value of the ratio the two risks are estimated under the constraint
# that they stand in that ratio (the smaller root of a quadratic in the control
# risk, kept to the values that leave both risks at most 1), and the limits are the
# ratios at which the score statistic for the difference of the observed risks
# reaches plus and minus the normal deviate, searched for on the log scale. With
# no exposed event the lower limit is 0, with no control event the upper limit is
# infinite, and with an event in every subject of both groups the limits have a
# closed form.
rr <- ifelse(included, (a1 / (a1 + c1)) / (b1 / (b1 + d1)), NA)
koopman <- function(x1, n1, x0, n0) {
  if (x0 == n0 && x1 == n1) return(c(n1 / (n1 + z^2), (n0 + z^2) / n0))
  score <- function(theta) {
    qa <- (n0 + n1) * theta
    qb <- -((x0 + n1) * theta + x1 + n0)
    qc <- x0 + x1
    p0 <- min(2 * qc / (-qb + sqrt(max(0, qb^2 - 4 * qa * qc))), 1, 1 / theta)
    p1 <- p0 * theta
    (x1 / n1 - theta * x0 / n0) / sqrt(p1 * (1 - p1) / n1 + theta^2 * p0 * (1 - p0) / n0)
  }
  est <- (x1 / n1) / (x0 / n0)
  at <- if (is.finite(est) && est > 0) log(est) else if (x1 == 0) -60 else 60
  f <- function(l, target) score(exp(l)) - target
  c(if (x1 == 0) 0 else exp(uniroot(f, c(-60, at), target = z, tol = 1e-12)$root),
    if (x0 == 0) Inf else exp(uniroot(f, c(at, 60), target = -z, tol = 1e-12)$root))
}
ci <- cbind(rep(0, length(a)), Inf)   # the limits the report gives an excluded study
if (isTRUE(exact_meta)) {
  for (i in which(included)) ci[i, ] <- koopman(a[i], a[i] + cx[i], b[i], b[i] + d[i])
} else {
  se_log_rr <- sqrt(1 / a1 + 1 / b1 - 1 / (a1 + c1) - 1 / (b1 + d1))
  ci[included, ] <- cbind(exp(log(rr) - z * se_log_rr), exp(log(rr) + z * se_log_rr))[included, ]
}
cat("Stratum  Relative risk", pct, "CI (",
    if (isTRUE(exact_meta)) "Koopman" else "approximate", ")\n", sep = " ")
for (i in seq_along(a)) cat(i, six(rr[i]), six(ci[i, 1]), six(ci[i, 2]), study[i], note[i], "\n")

# Fixed effects: the Mantel-Haenszel type pooled risk ratio of Rothman and Boice,
# with the Greenland-Robins variance of its log for the interval and chi-square, of
# the pooled studies' corrected cells, or of the cells as they are when the
# correction is delayed and some pooled study has an event in each group
raw <- isTRUE(delay_cc) && any(a[included] > 0) && any(b[included] > 0)
ap <- if (raw) a else a1
bp <- if (raw) b else b1
cp <- if (raw) cx else c1
dp <- if (raw) d else d1
np <- ap + bp + cp + dp
w_mh <- ifelse(included, bp * (ap + cp) / np, 0)
rr_mh <- sum((ap * (bp + dp) / np)[included]) / sum(w_mh)
v_mh <- sum((((ap + bp) * (ap + cp) * (bp + dp) - ap * bp * np) / np^2)[included]) /
  (sum((ap * (bp + dp) / np)[included]) * sum(w_mh))
x2 <- log(rr_mh)^2 / v_mh

# Cochran's Q about the pooled log risk ratio above, each pooled study weighted by
# the inverse of the usual variance of its log relative risk; the DerSimonian-Laird
# moment estimate of the between studies variance then inflates each variance for
# the random effects weights
lrr <- log(rr)
v_i <- ifelse(included, 1 / a1 + 1 / b1 - 1 / (a1 + c1) - 1 / (b1 + d1), NA)
w_i <- ifelse(included, 1 / v_i, 0)
q <- if (k > 1) sum((w_i * (lrr - log(rr_mh))^2)[included]) else 0
spread <- sum(w_i) - sum(w_i^2) / sum(w_i)
tau2 <- if (spread == 0) 0 else max(0, (q - (k - 1)) / spread)
w_dl <- ifelse(included, 1 / (tau2 + v_i), 0)
rr_dl <- exp(sum((w_dl * lrr)[included]) / sum(w_dl))
dl_ci <- exp(sum((w_dl * lrr)[included]) / sum(w_dl) + c(-1, 1) * z / sqrt(sum(w_dl)))
x2_dl <- sum((w_dl * lrr)[included])^2 / sum(w_dl)

# The report's second table: the log relative risk with its variance, and each
# study's share of the fixed and random weights
cat("Stratum  Standardized effect  Variance  % Weights (fixed, random)\n")
for (i in seq_along(a)) {
  cat(i, six(lrr[i]), six(v_i[i]), six(100 * w_mh[i] / sum(w_mh)),
      six(100 * w_dl[i] / sum(w_dl)), study[i], note[i], "\n")
}

cat("Fixed effects (Mantel-Haenszel, Rothman-Boice)\n")
cat("Pooled relative risk = ", six(rr_mh), " (", pct, " CI = ",
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
    pv(if (k > 1) pchisq(q, k - 1, lower.tail = FALSE) else NA_real_), "\n", sep = "")
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
  } else if (k >= 3 || q > k) {
    # Test-based log(H) interval (Higgins & Thompson, 2002), as in
    # StatsDirect's MIT Meta.IsquareNcc. H is at least one; with two studies
    # only Q > k gives a standard error (the first form below).
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
  cat("I2 (inconsistency) = ", one(i2), "% (", pct, " CI = ",
      one(i2_ci[1]), "% to ", one(i2_ci[2]), "%)\n", sep = "")
# End of I-squared interval.

cat("Random effects (DerSimonian-Laird)\n")
cat("Pooled relative risk = ", six(rr_dl), " (", pct, " CI = ", six(dl_ci[1]), " to ",
    six(dl_ci[2]), ")\n", sep = "")
cat("Chi2 (test relative risk differs from 1) =", six(x2_dl), " (df = 1) ",
    pv(pchisq(x2_dl, 1, lower.tail = FALSE)), "\n")

# Bias indicators, which the report gives only when more than three studies are
# pooled. Begg and Mazumdar's rank correlation is Kendall's tau between each
# pooled study's deviation from the inverse variance pooled log relative risk,
# standardised by its variance less the pooled variance, and that variance; with
# no ties among seven studies cor.test gives the exact two sided P. With ties the
# report gives tau-b and a continuity corrected normal approximation, which is
# cor.test(..., exact = FALSE, continuity = TRUE). Fewer than eleven studies give
# the test little power, which the report then notes
cat("Bias indicators\n")
se_i <- sqrt(v_i)
# Egger's and Harbord's intervals are at the level of the bias tests, twice the
# analysis's alpha (90% for a 95% analysis), as the tests are conventionally read
bias_level <- 1 - 2 * (1 - confidence)
if (!(bias_level > 0 && bias_level < 1)) bias_level <- 0.9
if (k > 3) {
  use <- included
  dev <- (lrr - sum(w_i * lrr, na.rm = TRUE) / sum(w_i)) / sqrt(v_i - 1 / sum(w_i))
  tied <- anyDuplicated(dev[use]) > 0 || anyDuplicated(v_i[use]) > 0
  kt <- cor.test(dev[use], v_i[use], method = "kendall", exact = if (tied) FALSE else NULL,
                 continuity = TRUE, conf.level = confidence)
  cat("Begg-Mazumdar: Kendall's tau =", six(kt$estimate), "", pv(kt$p.value),
      if (k < 11 && !is.na(kt$estimate)) "(low power)\n" else "\n")

  # Egger's test regresses each study's standardised effect (log relative risk over
  # its standard error) on its precision (one over that standard error); the bias
  # is the intercept, judged by a t test on k - 2 degrees of freedom. As the report
  # has it, there is no figure when every study has the same precision or the line
  # fits every study exactly
  egger <- function(y, x, label, spread = diff(range(x)) > 1e-12 * max(x)) {
    fit <- lm(y ~ x)
    if (spread && sum(residuals(fit)^2) > 1e-12 * sum(y^2)) {
      bias <- coef(summary(fit))[1, ]
      ci <- confint(fit, level = bias_level)[1, ]
    } else bias <- ci <- c(Estimate = NA, "Pr(>|t|)" = NA)
    cat(label, ": bias = ", six(bias["Estimate"]), " (", round(100 * bias_level, 2), "% CI = ",
        six(ci[1]), " to ", six(ci[2]), ") ", pv(bias["Pr(>|t|)"]), "\n", sep = "")
    invisible(unname(c(bias["Estimate"], ci[1:2], bias["Pr(>|t|)"])))
  }
  egger_figures <- egger(lrr[use] / se_i[use], 1 / se_i[use], "Egger")

  # Harbord's modification (Harbord, Egger and Sterne 2006) uses the efficient score
  # for the log relative risk and its Fisher information in place of the estimate and
  # its standard error, which are far less correlated than the estimate and its standard
  # error when effects are large or events few. It is of the cells as they are, in
  # the studies with an event and a subject without one and a score with a variance
  score <- (a * n - (a + b) * (a + cx)) / (cx + d)
  info <- (b + d) * (a + cx) * (a + b) / (n * (cx + d))
  scored <- a + cx > 0 & b + d > 0 & !(a == 0 & b == 0) & !(cx == 0 & d == 0) &
    is.finite(info) & info > 0
  if (sum(scored) > 3) {
    x <- sqrt(info[scored])
    harbord_figures <- egger(score[scored] / x, x, "Harbord-Egger",
                             spread = sum((x - mean(x))^2) > 1e-12 * sum(x^2))
  } else {
    harbord_figures <- rep(NA, 4)
    cat("Harbord-Egger: bias = * (", round(100 * bias_level, 2), "% CI = * to *) P = *\n", sep = "")
  }
} else cat("Bias indicators need more than three studies with an estimate\n")

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
# pooled estimate as a diamond at the foot; an excluded study has a row without
# an estimate, and an infinite or zero limit runs to the edge of the plot
forest <- function(weights, pooled, lower, upper, title, label) {
  y <- rev(seq_along(a)) + 1
  limits <- c(ci[included, ], lower, upper)
  xlim <- range(limits[is.finite(limits) & limits > 0])
  par(mar = c(5, 8, 4, 8))
  plot(rr, y, log = "x", xlim = xlim, ylim = c(0.5, length(a) + 1.5),
       pch = 15, cex = 0.5 + 2 * sqrt(weights / max(weights)), yaxt = "n", ylab = "",
       xlab = paste0("relative risk (", pct, " confidence interval)"), main = title)
  segments(pmax(ci[, 1], xlim[1])[included], y[included], pmin(ci[, 2], xlim[2])[included], y[included])
  polygon(c(lower, pooled, upper, pooled), c(1, 1.3, 1, 0.7), col = "grey")
  segments(pooled, 1, pooled, length(a) + 1, lty = 3)
  abline(v = 1)
  axis(2, at = c(y, 1), labels = c(study, label), las = 1, tick = FALSE)
  axis(4, at = c(y, 1), las = 1, tick = FALSE,
       labels = c(ifelse(included, sprintf("%.2f (%.2f, %.2f)", rr, ci[, 1], ci[, 2]), "excluded"),
                  sprintf("%.2f (%.2f, %.2f)", pooled, lower, upper)))
}
forest(w_mh, rr_mh, exp(log(rr_mh) - z * sqrt(v_mh)), exp(log(rr_mh) + z * sqrt(v_mh)),
       "Relative risk meta-analysis plot (fixed effects)", "combined [fixed]")
forest(w_dl, rr_dl, dl_ci[1], dl_ci[2],
       "Relative risk meta-analysis plot (random effects)", "combined [random]")

# StatsDirect recipe: Risk difference meta-analysis, as the help shows it in R.
# From the help's R code (meta_analysis/risk_difference.htm); the data and settings above come from the run.
# data: n1, a, n2, b, study
# settings: confidence = gamma, exact_meta = metaExact, continuity = metaCC, delay_cc = delayContinuityCorrection

# Keep only studies with all inputs needed for this analysis.
keep <- complete.cases(n1, a, n2, b)
if (any(!keep)) cat("(", sum(!keep), " other rows not used)\n", sep = "")
n1 <- n1[keep]
a <- a[keep]
n2 <- n2[keep]
b <- b[keep]
study <- study[keep]
if (is.null(study)) study <- paste("Study", seq_along(n1))
# A study whose label is blank has its place among the studies kept, as in the report.
blank <- is.na(study) | !nzchar(trimws(study))
study[blank] <- paste("stratum", which(blank))
# Older records did not save this preference; their R recipe used score intervals.
if (is.null(exact_meta)) exact_meta <- TRUE
# Nor the continuity correction: the program's default is the treatment arm
# correction, not delayed.
if (is.null(continuity)) continuity <- -9
if (is.null(delay_cc)) delay_cc <- FALSE
# Risk difference meta-analysis: the StatsDirect help example (Fleiss and Gross 1991,
# deaths after myocardial infarction in seven placebo-controlled trials of aspirin; the
# test workbook's Meta-analysis worksheet columns A to E) in R

# Base R has no meta-analysis function, so the statistics are computed from the tables
# as the formulae above give them
pct <- paste0(100 * confidence, "%")
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
one <- function(x) formatC(x, digits = 1, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
z <- qnorm((1 + confidence) / 2)
c <- n1 - a
d <- n2 - b
n <- n1 + n2
# A study with a group of nobody has no risk difference and is listed as excluded;
# k is the number of studies pooled
included <- n1 > 0 & n2 > 0
k <- sum(included)
rd <- ifelse(included, a / n1 - b / n2, NA)
# The variance and weights of a pooled study with an empty cell have a continuity
# correction in every cell (not its risk difference or its score limits): the
# program's default, the treatment arm correction (Sweeting, Sutton and Lambert
# 2004), adds n1 / (n1 + n2) to the cells of the first group and n2 / (n1 + n2) to
# those of the second; a set correction between 0 and 1 is added to every cell, and
# any other value adds a half
correct <- function(a, b, c, d) {
  x <- if (continuity == 0) 0.5 else continuity
  if (x == -9 && a + c > 0 && b + d > 0) {
    r <- (b + d) / (a + c)
    c(a + 1 / (r + 1), b + r / (r + 1), c + 1 / (r + 1), d + r / (r + 1))
  } else c(a, b, c, d) + if (x > 0 && x < 1) x else 0.5
}
cced <- included & (a <= 0 | b <= 0 | c <= 0 | d <= 0)
corrected <- cbind(a, b, c, d)
for (i in which(cced)) corrected[i, ] <- correct(a[i], b[i], c[i], d[i])
a1 <- corrected[, 1]
b1 <- corrected[, 2]
c1 <- corrected[, 3]
d1 <- corrected[, 4]
note <- ifelse(!included, "* (excluded)", ifelse(cced, paste0("[CC = ",
  if (continuity == -9) "treatment arm" else format(continuity), "]"), ""))

# The binomial variance of each pooled study's difference, from its corrected cells
v_iv <- ifelse(included, a1 * c1 / (a1 + c1)^3 + b1 * d1 / (b1 + d1)^3, NA)

# The 'near exact' confidence interval of Miettinen and Nurminen (1985) for each study:
# the values of the difference at which the score statistic reaches -1.96 and +1.96,
# with the two proportions estimated under the constraint that they differ by that
# value (the closed form of the constrained estimates, Newcombe 1998 method 10) and
# the variance multiplied by N / (N - 1). These limits are of the counts as they
# are; a table with an empty cell has a continuity correction for the weights and
# the variances further down.
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
  ci <- matrix(NA_real_, length(a), 2)
  for (i in which(included)) ci[i, ] <- mn_limits(a[i], n1[i], b[i], n2[i])
} else {
  se_rd <- sqrt(v_iv)
  ci <- cbind(rd - z * se_rd, rd + z * se_rd)
}

# Mantel-Haenszel weights (fixed effects) and the pooled difference of Greenland and
# Robins (1985), with their variance formula, of the corrected cells, or of the
# cells as they are when the correction is delayed
ap <- if (isTRUE(delay_cc)) a else a1
bp <- if (isTRUE(delay_cc)) b else b1
cp <- if (isTRUE(delay_cc)) c else c1
dp <- if (isTRUE(delay_cc)) d else d1
m1 <- ap + cp
m2 <- bp + dp
w_mh <- ifelse(included, m1 * m2 / (m1 + m2), 0)
rd_mh <- sum((w_mh * rd)[included]) / sum(w_mh)
var_mh <- sum(((ap * cp * m2^3 + bp * dp * m1^3) / (m1 * m2 * (m1 + m2)^2))[included]) / sum(w_mh)^2
se_mh <- sqrt(var_mh)

# Cochran's Q about the pooled difference, with inverse variance weights from the
# binomial variances; the DerSimonian-Laird moment estimate of the between studies
# variance and the random effects weights
w_iv <- ifelse(included, 1 / v_iv, 0)
q <- if (k > 1) sum((w_iv * (rd - rd_mh)^2)[included]) else 0
spread <- sum(w_iv) - sum(w_iv^2) / sum(w_iv)
tau2 <- if (spread == 0) 0 else max(0, (q - (k - 1)) / spread)
w_dl <- ifelse(included, 1 / (v_iv + tau2), 0)
rd_dl <- sum((w_dl * rd)[included]) / sum(w_dl)
se_dl <- 1 / sqrt(sum(w_dl))

# The study table: risk differences, their intervals, their binomial variances and
# the percentage weights
tab <- data.frame(Study = trimws(paste(study, note)), `Risk difference` = six(rd), Lower = six(ci[, 1]),
                  Upper = six(ci[, 2]), Variance = six(v_iv),
                  `% fixed` = six(100 * w_mh / sum(w_mh)),
                  `% random` = six(100 * w_dl / sum(w_dl)), check.names = FALSE)
cat(pct, "study confidence intervals (",
    if (isTRUE(exact_meta)) "Miettinen" else "approximate", ")\n", sep = " ")
print(tab, row.names = FALSE)

cat("Fixed effects (Mantel-Haenszel, Greenland-Robins)\n")
cat("Pooled risk difference = ", six(rd_mh), " (", pct, " CI = ", six(rd_mh - z * se_mh),
    " to ", six(rd_mh + z * se_mh), ")\n", sep = "")
# without an event, or without a subject free of it, in any study the cells as they
# are give the pooled difference no variance, and so no test
x2 <- if (se_mh > 0) (rd_mh / se_mh)^2 else NA
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
    pv(if (k > 1) pchisq(q, dfree, lower.tail = FALSE) else NA_real_), "\n")
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
if (k < 2) cat("I-squared not calculated: at least two studies are required.\n") else if (anyNA(i2_ci))
  cat("I-squared (inconsistency) =", one(i2), "% (interval unavailable for this number of studies and confidence level)\n") else
  cat("I-squared (inconsistency) = ", one(i2), "% (", pct, " CI = ",
      one(i2_ci[1]), "% to ", one(i2_ci[2]), "%)\n", sep = "")
# End of I-squared interval.

cat("Random effects (DerSimonian-Laird)\n")
cat("Pooled risk difference = ", six(rd_dl), " (", pct, " CI = ", six(rd_dl - z * se_dl),
    " to ", six(rd_dl + z * se_dl), ")\n", sep = "")
x2_dl <- (rd_dl / se_dl)^2
cat("Chi-square (test risk difference differs from 0) =", six(x2_dl), " (df = 1) ",
    pv(pchisq(x2_dl, 1, lower.tail = FALSE)), "\n")

# Bias indicators, which the report gives only when more than three studies are
# pooled, both from the binomial variances that the inverse variance weights are made
# from, whatever the method of the intervals of the studies. Begg and Mazumdar's test
# is Kendall's rank correlation between the standardised effects (deviations from the
# inverse variance pooled estimate) and the variances, with the exact P that cor.test
# gives for so few studies when no values tie; with ties the report gives tau-b and a
# continuity corrected normal approximation, cor.test(..., exact = FALSE,
# continuity = TRUE). Fewer than eleven studies give the test little power, which
# the report then notes. Egger's test regresses the standardised effect (estimate / se) on
# precision (1 / se) and asks whether the intercept is zero, with an interval at the
# bias tests' level, twice the analysis's alpha (90% for a 95% analysis); as the
# report has it, there is no figure when every study has the same precision or the
# line fits every study exactly.
cat("Bias indicators\n")
se_iv <- sqrt(v_iv)
bias_level <- 1 - 2 * (1 - confidence)
if (!(bias_level > 0 && bias_level < 1)) bias_level <- 0.9
if (k > 3) {
  rd_iv <- sum((w_iv * rd)[included]) / sum(w_iv)
  t_std <- (rd - rd_iv) / sqrt(v_iv - 1 / sum(w_iv))
  tied <- anyDuplicated(t_std[included]) > 0 || anyDuplicated(v_iv[included]) > 0
  begg <- cor.test(t_std[included], v_iv[included], method = "kendall",
                   exact = if (tied) FALSE else NULL, continuity = TRUE, conf.level = confidence)
  cat("Begg-Mazumdar: Kendall's tau =", six(begg$estimate), " ", pv(begg$p.value),
      if (k < 11 && !is.na(begg$estimate)) "(low power)\n" else "\n")
  precision <- 1 / se_iv[included]
  standard <- rd[included] / se_iv[included]
  egger <- lm(standard ~ precision)
  if (diff(range(precision)) > 1e-12 * max(precision) &&
      sum(residuals(egger)^2) > 1e-12 * sum(standard^2)) {
    egger_ci <- confint(egger, level = bias_level)[1, ]
    egger_p <- summary(egger)$coefficients[1, 4]
    bias <- coef(egger)[1]
  } else bias <- egger_p <- egger_ci <- c(NA, NA)
  egger_figures <- unname(c(bias[1], egger_ci[1:2], egger_p[1]))
  cat("Egger: bias = ", six(bias[1]), " (", round(100 * bias_level, 2), "% CI = ", six(egger_ci[1]),
      " to ", six(egger_ci[2]), ")  ", pv(egger_p[1]), "\n", sep = "")
} else cat("Bias indicators need more than three studies with an estimate\n")

# The charts that follow in the report: a bias assessment (funnel) plot of each risk
# difference against its standard error, with the fixed effects pooled estimate and
# the limits within which 95% of study estimates would fall at each standard error
top <- max(se_iv, na.rm = TRUE) * 1.05
plot(rd, se_iv, ylim = c(top, 0), xlim = range(rd, rd_mh + c(-1, 1) * z * top, na.rm = TRUE),
     xlab = "Risk difference", ylab = "Standard error", main = "Bias assessment plot")
abline(v = rd_mh)
lines(rd_mh + c(-1, 0, 1) * z * top, c(top, 0, top))

# Then a forest plot for each model: a circle per study sized by its weight, its
# interval as a line, the pooled estimate as a diamond, the line of no effect and a
# dashed line at the pooled estimate; an excluded study has a row without an estimate
forest <- function(weight, pooled, lower, upper, title, label) {
  rows <- length(a):1
  op <- par(mar = c(5, 8, 4, 9))
  plot(NA, xlim = range(ci, lower, upper, 0, na.rm = TRUE), ylim = c(0, length(a) + 0.5), yaxt = "n",
       ylab = "", xlab = paste0("risk difference (", pct, " confidence interval)"), main = title)
  axis(2, at = c(rows, 0), labels = c(study, label), las = 1, tick = FALSE)
  axis(4, at = c(rows, 0), tick = FALSE, las = 1, cex.axis = 0.8,
       labels = c(ifelse(included, sprintf("%.3f (%.3f, %.3f)", rd, ci[, 1], ci[, 2]), "excluded"),
                  sprintf("%.3f (%.3f, %.3f)", pooled, lower, upper)))
  abline(v = 0)
  segments(pooled, 0, pooled, length(a), lty = 2)
  segments(ci[, 1], rows, ci[, 2], rows)
  points(rd, rows, pch = 16, col = "grey40", cex = 0.6 + 2 * sqrt(weight / max(weight)))
  polygon(c(lower, pooled, upper, pooled), c(0, 0.25, 0, -0.25), col = "grey60")
  par(op)
}
forest(w_mh, rd_mh, rd_mh - z * se_mh, rd_mh + z * se_mh,
       "Risk difference meta-analysis plot [fixed effects]", "combined [fixed]")
forest(w_dl, rd_dl, rd_dl - z * se_dl, rd_dl + z * se_dl,
       "Risk difference meta-analysis plot [random effects]", "combined [random]")

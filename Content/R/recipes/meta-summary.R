# StatsDirect recipe: Meta-analysis of summary statistics with their confidence limits, as the help shows it in R.
# From the help's R code (meta_analysis/summary.htm); the data and settings above come from the run.
# data: or = y, lower = ll_y, upper = ul_y, se_in = se_y, study = studies
# settings: confidence = gamma, type = type, use_ci = use_ci, exact_meta = metaExact

# Keep studies with an estimate and the supplied uncertainty measure.
keep <- if (!is.null(se_in)) complete.cases(or, se_in) else complete.cases(or, lower, upper)
if (any(!keep)) cat("(", sum(!keep), " other rows not used)\n", sep = "")
or <- or[keep]
se_in <- se_in[keep]
lower <- lower[keep]
upper <- upper[keep]
study <- study[keep]
if (is.null(study)) study <- paste("Study", seq_along(or))
# Summary data meta-analysis: the StatsDirect help example (the odds ratio of each of
# seven trials of aspirin after heart attack, Fleiss 1993, with its 95% confidence
# limits; the test workbook's Meta-analysis worksheet columns Odds Ratio, LCI, UCI and
# Study) in R
pct <- paste0(100 * confidence, "%")
k <- length(or)
z <- qnorm((1 + confidence) / 2)
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
one <- function(x) formatC(x, digits = 1, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}

# Base R has no meta-analysis function, so the report is built from the formulae.
# A ratio is analysed on the log scale: each study's standard error of the log odds
# ratio is recovered from its limits as their log difference over twice the normal
# deviate (had standard errors been given instead, the limits would be recovered
# from them the other way round), and the inverse variance weights follow. A
# difference is analysed as it is, with no effect at 0 rather than at 1.
ratio <- type %in% c("oddsRatio", "relativeRisk", "otherRatio")   # a ratio is pooled on the log scale, a difference as it is
stat <- c(oddsRatio = "Odds Ratio", relativeRisk = "Relative Risk", riskDifference = "Risk Difference",
          otherRatio = "* Ratio", otherDifference = "* Difference")[[type]]
null_value <- if (ratio) 1 else 0
y <- if (ratio) log(or) else or
# Limits selected the wrong way round, the upper before the lower, are put the right
# way round, as the report puts them
if (!is.null(lower)) { lower_in <- lower; lower <- pmin(lower_in, upper); upper <- pmax(lower_in, upper) }
se <- if (!is.null(se_in)) se_in else if (ratio) (log(upper) - log(lower)) / (2 * z) else (upper - lower) / (2 * z)
if (is.null(lower)) { lower <- if (ratio) exp(y - z * se) else y - z * se; upper <- if (ratio) exp(y + z * se) else y + z * se }
back <- if (ratio) exp else identity
w <- 1 / se^2
cat("Study ", stat, " SE  Approximate", pct, "CI\n")
for (i in 1:k) {
  cat(i, six(or[i]), six(se[i]), six(lower[i]), six(upper[i]), study[i], "\n")
}

# Fixed effects: the weighted mean of the log odds ratios, its standard error the
# root of the reciprocal of the total weight, transformed back to the ratio scale
pooled <- sum(w * y) / sum(w)
se_pooled <- 1 / sqrt(sum(w))
z_fixed <- pooled / se_pooled

# Cochran's Q about the pooled log odds ratio, then the DerSimonian-Laird moment
# estimate of the between studies variance, which inflates each study's variance
# for the random effects weights
q <- sum(w * (y - pooled)^2)
tau2 <- max(0, (q - (k - 1)) / (sum(w) - sum(w^2) / sum(w)))
w_dl <- 1 / (tau2 + se^2)
pooled_dl <- sum(w_dl * y) / sum(w_dl)
se_dl <- 1 / sqrt(sum(w_dl))
z_dl <- pooled_dl / se_dl

# The report's second table: each study's standardised effect, the log odds ratio on
# which the pooling is done, with its standard error on that scale and its share of
# the fixed and random weights
cat("Stratum  Standardized effect  Standard error  % Weights (fixed, random)\n")
for (i in 1:k) {
  cat(i, six(y[i]), six(se[i]), six(100 * w[i] / sum(w)),
      six(100 * w_dl[i] / sum(w_dl)), study[i], "\n")
}

cat("Fixed effects (inverse variance)\n")
cat("Pooled ", tolower(stat), " = ", six(back(pooled)), " (", pct, "CI = ",
    six(back(pooled - z * se_pooled)), " to ", six(back(pooled + z * se_pooled)), ")\n",
    sep = "")
cat("Z (test ", stat, " differs from ", null_value, ") = ", six(z_fixed), "  ",
    pv(2 * pnorm(-abs(z_fixed))), "\n", sep = "")

# I-squared = (Q - df) / Q, with the interval of the heterogeneity topic's default
# 'exact' option (the iterative method it credits to Hedges and Pigott, 2001): Q is
# treated as non-central chi-square and its distribution function at the observed Q
# is inverted for the non-centrality parameter lambda, the lower limit where that
# probability reaches the selected upper or lower tail probability (0 when even
# the central distribution gives less). Each limit becomes I-squared as
# lambda / (df + lambda).
cat("Non-combinability of studies\n")
dfree <- k - 1
cat("Cochran Q = ", six(q), "  (df = ", dfree, ")  ",
    pv(pchisq(q, dfree, lower.tail = FALSE)), "\n", sep = "")
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
  cat("I2 (inconsistency) = ", one(i2), "% (", pct, "CI = ",
      one(i2_ci[1]), "% to ", one(i2_ci[2]), "%)\n", sep = "")
# End of I-squared interval.

cat("Random effects (DerSimonian-Laird)\n")
cat("Pooled ", tolower(stat), " = ", six(back(pooled_dl)), " (", pct, "CI = ",
    six(back(pooled_dl - z * se_dl)), " to ", six(back(pooled_dl + z * se_dl)), ")\n",
    sep = "")
cat("Z (test ", stat, ") = ", six(z_dl), "  ", pv(2 * pnorm(-abs(z_dl))), "\n", sep = "")

# Bias indicators, which the report gives only with more than three studies. Begg
# and Mazumdar's test is Kendall's tau between each study's
# deviation from the pooled log odds ratio, standardised by its variance less the
# pooled variance, and that variance; with no ties among seven studies cor.test
# gives the exact two sided P (with tied standard errors it would give tau-b and a
# normal approximation, which the report corrects for continuity); the report marks
# the test as low in power when there are fewer than eleven studies
cat("Bias indicators\n")
# Egger's interval is at the level of the bias tests, twice the analysis's alpha
# (90% for a 95% analysis); as the report has it, there is no figure when every
# study has the same precision or the line fits every study exactly
bias_level <- 1 - 2 * (1 - confidence)
if (!(bias_level > 0 && bias_level < 1)) bias_level <- 0.9
if (k > 3) {
  dev <- (y - pooled) / sqrt(se^2 - se_pooled^2)
  kt <- cor.test(dev, se^2, method = "kendall", conf.level = confidence)
  cat("Begg-Mazumdar: Kendall's tau =", six(kt$estimate), " ", pv(kt$p.value),
      "(low power)\n")

  # Egger's test regresses each study's standardised effect (log odds ratio over its
  # standard error) on its precision (one over that standard error); the bias is the
  # intercept, judged by a t test on k - 2 degrees of freedom
  fit <- lm(I(y / se) ~ I(1 / se))
  if (diff(range(1 / se)) > 1e-12 * max(1 / se) && sum(residuals(fit)^2) > 1e-12 * sum((y / se)^2)) {
    bias <- coef(summary(fit))[1, ]
    ci <- confint(fit, level = bias_level)[1, ]
  } else {
    bias <- c(Estimate = NA, "Pr(>|t|)" = NA)
    ci <- c(NA, NA)
  }
  egger_figures <- unname(c(bias["Estimate"], ci, bias["Pr(>|t|)"]))
  cat("Egger: bias = ", six(bias["Estimate"]), " (", round(100 * bias_level, 2), "% CI = ", six(ci[1]),
      " to ", six(ci[2]), ")  ", pv(bias["Pr(>|t|)"]), "\n", sep = "")
} else cat("Bias indicators need more than three studies with an estimate\n")

# The report's bias assessment (funnel) plot: each log odds ratio against its
# standard error, the axis reversed so that the 95% cone about the pooled log odds
# ratio opens downwards
se_top <- max(se) * 1.05
plot(y, se, ylim = c(se_top, 0), xlim = range(y, pooled + c(-1, 1) * z * se_top),
     xlab = if (ratio) paste0("Log(", tolower(stat), ")") else tolower(stat),
     ylab = "Standard error", main = "Bias assessment plot")
abline(v = pooled)
lines(pooled + c(-1, 0, 1) * z * se_top, c(se_top, 0, se_top))

# The two forest plots: each study's estimate (the symbol size growing with its
# weight) with its interval, on a log scale for a ratio, the line of no effect at 1
# for a ratio or 0 for a difference, and the pooled estimate as a diamond at the foot
forest <- function(weights, est, se_est, title) {
  yy <- rev(seq_len(k)) + 1
  limits <- back(est + c(-1, 1) * z * se_est)
  par(mar = c(5, 8, 4, 8))
  plot(or, yy, log = if (ratio) "x" else "", xlim = range(lower, upper, limits, null_value),
       ylim = c(0.5, k + 1.5), pch = 15, cex = 0.5 + 2 * sqrt(weights / max(weights)), yaxt = "n",
       ylab = "", xlab = paste0(tolower(stat), " (", pct, " confidence interval)"), main = title)
  segments(lower, yy, upper, yy)
  polygon(c(limits[1], back(est), limits[2], back(est)), c(1, 1.3, 1, 0.7), col = "grey")
  segments(back(est), 1, back(est), k + 1, lty = 3)
  abline(v = null_value)
  axis(2, at = c(yy, 1), labels = c(study, "combined"), las = 1, tick = FALSE)
  axis(4, at = c(yy, 1), las = 1, tick = FALSE,
       labels = sprintf("%.2f (%.2f, %.2f)", c(or, back(est)), c(lower, limits[1]),
                        c(upper, limits[2])))
}
forest(w, pooled, se_pooled, "Summary meta-analysis plot [fixed effects]")
forest(w_dl, pooled_dl, se_dl, "Summary meta-analysis plot [random effects]")

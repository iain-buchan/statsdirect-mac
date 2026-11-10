# StatsDirect recipe: Correlation meta-analysis, as the help shows it in R.
# From the help's R code (meta_analysis/correlation.htm); the data and settings above come from the run.
# data: r = r, n = n, study = studies
# settings: confidence = gamma, exact_meta = metaExact

# Correlation meta-analysis: the StatsDirect help example (eight studies of the
# relationship between drug misuse and delinquency; the test workbook's meta worksheet
# columns Correlation and Sample size) in R

# Base R has no meta-analysis function, so the Hedges-Olkin method is computed as the
# report describes it: each correlation becomes Fisher's z (atanh), whose variance is
# 1 / (n - 3); the studies are pooled on the z scale with weights n - 3, and the pooled
# z and its limits are transformed back to correlations (tanh)
pct <- paste0(100 * confidence, "%")
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
# Omit incomplete studies, including their labels, before pooling.
keep <- complete.cases(r, n)
if (any(!keep)) cat("(", sum(!keep), " other rows not used)\n", sep = "")
r <- r[keep]
n <- n[keep]
k <- length(r)
if (k == 0) stop("At least one study must have a correlation and sample size")
study <- study[keep]
if (is.null(study)) study <- paste("study", seq_len(k))
blank <- is.na(study) | !nzchar(trimws(study))
study[blank] <- paste("study", which(blank))
z <- atanh(r)
v <- 1 / (n - 3)
cit <- qnorm((1 + confidence) / 2)
lower <- tanh(z - cit * sqrt(v))
upper <- tanh(z + cit * sqrt(v))
w <- 1 / v
z_fixed <- sum(w * z) / sum(w)
se_fixed <- 1 / sqrt(sum(w))
fixed <- tanh(z_fixed + c(0, -1, 1) * cit * se_fixed)

# Cochran's Q on the z scale, and the DerSimonian-Laird moment estimate of the
# between-studies variance that the random effects weights add to each variance
Q <- if (k > 1) sum(w * (z - z_fixed)^2) else 0
df <- k - 1
spread <- sum(w) - sum(w^2) / sum(w)
tau2 <- if (k < 2 || spread == 0) 0 else max(0, (Q - df) / spread)
w_random <- 1 / (v + tau2)
z_random <- sum(w_random * z) / sum(w_random)
se_random <- 1 / sqrt(sum(w_random))
random <- tanh(z_random + c(0, -1, 1) * cit * se_random)

# The report's two tables: each correlation with its approximate 95% interval, then
# its Fisher z, variance and percentage weights (fixed effects, random effects, and by
# sample size as the Schmidt-Hunter method below weights)
print(data.frame(Study = 1:k, Size = n, Correlation = r, Lower = six(lower),
                 Upper = six(upper), Label = study), row.names = FALSE)
# (study 1's variance is exactly 1/128, printed 0.007812 here and 0.007813 by the
# program, which squares the standard error)
print(data.frame(Study = 1:k, Fisher_z = six(z), Variance = six(v),
                 Fixed = six(100 * w / sum(w)),
                 Random = six(100 * w_random / sum(w_random)),
                 Size = six(100 * n / sum(n)), Label = study), row.names = FALSE)

cat("Hedges-Olkin fixed effects\n")
cat("Pooled correlation = ", six(fixed[1]), " (", pct, " CI = ", six(fixed[2]), " to ",
    six(fixed[3]), ")\n", sep = "")
cat("Z (test correlation differs from 0) =", six(z_fixed / se_fixed), " ",
    pv(2 * pnorm(-abs(z_fixed / se_fixed))), "\n")

cat("Non-combinability of studies\n")
cat("Cochran Q = ", six(Q), "  (df = ", df, ")  ",
    pv(if (k > 1) pchisq(Q, df, lower.tail = FALSE) else NA_real_), "\n", sep = "")
cat("Moment-based estimate of between studies variance =", six(tau2), "\n")
one <- function(x) formatC(x, digits = 1, format = "f", drop0trailing = TRUE)
# I-squared interval: recorded exact/test-based choice.
# Older records have no preference: retain the non-central interval they used.
if (is.null(exact_meta)) exact_meta <- TRUE
df_i2 <- k - 1
i2 <- if (k < 2) NA_real_ else if (Q == 0) 0 else max(0, 100 * (Q - df_i2) / Q)
i2_ci <- rep(NA_real_, 2)
if (k >= 2 && confidence > 0 && confidence < 1) {
  if (isTRUE(exact_meta)) {
    # Invert the non-central chi-square CDF (Hedges & Pigott, 2001).
    lambda <- function(p) {
      if (pchisq(Q, df_i2) <= p) 0 else
        uniroot(function(l) pchisq(Q, df_i2, ncp = l) - p,
                c(0, 10 * Q + 100), tol = 1e-10)$root
    }
    lim <- c(lambda((1 + confidence) / 2), lambda((1 - confidence) / 2))
    i2_ci <- 100 * lim / (df_i2 + lim)
  } else if (k >= 3 || Q > k) {
    # Test-based log(H) interval (Higgins & Thompson, 2002), as in
    # StatsDirect's MIT Meta.IsquareNcc. H is at least one; with two studies
    # only Q > k gives a standard error (the first form below).
    h2 <- max(1, Q / df_i2)
    se_log_h <- if (Q > k) 0.5 * (log(Q) - log(df_i2)) /
      (sqrt(2 * Q) - sqrt(2 * k - 3)) else
      sqrt((1 - 1 / (3 * (k - 2)^2)) / (2 * (k - 2)))
    h_limits <- exp(log(sqrt(h2)) + c(-1, 1) * cit * se_log_h)
    h_limits[1] <- max(1, h_limits[1])
    i2_ci <- 100 * (1 - 1 / h_limits^2)
  }
}
if (k < 2) cat("I-squared not calculated: at least two studies are required.\n") else if (anyNA(i2_ci))
  cat("I-squared (inconsistency) =", one(i2), "% (interval unavailable for this number of studies and confidence level)\n") else
  cat("I-squared (inconsistency) = ", one(i2), "% (", pct, " CI = ",
      one(i2_ci[1]), "% to ", one(i2_ci[2]), "%)\n", sep = "")
# End of I-squared interval.

cat("Hedges-Olkin random effects\n")
cat("Pooled correlation = ", six(random[1]), " (", pct, " CI = ", six(random[2]), " to ",
    six(random[3]), ")\n", sep = "")
cat("Z (test correlation differs from 0) =", six(z_random / se_random), " ",
    pv(2 * pnorm(-abs(z_random / se_random))), "\n")

# Begg-Mazumdar: Kendall's rank correlation between each study's standardised
# deviation from the fixed effects pooled z and its variance. With no tied variances
# cor.test gives the exact two sided P, as the report does; with tied sample sizes the
# report instead gives tau-b and a continuity corrected normal approximation, which is
# cor.test(..., exact = FALSE, continuity = TRUE). The test has low power with fewer
# than 11 studies, as the report notes.
# The report gives the bias indicators only with more than three studies.
cat("Bias indicators\n")
# Egger's interval is at the level of the bias tests, twice the analysis's alpha
# (90% for a 95% analysis); as the report has it, there is no figure when every
# study has the same precision or the line fits every study exactly
bias_level <- 1 - 2 * (1 - confidence)
if (!(bias_level > 0 && bias_level < 1)) bias_level <- 0.9
if (k > 3) {
  deviation <- (z - z_fixed) / sqrt(v - 1 / sum(w))
  tied <- anyDuplicated(deviation) > 0 || anyDuplicated(v) > 0
  bm <- cor.test(deviation, v, method = "kendall", exact = if (tied) FALSE else NULL,
                 continuity = TRUE, conf.level = confidence)
  cat("Begg-Mazumdar: Kendall's tau =", six(bm$estimate), " ", pv(bm$p.value),
      if (k < 11 && !is.na(bm$estimate)) "(low power)\n" else "\n")

  # Egger: each standardised effect (z / se) regressed on its precision (1 / se); the
  # bias is the intercept, with a t test on k - 2 degrees of freedom
  egger <- lm(I(z / sqrt(v)) ~ I(1 / sqrt(v)))
  if (diff(range(1 / sqrt(v))) > 1e-12 * max(1 / sqrt(v)) &&
      sum(residuals(egger)^2) > 1e-12 * sum((z / sqrt(v))^2)) {
    egger_ci <- confint(egger, level = bias_level)[1, ]
    egger_figures <- unname(c(coef(egger)[1], egger_ci, summary(egger)$coefficients[1, 4]))
  } else egger_figures <- rep(NA, 4)
  cat("Egger: bias = ", six(egger_figures[1]), " (", round(100 * bias_level, 2), "% CI = ", six(egger_figures[2]), " to ",
      six(egger_figures[3]), ")  ", pv(egger_figures[4]), "\n", sep = "")
} else cat("Bias indicators need more than three studies with an estimate\n")

# Schmidt-Hunter: the mean correlation weighted by sample size, the variance of the
# correlations about it, the part of that variance expected from sampling error alone
# and the remainder, attributed to real differences between the populations studied
wmc <- sum(n * r) / sum(n)
var_r <- sum(n * (r - wmc)^2) / sum(n)
var_e <- (1 - wmc^2)^2 / (mean(n) - 1)
var_p <- max(0, var_r - var_e)
se_wmc <- sqrt(var_r / k)
sh <- wmc + c(0, -1, 1) * cit * se_wmc
cat("Schmidt-Hunter\n")
cat("Weighted mean correlation (", pct, " CI): ", six(sh[1]), " (", six(sh[2]), " to ",
    six(sh[3]), ")\n", sep = "")
cat("Z (test correlation differs from 0) =", six(wmc / se_wmc),
    pv(2 * pnorm(-abs(wmc / se_wmc))), "\n")
cat("Observed variance across studies:", six(var_r), "\n")
cat("Variance due to sampling error:", six(var_e), "\n")
cat("Variance in the population correlations:", six(var_p), "\n")
# the credibility interval spreads the population correlations about the mean by
# their standard deviation, the square root of var_p (the report leaves it out when
# that is zero)
cat(pct, "Credibility interval for weighted mean correlation:",
    six(wmc - cit * sqrt(var_p)), "to", six(wmc + cit * sqrt(var_p)), "\n")
cat("Indicators of homogeneity/heterogeneity:\n")
cat("1. Residual standard deviation (should be smaller than 1/4 WMC: ", six(wmc / 4),
    "): ", six(sqrt(var_p)), "\n", sep = "")
cat("2. Percent of observed variance accounted for by sampling error",
    "(should be at least 75%):", six(100 * var_e / var_r), "\n")
het <- k * var_r / var_e
cat("3. Chi-square test of heterogeneity:", six(het),
    pv(if (k > 1) pchisq(het, df, lower.tail = FALSE) else NA_real_), "\n")

# The report's charts: the bias assessment (funnel) plot of each study's Fisher z
# against its standard error, the most precise studies at the top, with the fixed
# effects pooled z and the limits within which 95% of studies of each precision would
# fall; then a forest plot for each of the three pooled correlations, the studies'
# squares scaled by the square root of their fixed effects weights
se <- sqrt(v)
top <- max(se) * 1.05
plot(z, se, ylim = c(top, 0), xlim = z_fixed + c(-1, 1) * cit * top,
     xlab = "Fisher Z(Correlation)", ylab = "Standard error",
     main = "Bias assessment plot", pch = 16)
abline(v = z_fixed)
lines(z_fixed + cit * c(0, top), c(0, top))
lines(z_fixed - cit * c(0, top), c(0, top))
forest <- function(pooled, title) {
  y <- rev(seq_len(k + 1))   # study 1 at the top, the pooled correlation at the foot
  par(mar = c(5, 8, 4, 2))
  # the axis runs from -1 when a study or limit is negative, as the program draws it
  left <- if (min(lower, pooled[2]) < 0) -1 else 0
  right <- if (max(upper, pooled[3]) <= 0) 0 else 1
  plot(c(r, pooled[1]), y, xlim = c(left, right), yaxt = "n", ylab = "",
       xlab = paste0("Correlation (", pct, " confidence interval)"), main = title,
       pch = c(rep(15, k), 18), cex = c(2 * sqrt(w / max(w)), 3))
  segments(c(lower, pooled[2]), y, c(upper, pooled[3]), y)
  abline(v = pooled[1], lty = 2)
  axis(2, at = y, labels = c(study, "combined"), las = 1, tick = FALSE)
}
forest(fixed, "Correlation (Hedges-Olkin fixed effects) meta-analysis plot")
forest(random, "Correlation (Hedges-Olkin random effects) meta-analysis plot")
forest(sh, "Correlation (Schmidt-Hunter) meta-analysis plot")
# StatsDirect recipe: Paired t test with its agreement analysis, as the help shows it in R.
# From the help's R code (parametric_methods/paired_t.htm); the data and settings above come from the run.
# data: before, after
# settings: confidence = gamma, agreement = doAgreement
# hand-edited: the selected confidence level, agreement option and complete pairs come from the run

# Paired t test: the StatsDirect help example (peak expiratory flow rate before
# and after a walk on a cold day in 9 asthmatics) in R

# R's standard test gives t, df, the two sided P and the confidence interval for
# the mean difference, as StatsDirect reports them.
paired <- !is.null(after)
if (paired) {
  keep <- complete.cases(before, after)
  before <- before[keep]
  after <- after[keep]
  d <- before - after
} else {
  d <- before[!is.na(before)]   # one column already contains the differences
}
if (is.null(confidence) || !is.finite(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95
pct <- paste0(100 * confidence, "%")
n <- length(d)
if (n >= 2 && sd(d) == 0) {
  # R's t.test rejects constant differences. The report's limiting result has
  # a point interval, infinite t for a nonzero mean, and undefined t/P at zero.
  t <- mean(d) / 0
  r <- structure(list(statistic = c(t = t), parameter = c(df = n - 1),
    p.value = 2 * pt(-abs(t), n - 1),
    conf.int = structure(rep(mean(d), 2), conf.level = confidence),
    estimate = c("mean difference" = mean(d)), null.value = c("mean difference" = 0),
    stderr = 0, alternative = "two.sided", method = "Paired t-test (constant differences)",
    data.name = "Recorded differences"), class = "htest")
  if (mean(d) == 0) cat("All differences are zero: t and P are undefined.\n")
} else {
  r <- if (paired) t.test(before, after, paired = TRUE, conf.level = confidence) else
    t.test(d, mu = 0, conf.level = confidence)
}
print(r)

# The report's other lines, to 6 decimal places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
n <- length(d)
cat(sprintf("Mean of differences = %s  (n = %d)\n", six(mean(d)), n))
cat("Standard deviation =", six(sd(d)), "  Standard error =", six(sd(d) / sqrt(n)),
    "\n")
cat(pct, "CI =", six(r$conf.int[1]), "to", six(r$conf.int[2]), "\n")
cat("df =", r$parameter, "  t =", six(r$statistic), "\n")
cat(sprintf("One sided P = %.4f   Two sided P = %.4f\n", r$p.value / 2, r$p.value))

# Power at the selected significance level to detect the mean difference and sd
# seen, from the noncentral t distribution; strict = TRUE counts rejections in
# both tails, as StatsDirect does.
alpha <- 1 - confidence
if (sd(d) == 0) {
  pw <- list(power = NA_real_)
  cat(sprintf("Power (for %g%% significance) not calculated: zero standard deviation\n", 100 * alpha))
} else {
  pw <- power.t.test(n = n, delta = mean(d), sd = sd(d), sig.level = alpha,
                     type = "paired", strict = TRUE)
  cat(sprintf("Power (for %g%% significance) = %.2f%%\n", 100 * alpha, 100 * pw$power))
}

# StatsDirect's agreement analysis option adds the 95% limits of agreement of
# Bland and Altman: the mean difference plus or minus 1.96 standard deviations.
if (!exists("agreement") || is.null(agreement)) agreement <- paired # older saved results
if (paired && isTRUE(agreement)) {
  loa <- mean(d) + c(-1, 1) * qnorm((1 + confidence) / 2) * sd(d)
  cat(pct, "Limits of agreement =", six(loa[1]), "to", six(loa[2]), "\n")

# The agreement plot that follows in the report: each difference against the mean
# of its pair, with the mean difference (black) and the limits of agreement (red)
  if (sd(d) > 0) {
  if (!exists("before_title")) before_title <- "before"
  if (!exists("after_title")) after_title <- "after"
  plot((before + after) / 2, d, xlab = paste0("Mean ((", before_title, " + ", after_title, ") / 2)"),
       ylab = paste0("Difference (", before_title, " - ", after_title, ")"), ylim = range(d, loa))
  abline(h = mean(d))
  abline(h = loa, col = "red")
  mtext(paste0("Mean difference and ", pct, " limits of agreement"),
        side = 3, line = 0.5, cex = 0.8)
  } else cat("No agreement plot: the differences do not vary.\n")
}

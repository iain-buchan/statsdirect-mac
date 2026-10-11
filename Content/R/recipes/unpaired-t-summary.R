# StatsDirect recipe: Unpaired t test from the two samples' summary figures (sizes, means and standard deviations), with equal and unequal variances, as the help shows the test in R.
# From the help's R code (parametric_methods/unpaired_t.htm); the settings above come from the run.
# settings: n1 = nx1, xbar1 = um1, s1 = sd1, n2 = nx2, xbar2 = um2, s2 = sd2, confidence = gamma
# hand-edited: the tests are rebuilt from the summary figures, since R's t.test and var.test take the observations themselves

# R's t.test and var.test take the observations; from each sample's size, mean and standard
# deviation the same tests are rebuilt here and printed as R prints them: first assuming
# equal variances and then not (R's default, the Welch test, whose t and df are StatsDirect's
# t(d) and its fractional df), each with t, df, the two sided P and the confidence interval.
delta <- xbar1 - xbar2
htest <- function(t, df, se, method) {
  ci <- delta + c(-1, 1) * qt((1 + confidence) / 2, df) * se
  attr(ci, "conf.level") <- confidence
  structure(list(statistic = c(t = t), parameter = c(df = df), p.value = 2 * pt(-abs(t), df),
                 conf.int = ci, estimate = c("mean of x" = xbar1, "mean of y" = xbar2),
                 null.value = c("difference in means" = 0), stderr = se, alternative = "two.sided",
                 method = method, data.name = "the summary figures"), class = "htest")
}
pooled <- sqrt(((n1 - 1) * s1^2 + (n2 - 1) * s2^2) / (n1 + n2 - 2))
se_equal <- pooled * sqrt(1 / n1 + 1 / n2)
equal <- htest(delta / se_equal, n1 + n2 - 2, se_equal, " Two Sample t-test")
print(equal)
v1 <- s1^2 / n1
v2 <- s2^2 / n2
se_welch <- sqrt(v1 + v2)
unequal <- htest(delta / se_welch, (v1 + v2)^2 / (v1^2 / (n1 - 1) + v2^2 / (n2 - 1)), se_welch,
                 "Welch Two Sample t-test")
print(unequal)

# The F test that StatsDirect uses to compare the variances, rebuilt from the standard deviations
ratio <- s1^2 / s2^2
fci <- ratio / qf(c((1 + confidence) / 2, (1 - confidence) / 2), n1 - 1, n2 - 1)
attr(fci, "conf.level") <- confidence
f <- structure(list(statistic = c(F = ratio), parameter = c("num df" = n1 - 1, "denom df" = n2 - 1),
                    p.value = 2 * min(pf(ratio, n1 - 1, n2 - 1), pf(ratio, n1 - 1, n2 - 1, lower.tail = FALSE)),
                    conf.int = fci, estimate = c("ratio of variances" = ratio),
                    null.value = c("ratio of variances" = 1), alternative = "two.sided",
                    method = "F test to compare two variances", data.name = "the summary figures"),
               class = "htest")
print(f)

# The report's other lines, to 6 decimal places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pct <- paste0(100 * confidence, "%")
cat(sprintf("Mean of the first sample = %s  (n = %d)\n", six(xbar1), n1))
cat(sprintf("Mean of the second sample = %s  (n = %d)\n", six(xbar2), n2))
report <- function(r, label, t) {
  cat(label, "\n")
  cat("Combined standard error =", six(delta / r$statistic), "  df =",
      six(r$parameter), " ", t, "=", six(r$statistic), "\n")
  cat(sprintf("One sided P = %.4f   Two sided P = %.4f\n", r$p.value / 2, r$p.value))
  cat(pct, "confidence interval for difference between means =", six(r$conf.int[1]),
      "to", six(r$conf.int[2]), "\n")
  # Power of a two sided test at the 5% level to detect the difference seen, from
  # the noncentral t distribution: the noncentrality parameter is the t observed
  tc <- qt(0.975, r$parameter)
  pw <- pt(-tc, r$parameter, ncp = r$statistic) +
        pt(tc, r$parameter, ncp = r$statistic, lower.tail = FALSE)
  cat(sprintf("Power (for 5%% significance) = %.2f%%\n", 100 * pw))
}
report(equal, "Assuming equal variances", "t")
report(unequal, "Assuming unequal variances", "t(d)")
cat("Two sided F test is", if (f$p.value < 0.05) "significant" else "not significant",
    "\n")

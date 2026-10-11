# StatsDirect recipe: Unpaired t test, with equal and unequal variances, as the help shows it in R.
# From the help's R code (parametric_methods/unpaired_t.htm); the data and settings above come from the run.
# data: high, low
# settings: confidence = gamma
# hand-edited: the confidence level and the data come from the run, as the header says

# Unpaired t test: the StatsDirect help example (Armitage and Berry 1994, weight
# gain of 19 rats on high or low protein diets) in R

# R's standard test, first assuming equal variances and then not (R's default,
# the Welch test, whose t and df are StatsDirect's t(d) and its fractional df).
# Each gives t, df, the two sided P and the confidence interval.
pct <- paste0(100 * confidence, "%")
equal <- t.test(high, low, var.equal = TRUE, conf.level = confidence)
print(equal)
unequal <- t.test(high, low, conf.level = confidence)
print(unequal)

# The F test that StatsDirect uses to compare the variances
f <- var.test(high, low)
print(f)

# The report's other lines, to 6 decimal places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
cat(sprintf("Mean of High Protein = %s  (n = %d)\n", six(mean(high)), length(high)))
cat(sprintf("Mean of Low Protein = %s  (n = %d)\n", six(mean(low)), length(low)))
delta <- mean(high) - mean(low)
report <- function(r, label, t) {
  cat(label, "\n")
  cat("Combined standard error =", six(delta / r$statistic), "  df =",
      six(r$parameter), " ", t, "=", six(r$statistic), "\n")
  cat(sprintf("One sided P = %.4f   Two sided P = %.4f\n", r$p.value / 2, r$p.value))
  cat(pct, "confidence interval for difference between means =", six(r$conf.int[1]),
      "to", six(r$conf.int[2]), "\n")
  # Power of a two sided test at the 5% level to detect the difference seen, from
  # the noncentral t distribution: the noncentrality parameter is the t observed
  tc <- qt((1 + confidence) / 2, r$parameter)
  pw <- pt(-tc, r$parameter, ncp = r$statistic) +
        pt(tc, r$parameter, ncp = r$statistic, lower.tail = FALSE)
  cat(sprintf("Power (for 5%% significance) = %.2f%%\n", 100 * pw))
}
report(equal, "Assuming equal variances", "t")
report(unequal, "Assuming unequal variances", "t(d)")
cat("Two sided F test is", if (f$p.value < 0.05) "significant" else "not significant",
    "\n")
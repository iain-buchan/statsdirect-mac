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
f <- var.test(high, low, conf.level = confidence)
print(f)

# The report's other lines, to 6 decimal places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
if (!exists("high_title")) high_title <- "high"
if (!exists("low_title")) low_title <- "low"
cat(sprintf("Mean of %s = %s  (n = %d)\n", high_title, six(mean(high)), length(high)))
cat(sprintf("Mean of %s = %s  (n = %d)\n", low_title, six(mean(low)), length(low)))
delta <- mean(high) - mean(low)
report <- function(r, label) {
  cat(label, "\n")
  cat("Combined standard error =", six(r$stderr), "\n")
  cat(sprintf("One sided P = %.4f\n", r$p.value / 2))
  # Power of a two sided test at the 5% level to detect the difference seen, from
  # the noncentral t distribution: the noncentrality parameter is the t observed
  tc <- qt(0.975, r$parameter)
  pw <- pt(-tc, r$parameter, ncp = r$statistic) +
        pt(tc, r$parameter, ncp = r$statistic, lower.tail = FALSE)
  cat(sprintf("Power (for 5%% significance) = %.2f%%\n", 100 * pw))
}
report(equal, "Assuming equal variances")
report(unequal, "Assuming unequal variances")
cat("Two sided F test is", if (f$p.value < 0.05) "significant" else "not significant",
    "\n")

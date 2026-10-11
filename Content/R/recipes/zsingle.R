# StatsDirect recipe: Single sample z test, as the help shows it in R.
# From the help's R code (parametric_methods/z_normal.htm); the data and settings above come from the run.
# data: speed
# settings: mu = popmean, confidence = gamma

# Normal distribution (z) tests: the StatsDirect help example (Michelson's 100
# measurements of the speed of light in air, millions of metres per second) in R
pct <- paste0(100 * confidence, "%")
n <- length(speed)

# R has no z test among its standard functions (with a sample this large t.test
# gives almost the same answers), so the report's lines are calculated here.
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else paste("P =", formatC(p, digits = 4, format = "f"))
}
z <- qnorm((1 + confidence) / 2)
cat("Sample mean =", six(mean(speed)), "  Sample size n =", n,
    "  Sample sd =", six(sd(speed)), "\n")

# Single sample test, with the population sd not known: the sample sd is used
se <- sd(speed) / sqrt(n)
cat(pct, "confidence interval for mean difference =", six(mean(speed) - mu - z * se),
    "to", six(mean(speed) - mu + z * se), "\n")
dev <- (mean(speed) - mu) / se
cat("Standard normal deviate (z) =", six(dev), "\n")
cat("One sided", pv(pnorm(-abs(dev))), "  Two sided", pv(2 * pnorm(-abs(dev))), "\n")

# For lognormal data: the geometric mean, with the reference range exp(mean of
# the logs plus or minus z times their sd)
lg <- log(speed)
cat("Geometric mean =", six(exp(mean(lg))), " (", pct, "reference range =",
    six(exp(mean(lg) - z * sd(lg))), "to", paste0(six(exp(mean(lg) + z * sd(lg))), ")"),
    "\n")

# Two independent samples: the first and last 50 measurements
first <- speed[1:50]
last <- speed[51:100]
cat("First 50:  Mean =", six(mean(first)), "  Variance =", six(var(first)),
    "  Size =", length(first), "\n")
cat("Last 50:  Mean =", six(mean(last)), "  Variance =", six(var(last)),
    "  Size =", length(last), "\n")
se2 <- sqrt(var(first) / length(first) + var(last) / length(last))
cat("Combined standard error =", six(se2), "\n")
d <- mean(first) - mean(last)
cat(pct, "confidence interval for difference between means =", six(d - z * se2), "to",
    six(d + z * se2), "\n")
dev2 <- d / se2
cat("Standard normal deviate (z) =", six(dev2), "\n")
cat("One sided", pv(pnorm(-abs(dev2))), "  Two sided", pv(2 * pnorm(-abs(dev2))), "\n")
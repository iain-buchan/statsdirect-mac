# StatsDirect recipe: Single sample t test against a population mean, as the help shows it in R.
# From the help's R code (parametric_methods/single_sample_t.htm); the data and settings above come from the run.
# data: bp
# settings: mu = population-mean, confidence = gamma
# hand-edited: the confidence level and the data come from the run, as the header says

# Single sample t test: the StatsDirect help example (resting systolic blood
# pressure of 20 first year resident doctors) in R
bp <- bp[!is.na(bp)]
if (is.null(confidence) || !is.finite(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95
pct <- paste0(100 * confidence, "%")
n <- length(bp)

# R's standard test gives t, df, the two sided P and a 95% confidence interval for
# the mean. StatsDirect's interval is for the difference between the sample and
# population means, so its limits are these less 120.
r <- t.test(bp, mu = mu, conf.level = confidence)
print(r)

# The report's other lines, to 6 decimal places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
cat("Sample mean =", six(mean(bp)), "  Sample size n =", n,
    "  Sample sd =", six(sd(bp)), "\n")
cat(pct, "confidence interval for mean difference =", six(r$conf.int[1] - mu), "to",
    six(r$conf.int[2] - mu), "\n")
cat(sprintf("One sided P = %.4f\n", r$p.value / 2))

# Power at the selected significance level to detect the difference and sd seen,
# from the noncentral t distribution; strict = TRUE counts rejections in both
# tails, as StatsDirect does.
alpha <- 1 - confidence
pw <- power.t.test(n = n, delta = mean(bp) - mu, sd = sd(bp), sig.level = alpha,
                   type = "one.sample", strict = TRUE)
cat(sprintf("Power (for %g%% significance) = %.2f%%\n", 100 * alpha, 100 * pw$power))

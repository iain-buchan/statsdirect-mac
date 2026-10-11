# StatsDirect recipe: Single sample t test from its summary figures (n, mean and standard deviation) against a population mean, as the help shows the test in R.
# From the help's R code (parametric_methods/single_sample_t.htm); the settings above come from the run.
# settings: n = nx, xbar = mu, s = sd1, mu0 = mu0, confidence = gamma
# hand-edited: the test is rebuilt from the summary figures, since R's t.test takes the observations themselves

# R's t.test takes the observations; from their number n, mean xbar and standard deviation s
# the same test is rebuilt here and printed as t.test prints it: t, df, the two sided P and
# the confidence interval for the mean. StatsDirect's interval is for the difference between
# the sample and population means, so its limits are these less mu0.
se <- s / sqrt(n)
df <- n - 1
t <- (xbar - mu0) / se
ci <- xbar + c(-1, 1) * qt((1 + confidence) / 2, df) * se
attr(ci, "conf.level") <- confidence
r <- structure(list(statistic = c(t = t), parameter = c(df = df), p.value = 2 * pt(-abs(t), df),
                    conf.int = ci, estimate = c("mean of x" = xbar), null.value = c(mean = mu0),
                    stderr = se, alternative = "two.sided", method = "One Sample t-test",
                    data.name = "the summary figures"), class = "htest")
print(r)

# The report's other lines, to 6 decimal places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pct <- paste0(100 * confidence, "%")
cat("Sample mean =", six(xbar), "  Sample size n =", n, "  Sample sd =", six(s), "\n")
cat(pct, "confidence interval for mean difference =", six(r$conf.int[1] - mu0), "to",
    six(r$conf.int[2] - mu0), "\n")
cat("df =", r$parameter, "  t =", six(r$statistic), "\n")
cat(sprintf("One sided P = %.4f   Two sided P = %.4f\n", r$p.value / 2, r$p.value))

# Power of a two sided test at the 5% level to detect the difference and sd seen, from the
# noncentral t distribution; strict = TRUE counts rejections in both tails, as StatsDirect does.
pw <- power.t.test(n = n, delta = xbar - mu0, sd = s, sig.level = 0.05,
                   type = "one.sample", strict = TRUE)
cat(sprintf("Power (for 5%% significance) = %.2f%%\n", 100 * pw$power))

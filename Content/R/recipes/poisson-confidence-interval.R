# StatsDirect recipe: Poisson confidence interval of a mean count, as the help shows it in R.
# From the help's R code (parametric_methods/poisson_ci.htm); the data and settings above come from the run.
# data: counts
# settings: confidence = gamma

# Poisson confidence interval: the StatsDirect help example (patients arriving at
# a reception desk in 23 five minute intervals) in R
pct <- paste0(100 * confidence, "%")
n <- length(counts)

# R's standard function takes the total count as one Poisson observation over a
# time base of n intervals, so its event rate is the mean count per interval and
# its confidence interval, from the chi-square distribution, has the limits
# StatsDirect reports.
r <- poisson.test(sum(counts), n, conf.level = confidence)
print(r)

# The report's lines, to 6 decimal places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
cat("Size =", n, "  Mean =", six(mean(counts)), "\n")
cat("Exact two sided", pct, "CI =", six(r$conf.int[1]), "to", six(r$conf.int[2]), "\n")
# StatsDirect also gives the one sided 95% lower and upper limits, which are the
# ends of a two sided 90% interval
ci <- poisson.test(sum(counts), n, conf.level = 2 * confidence - 1)$conf.int
cat("Exact one sided", pct, "confidence limits: lower ", six(ci[1]), ", upper ", six(ci[2]),
    "\n", sep = "")
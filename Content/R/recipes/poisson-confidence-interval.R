# StatsDirect recipe: Poisson confidence interval of a mean count, as the help shows it in R.
# From the help's R code (parametric_methods/poisson_ci.htm); the data and settings above come from the run.
# data: counts
# repeat: data
# settings: confidence = gamma

# Poisson confidence interval: the StatsDirect help example (patients arriving at
# a reception desk in 23 five minute intervals) in R
counts <- counts[!is.na(counts)]
if (is.null(confidence) || !is.finite(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95
pct <- paste0(100 * confidence, "%")
n <- length(counts)
if (!n || any(counts < 0)) {
  r <- NULL
  ci <- rep(NA_real_, 2)
  cat("Poisson interval not calculated: use nonnegative counts with at least one observation.\n")
} else {

# R's standard function takes the total count as one Poisson observation over a
# time base of n intervals, so its event rate is the mean count per interval and
# its confidence interval, from the chi-square distribution, has the limits
# StatsDirect reports.
if (all(counts == floor(counts))) {
  r <- poisson.test(sum(counts), n, conf.level = confidence)
  print(r)
} else {
  # Native reports warn about fractional counts but still give gamma limits.
  cat("Warning: source data are not integers.\n")
  total <- sum(counts)
  r <- list(conf.int = c(if (total == 0) 0 else qgamma((1 - confidence) / 2, total),
                         qgamma((1 + confidence) / 2, total + 1)) / n)
}

# The report's lines, to 6 decimal places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
cat("Size =", n, "  Mean =", six(mean(counts)), "\n")
cat("Exact two sided", pct, "CI =", six(r$conf.int[1]), "to", six(r$conf.int[2]), "\n")
# StatsDirect also gives the one sided 95% lower and upper limits, which are the
# ends of a two sided 90% interval
ci <- if (confidence <= 0.5) rep(NA_real_, 2) else
  c(if (sum(counts) == 0) 0 else qgamma(1 - confidence, sum(counts)),
    qgamma(confidence, sum(counts) + 1)) / n
cat("Exact one sided", pct, "confidence limits: lower ", six(ci[1]), ", upper ", six(ci[2]),
    "\n", sep = "")
}

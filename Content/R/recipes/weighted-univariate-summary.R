# StatsDirect recipe: Weighted descriptive statistics of a column, as the help shows them in R.
# From the help's R code (basic_descriptive_statistics/univariate_summary.htm); the data and settings above come from the run.
# data: value = data, weight = weights
# settings: confidence = gamma

# Weighted univariate summary: five values with weights, as a second example.
# StatsDirect first scales the weights to sum to the number of values n, then
# uses n - 1 for the variance and n for the moments and the standard error, so a
# weighted summary is not the summary of the values repeated by their weights.
pct <- paste0(100 * confidence, "%")
if (length(value) != length(weight)) stop("values and weights must have the same length")
if (any(weight < 0, na.rm = TRUE)) stop("weights must not be negative")
keep <- !is.na(value) & !is.na(weight) & weight > 0
value <- value[keep]
weight <- weight[keep]
ordered <- order(value)
value <- value[ordered]
weight <- weight[ordered]
n <- length(value)
if (n == 0) stop("at least one value with positive weight is needed")
w <- weight * n / sum(weight)
m <- weighted.mean(value, w)
v <- sum(w * (value - m)^2) / (n - 1)
six <- function(x) formatC(round(x, 6), digits = 6, format = "f", drop0trailing = TRUE)
cat("Valid data", n, "  Sum of weights", sum(weight), "\n")
cat("Mean", six(m), "  Variance", six(v), "  Standard deviation", six(sqrt(v)), "\n")
cat("Variance coefficient", six(sqrt(v) / m), "  Standard error of mean",
    six(sqrt(v / n)), "\n")
cat("Upper", pct, "CL of mean", six(m + qt((1 + confidence) / 2, n - 1) * sqrt(v / n)),
    "  Lower", pct, "CL of mean", six(m - qt((1 + confidence) / 2, n - 1) * sqrt(v / n)), "\n")
cat("Geometric mean", six(exp(sum(w * log(value)) / n)), "\n")
mom <- function(k) sum(w * (value - m)^k) / n
cat("Skewness", six(mom(3) / mom(2)^1.5), "  Kurtosis", six(mom(4) / mom(2)^2), "\n")

# Centile type 1 with weights: the ordered value at which the cumulative scaled
# weight first exceeds pn, or the average of it and the value before when the
# cumulative weight reaches pn exactly
centile <- function(p) {
  cum <- cumsum(w)
  i <- which(cum > p * n)[1]
  if (i > 1 && isTRUE(all.equal(cum[i - 1], p * n))) (value[i - 1] + value[i]) / 2
  else value[i]
}
cat("Upper quartile", centile(0.75), "  Median", centile(0.5), "  Lower quartile",
    centile(0.25), "  Centile 95", centile(0.95), "  Centile 5", centile(0.05), "\n")

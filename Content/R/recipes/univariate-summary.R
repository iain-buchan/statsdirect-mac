# StatsDirect recipe: Descriptive statistics of a column, as the help shows them in R.
# From the help's R code (basic_descriptive_statistics/univariate_summary.htm); the data and settings above come from the run.
# data: speed
# settings: confidence = gamma
# hand-edited: the confidence level and the data come from the run, as the header says

# Univariate summary: the StatsDirect help example (Michelson's 100 measurements
# of the speed of light in air, millions of metres per second) in R
pct <- paste0(100 * confidence, "%")
n <- length(speed)

# R's standard summary, then each statistic of the report, printed to 12 places
# as the example shows them (decimal places set to 12 in Analysis_Options)
print(summary(speed))
twelve <- function(x) {
  formatC(round(x, 12), digits = 12, format = "f", drop0trailing = TRUE)
}
cat("Valid data", n, "  Missing data", sum(is.na(speed)), "\n")
cat("Sum", twelve(sum(speed)), "\n")
cat("Mean", twelve(mean(speed)), "\n")
cat("Variance", twelve(var(speed)), "\n")
cat("Standard deviation", twelve(sd(speed)), "\n")
cat("Variance coefficient", twelve(sd(speed) / mean(speed)), "\n")
se <- sd(speed) / sqrt(n)
cat("Standard error of mean", twelve(se), "\n")
cat("Upper", pct, "CL of mean", twelve(mean(speed) + qt((1 + confidence) / 2, n - 1) * se), "\n")
cat("Lower", pct, "CL of mean", twelve(mean(speed) - qt((1 + confidence) / 2, n - 1) * se), "\n")
cat("Geometric mean", twelve(exp(mean(log(speed)))), "\n")

# Skewness and kurtosis are sqrt(b1) and b2, from the moments about the mean
# with n as the divisor, as in the normality tests
m <- function(k) mean((speed - mean(speed))^k)
cat("Skewness", twelve(m(3) / m(2)^1.5), "\n")
cat("Kurtosis", twelve(m(4) / m(2)^2), "\n")

# Centile type 2 interpolates between the ordered values at p(n + 1): type 6 in
# R, whose default, type 7, interpolates at 1 + p(n - 1) instead
q <- quantile(speed, c(0.05, 0.25, 0.5, 0.75, 0.95), type = 6)
cat("Maximum", max(speed), "\n")
cat("Upper quartile", twelve(q[4]), "\n")
cat("Median", twelve(q[3]), "\n")
cat("Lower quartile", twelve(q[2]), "\n")
cat("Interquartile range", twelve(q[4] - q[2]), "\n")
cat("Minimum", min(speed), "\n")
cat("Range", twelve(max(speed) - min(speed)), "\n")
cat("Centile 95", twelve(q[5]), "\n")
cat("Centile 5", twelve(q[1]), "\n")


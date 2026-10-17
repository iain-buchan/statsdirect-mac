# StatsDirect recipe: descriptive summaries of every selected column.
# hand-edited: selected columns, missing values, centile definition and report choices.
# data: samples... = data
# settings: confidence = gamma, centile_a = report-udca, centile_b = report-udcb, centile_type = report-centile-type, show_n = report-valid-data, show_missing = report-missing-data, show_sum = report-sum, show_mean = report-mean, show_variance = report-variance, show_sd = report-sd, show_cv = report-variance-coeff, show_se = report-sem, show_upper = report-u95cl, show_lower = report-l95cl, show_geometric = report-geometric-mean, show_skewness = report-skewness, show_kurtosis = report-kurtosis, show_max = report-maximum, show_uq = report-uq, show_median = report-median, show_lq = report-lq, show_iqr = report-iqr, show_min = report-minimum, show_range = report-range, show_centiles = report-udc

if (is.null(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95
if (is.null(centile_a)) centile_a <- 0.05
if (is.null(centile_b)) centile_b <- 0.95
if (is.null(centile_type)) centile_type <- 1L
# Native centile type 1 is R type 2 (average at an exact cumulative count);
# native type 2 is R type 6 (interpolation at p(n+1)), with held endpoints.
summary_centile <- function(x, p) {
  if (p < 0 || p > 1 || !length(x)) return(NA_real_)
  if (as.integer(centile_type) == 2L) return(unname(quantile(x, p, type = 6)))
  x <- sort(x); n <- length(x)
  index <- p * n
  if (p <= 0) return(x[1L])
  if (p >= 1) return(x[n])
  nearest <- round(index)
  if (nearest >= 1L && nearest < n && abs(index - nearest) <= 1e-9 * n)
    return(mean(x[c(nearest, nearest + 1L)]))
  x[min(n, floor(index) + 1L)]
}
summary_column <- function(values) {
  x <- values[!is.na(values)]; n <- length(x)
  result <- c(n = n, missing = length(values) - n, sum = NA_real_, mean = NA_real_,
    variance = NA_real_, sd = NA_real_, cv = NA_real_, se = NA_real_, upper = NA_real_, lower = NA_real_,
    geometric = NA_real_, skewness = NA_real_, kurtosis = NA_real_, maximum = NA_real_,
    uq = NA_real_, median = NA_real_, lq = NA_real_, iqr = NA_real_, minimum = NA_real_,
    range = NA_real_, centile_b = NA_real_, centile_a = NA_real_)
  if (!n) return(result)
  result[c("sum", "mean", "maximum", "minimum", "range")] <- c(sum(x), mean(x), max(x), min(x), diff(range(x)))
  q <- vapply(c(centile_a, 0.25, 0.5, 0.75, centile_b), function(p) summary_centile(x, p), double(1))
  result[c("uq", "median", "lq", "iqr", "centile_b", "centile_a")] <- c(q[4L], q[3L], q[2L], q[4L] - q[2L], q[5L], q[1L])
  if (all(x > 0)) result["geometric"] <- exp(mean(log(x)))
  if (n > 1L) {
    result["variance"] <- var(x); result["sd"] <- sd(x)
    result["se"] <- sd(x) / sqrt(n)
    if (mean(x) != 0) result["cv"] <- sd(x) / mean(x)
    result[c("lower", "upper")] <- mean(x) + c(-1, 1) * qt((1 + confidence) / 2, n - 1L) * result["se"]
    if (n > 3L && sd(x) > 0) {
      unit <- max(abs(x - mean(x)))
      d <- (x - mean(x)) / unit
      result["skewness"] <- mean(d^3) / mean(d^2)^1.5
      result["kurtosis"] <- mean(d^4) / mean(d^2)^2
    }
  }
  result
}
summary_results <- lapply(samples, summary_column)
summary_shown <- vapply(list(show_n, show_missing, show_sum, show_mean, show_variance, show_sd,
  show_cv, show_se, show_upper, show_lower, show_geometric, show_skewness, show_kurtosis,
  show_max, show_uq, show_median, show_lq, show_iqr, show_min, show_range, show_centiles, show_centiles),
  function(value) is.null(value) || isTRUE(value), logical(1))
summary_labels <- c("Valid data", "Missing data", "Sum", "Mean", "Variance", "Standard deviation",
  "Variance coefficient", "Standard error of mean", paste("Upper", 100 * confidence, "% CL of mean"),
  paste("Lower", 100 * confidence, "% CL of mean"), "Geometric mean", "Skewness", "Kurtosis", "Maximum",
  "Upper quartile", "Median", "Lower quartile", "Interquartile range", "Minimum", "Range",
  paste("Centile", 100 * centile_b), paste("Centile", 100 * centile_a))
for (i in seq_along(summary_results)) {
  cat(names(samples)[i], "\n")
  result <- summary_results[[i]]
  for (j in which(summary_shown))
    cat(summary_labels[j], formatC(round(result[j], 12), digits = 12, format = "f", drop0trailing = TRUE), "\n")
}

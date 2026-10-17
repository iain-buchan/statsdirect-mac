# StatsDirect recipe: selected quantiles and their selected confidence intervals.
# hand-edited: replay every selected column, missing values and conservative settings.
# data: samples... = data
# settings: p = quantile, conf = gamma, conservative = conservative-ci

if (is.null(p) || p <= 0 || p >= 1) p <- 0.5
if (is.null(conf)) conf <- 0.95
if (is.null(conservative)) conservative <- FALSE
quantile_summary <- function(values) {
  x <- sort(values[!is.na(values)])
  n <- length(x)
  if (!n) return(list(n = 0L, missing = length(values), value = NA_real_, lower = NA_real_,
    upper = NA_real_, coverage = NA_real_, capLower = FALSE, capUpper = FALSE))
  tail_area <- (1 - conf) / 2
  cap_lower <- cap_upper <- FALSE
  if (n > 200L) {
    z <- qnorm(1 - tail_area)
    lo <- n * p - z * sqrt(n * p * (1 - p))
    hi <- n * p + z * sqrt(n * p * (1 - p))
    if (lo < 1) { lo <- 0; cap_lower <- TRUE }
    if (hi + 1 > n) { hi <- n - 1; cap_upper <- TRUE }
    if (conservative) {
      while (lo >= 1 && pbinom(floor(lo), n, p) > tail_area) lo <- lo - 1
      if (lo < 1) { lo <- 0; cap_lower <- TRUE }
      while (hi + 1 < n && pbinom(floor(hi), n, p) < 1 - tail_area) hi <- hi + 1
      if (hi + 1 >= n) { hi <- n - 1; cap_upper <- TRUE }
    }
    lo <- floor(lo); hi <- floor(hi)
  } else {
    cumulative <- pbinom(0:n, n, p)
    if (conservative) {
      eligible <- which(cumulative <= tail_area)
      lo <- if (length(eligible)) tail(eligible, 1L) - 1L else 0L
      hi <- which(cumulative >= 1 - tail_area)[1L] - 1L
    } else {
      lo <- which.min(abs(cumulative - tail_area)) - 1L
      hi <- which.min(abs(cumulative - (1 - tail_area))) - 1L
    }
    if (lo < 1) { lo <- 0L; cap_lower <- TRUE }
    if (hi + 1 > n) { hi <- n - 1L; cap_upper <- TRUE }
  }
  list(n = n, missing = length(values) - n, value = unname(quantile(x, p, type = 6)),
       lower = x[lo + 1L], upper = x[hi + 1L],
       coverage = 100 * (pbinom(hi, n, p) - pbinom(lo, n, p)),
       capLower = cap_lower, capUpper = cap_upper)
}
quantile_results <- lapply(samples, quantile_summary)
for (i in seq_along(quantile_results)) {
  result <- quantile_results[[i]]
  cat(names(samples)[i], "\n")
  cat("Quantile (", p, ") = ", result$value, "\n", sep = "")
  cat(sprintf("Approximate %g%% CI (%s) = %g to %g\n", 100 * conf,
              if (conservative) "conservative" else "non-conservative", result$lower, result$upper))
  cat("Exact confidence level = ", format(round(result$coverage, 6), digits = 10), "%\n", sep = "")
  if (result$capLower || result$capUpper) cat("* Limit capped at the sample minimum or maximum.\n")
}

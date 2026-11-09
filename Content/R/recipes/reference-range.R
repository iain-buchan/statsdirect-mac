# StatsDirect recipe: Reference range with the confidence intervals of its limits, as the help shows it in R.
# From the help's R code (parametric_methods/reference_range.htm); the data and settings above come from the run.
# data: igm
# settings: confidence = gamma, range = reference-interval, conservative = do_conservative

# Reference range: the StatsDirect help example (Altman 1991, serum IgM in 298
# children) in R
# The data are the IgM column of the Parametric worksheet of the StatsDirect test
# workbook.
igm <- igm[!is.na(igm)]
pct <- paste0(100 * confidence, "%")
rpct <- paste0(100 * range, "%")
n <- length(igm)
z <- qnorm((1 + confidence) / 2)   # confidence in each estimated limit
zr <- qnorm((1 + range) / 2)       # proportion covered by the reference interval
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
cat("Sample mean =", six(mean(igm)), "  Sample size n =", n,
    "  Sample sd =", six(sd(igm)), "\n")

# Normal reference limits use the requested population coverage. Their
# confidence intervals use the separate confidence level (Altman 1991).
normal_range <- function(x, back = identity) {
  m <- mean(x)
  s <- sd(x)
  limits <- m + c(-1, 1) * zr * s
  se <- s * sqrt(1 / n + zr^2 / (2 * n))
  cat(rpct, "reference interval =", six(back(limits[1])), "to", six(back(limits[2])), "\n")
  cat(pct, "confidence interval for lower range limit =", six(back(limits[1] - z * se)),
      "to", six(back(limits[1] + z * se)), "\n")
  cat(pct, "confidence interval for upper range limit =", six(back(limits[2] - z * se)),
      "to", six(back(limits[2] + z * se)), "\n")
}
cat("For normal data\n")
normal_range(igm)
if (all(igm > 0)) {
  cat("For log-normal data\n")
  normal_range(log(igm), exp)
}

# Distribution-free limits use the same binomial order-statistic search as the
# quantile recipe: exact search up to 200 values, normal starting limits above
# 200, and conservative extension when requested. Capped limits are marked.
reference_quantile <- function(p) {
  tail_area <- (1 - confidence) / 2
  cap_lower <- cap_upper <- FALSE
  if (n > 200) {
    lo <- n * p - z * sqrt(n * p * (1 - p))
    hi <- n * p + z * sqrt(n * p * (1 - p))
    if (lo < 1) { lo <- 0; cap_lower <- TRUE }
    if (hi + 1 > n) { hi <- n - 1; cap_upper <- TRUE }
    if (isTRUE(conservative)) {
      while (lo >= 1 && pbinom(floor(lo), n, p) > tail_area) lo <- lo - 1
      if (lo < 1) { lo <- 0; cap_lower <- TRUE }
      while (hi + 1 < n && pbinom(floor(hi), n, p) < 1 - tail_area) hi <- hi + 1
      if (hi + 1 >= n) { hi <- n - 1; cap_upper <- TRUE }
    }
    lo <- floor(lo); hi <- floor(hi)
  } else {
    cumulative <- pbinom(0:n, n, p)
    if (isTRUE(conservative)) {
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
  list(value = unname(quantile(igm, p, type = 6)), lower = x[lo + 1], upper = x[hi + 1],
       coverage = 100 * (pbinom(hi, n, p) - pbinom(lo, n, p)),
       capLower = cap_lower, capUpper = cap_upper)
}
cat("For any data\n")
x <- sort(igm)
probabilities <- c((1 - range) / 2, (1 + range) / 2)
reference_quantiles <- lapply(probabilities, reference_quantile)
for (i in seq_along(reference_quantiles)) {
  q <- reference_quantiles[[i]]
  cat("Quantile", probabilities[i], "=", q$value, "\n")
  cat("Approximate", pct, "confidence interval", if (isTRUE(conservative)) "(conservative)" else "(non-conservative)", "=",
      paste0(if (q$capLower) "* " else "", q$lower), "to", paste0(if (q$capUpper) "* " else "", q$upper), "\n")
  cat(sprintf("Exact confidence level = %s%%%s\n", six(q$coverage),
              if (q$capLower || q$capUpper) " (* limit capped at min/max)" else ""))
}

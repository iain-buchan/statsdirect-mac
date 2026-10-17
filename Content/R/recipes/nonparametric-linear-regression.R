# StatsDirect recipe: Theil regression for the selected outcome and predictor.
# hand-edited: complete pairs and the selected confidence determine the slope interval.
# data: outcome = outcome, predictor = predictor
# settings: confidence = gamma

if (length(outcome) != length(predictor)) stop("Select outcome and predictor columns of equal length.")
if (is.null(confidence)) confidence <- 0.95
keep <- !is.na(outcome) & !is.na(predictor)
np_y <- outcome[keep]; np_x <- predictor[keep]
n <- length(np_x)
if (n < 5L) stop("Nonparametric regression needs at least five complete pairs.")
if (length(unique(np_x)) < 2L || length(unique(np_y)) < 2L)
  stop("The outcome and predictor must each contain more than one distinct value.")
if (n * (n - 1) / 2 >= 2000000)
  stop("The selected data contain too many pairwise slopes for this regression.")

# S = n(n-1)/2 - 2D, where D counts inversions in a random ordering.
# Use normalized probabilities to avoid overflowing permutation counts. The
# moving sum and symmetry give the exact no-ties null distribution used for
# slope ranks even when the selected X contains ties.
np_kendall_score <- function(n, tail) {
  pairs <- n * (n - 1) / 2
  if (n <= 1000L) {
    probability <- 1
    for (j in 2:n) {
      old_max <- length(probability) - 1L
      new_max <- old_max + j - 1L
      d <- 0:floor(new_max / 2)
      cumulative <- c(0, cumsum(probability))
      half <- (cumulative[pmin(d, old_max) + 2L] - cumulative[pmax(d - j, -1L) + 2L]) / j
      probability <- c(half, rev(if (new_max %% 2L == 0L) head(half, -1L) else half))
    }
    d <- which(cumsum(probability) + 1e-14 >= tail)[1L] - 1L
    return(pairs - 2 * d)
  }
  # Above 1000 points the native method uses the continuity-corrected
  # Edgeworth expansion. Search only scores with the correct parity.
  upper_tail <- function(score) {
    x <- (score - 1) / sqrt(n * (n - 1) * (2 * n + 5) / 18)
    h <- numeric(15); h[1L] <- x; h[2L] <- x * x - 1
    for (i in 3:15) h[i] <- x * h[i - 1L] - (i - 1) * h[i - 2L]
    r <- 1 / n
    a <- h[3L] * (-0.09 + r * (0.045 + r * (-0.5325 + r * 0.506)))
    b <- h[5L] * (0.036735 + r * (-0.036735 + r * 0.3214)) +
      h[7L] * (0.00405 + r * (-0.023336 + r * 0.07787))
    c <- h[9L] * (-0.0033061 - r * 0.0065166) + h[11L] * (-0.0001215 + r * 0.0025927) +
      r * (h[13L] * 0.00014878 + h[15L] * 0.0000027338)
    min(1, max(0, pnorm(x, lower.tail = FALSE) + r * (a + r * (b + r * c)) * 0.398942 * exp(-x * x / 2)))
  }
  low <- 0L; high <- floor(pairs / 2)
  while (low < high) {
    middle <- ceiling((low + high) / 2)
    if (upper_tail(pairs %% 2 + 2 * middle) + 1e-14 >= tail) low <- middle else high <- middle - 1L
  }
  pairs %% 2 + 2 * low
}
s <- sort(unlist(lapply(seq_len(n - 1L), function(i) {
  j <- (i + 1L):n
  distinct <- np_x[j] != np_x[i]
  (np_y[j[distinct]] - np_y[i]) / (np_x[j[distinct]] - np_x[i]) + 0
}), use.names = FALSE))
N <- length(s)
slope <- median(s)
intercept <- median(np_y) - slope * median(np_x)
w <- np_kendall_score(n, (1 - confidence) / 2)
r <- floor((N - w) / 2)
np_result <- list(n = n, slope = slope, intercept = intercept,
  lower = if (r >= 1L) s[r] else NA_real_,
  upper = if (r >= 1L) s[N + 1L - r] else NA_real_,
  confidence = confidence, kendall_score = w, interval_available = r >= 1L)
cat("Observations per sample =", n, "\n")
cat(sprintf("Median slope = %.6f   Y-intercept = %.6f\n", slope, intercept))
if (np_result$interval_available) {
  cat(sprintf("%g%% CI for the slope = %g to %g\n", 100 * confidence, np_result$lower, np_result$upper))
} else cat(sprintf("%g%% CI for the slope is unavailable: too few pairs at this confidence level.\n", 100 * confidence))
print(cor.test(np_x, np_y, method = "kendall", exact = FALSE, continuity = TRUE))

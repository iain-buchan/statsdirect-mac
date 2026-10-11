# StatsDirect recipe: Spearman's rho: the exact upper tail probability of the Hotelling-Pabst T for n pairs, or the T of a tail probability, as the help shows them in R.
# From the help's R code (distributions/spearman.htm); the settings above come from the run.
# settings: n = df, hotelling = df2, rho = value, upper = upper, asked = asked
# hand-edited: the calculator's boxes are bound to the run; the help computes T from two rankings

# The counts of the orderings of n ranks by T, the sum of squared differences from 1, 2, ..., n,
# built up one position at a time: for each set of ranks already placed in the first positions,
# the counts of the partial orderings by their sum so far; placing rank r at position i adds
# (i - r)^2. The count of sets doubles with each pair, so this is for 10 pairs or fewer, where
# StatsDirect also uses the exact distribution (above 10 it uses an Edgeworth series).
counts_by_T <- function(n) {
  top <- n * (n^2 - 1) / 3                # the largest T, for the reversed ranking
  counts <- vector("list", 2^n)           # one entry per set of ranks placed
  counts[[1]] <- c(1, numeric(top))       # nothing placed: one ordering with T = 0
  bit <- 2^(0:(n - 1))
  for (set in 0:(2^n - 2)) {
    so_far <- counts[[set + 1]]
    if (is.null(so_far)) next
    i <- sum(bitwAnd(set, bit) > 0) + 1   # the next position to fill
    for (r in (1:n)[bitwAnd(set, bit) == 0]) {
      added <- c(numeric((i - r)^2), so_far)[seq_len(top + 1)]
      to <- set + bit[r] + 1
      counts[[to]] <- if (is.null(counts[[to]])) added else counts[[to]] + added
    }
  }
  counts[[2^n]]                           # counts for T = 0, 1, ..., top
}
upper_tail <- function(t, n) {            # P(T <= t): the upper tail probability of rho
  counts <- counts_by_T(n)
  sum(counts[seq_len(t + 1)]) / sum(counts)
}
fifteen <- function(x) formatC(x, digits = 15, format = "f", drop0trailing = TRUE)
if (n > 10) stop("the exact distribution is enumerated here for 10 pairs or fewer; for more, StatsDirect uses the Edgeworth series of Best and Roberts (1975), as cor.test does")

if (exists("asked") && asked != "calculate") {
  # The inverse (the calculator's Invert): the largest T whose upper tail probability does not
  # exceed the P entered; the calculator shows that T, its rho, and the probability it cuts off
  counts <- counts_by_T(n)
  tail <- cumsum(counts) / sum(counts)    # P(T <= t) for t = 0, 1, ..., top
  t <- seq(0, length(counts) - 1, by = 2) # the possible values of T are even
  k <- max(t[tail[t + 1] <= upper])
  cat("T =", k, "  Spearman's rho =", fifteen(1 - 6 * k / (n^3 - n)), "\n")
  cat("Hotelling T (upper tail P ", fifteen(upper), ", n ", n, ") = ", fifteen(upper_tail(k, n)), "\n", sep = "")
} else {
  # The line the calculator reports for T with n pairs, to 15 decimal places: the probability of
  # a rank correlation at least as large as rho, which is a T no larger than this one. The
  # distribution of rho is symmetrical about 0, so the two sided P is twice it.
  cat("P(Hotelling T ", hotelling, ", n ", n, ") = ", fifteen(upper_tail(hotelling, n)), " upper tail\n", sep = "")
}

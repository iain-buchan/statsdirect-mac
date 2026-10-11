# StatsDirect recipe: Kendall's tau: the exact upper tail probability of S for n pairs, or the S of a tail probability, as the help shows them in R.
# From the help's R code (distributions/kendall.htm); the settings above come from the run.
# settings: n = df, S = df2, tau = value, upper = upper, asked = asked
# hand-edited: the calculator's boxes are bound to the run; the help computes S from two rankings

# The counts of the orderings of n items by their number of discordant pairs (0 to n(n-1)/2)
# follow from a recurrence: adding the mth item to an ordering of m - 1 items adds 0 to m - 1
# discordant pairs, each equally often, so the counts are the coefficients of the product of
# the polynomials 1 + x + ... + x^(m-1) for m = 2 to n. S is the number of concordant pairs
# less the number discordant: n(n-1)/2 - 2 * discordant
discordant_counts <- function(n) {
  f <- 1
  for (m in 2:n) {
    g <- numeric(length(f) + m - 1)
    for (j in 1:m) g[j:(j + length(f) - 1)] <- g[j:(j + length(f) - 1)] + f
    f <- g
  }
  f
}
upper_tail <- function(k, n) {            # P(S >= k), the upper tail probability
  f <- discordant_counts(n)
  s <- n * (n - 1) / 2 - 2 * (seq_along(f) - 1)
  sum(f[s >= k]) / sum(f)
}
fifteen <- function(x) formatC(x, digits = 15, format = "f", drop0trailing = TRUE)

if (exists("asked") && asked != "calculate") {
  # The inverse (the calculator's Invert): the largest S whose upper tail probability is not less
  # than the P entered; the calculator shows that S, its tau, and the probability it cuts off
  f <- discordant_counts(n)
  s <- n * (n - 1) / 2 - 2 * (seq_along(f) - 1)
  k <- max(s[cumsum(f) / sum(f) >= upper])
  cat("S =", k, "  Kendall's tau =", fifteen(k / (n * (n - 1) / 2)), "\n")
  cat("Kendall's T (upper tail P ", fifteen(upper), ", n ", n, ") = ", fifteen(upper_tail(k, n)), "\n", sep = "")
} else {
  # The line the calculator reports for S with n pairs, to 15 decimal places, with the tau it
  # shows (S divided by the n(n-1)/2 pairs). The distribution is symmetrical about 0, so the two
  # sided P is twice the upper tail.
  cat("Kendall's tau =", fifteen(S / (n * (n - 1) / 2)), "\n")
  cat("P(Kendall's T ", S, ", n ", n, ") = ", fifteen(upper_tail(S, n)), " upper tail\n", sep = "")
}

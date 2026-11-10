# StatsDirect recipe: Mann-Whitney U test with theta, its exact probabilities and the limits of the difference, as the help shows it in R.
# From the help's R code (nonparametric_methods/mann_whitney.htm); the data and settings above come from the run.
# data: farm, town
# settings: confidence = gamma
# hand-edited: the confidence level and the data come from the run, as the header says; large samples use the report's normal approximations; no interval for the difference where the report gives none

# Mann-Whitney U test: the StatsDirect help example (Conover 1999, p. 218) in R
farm <- farm[!is.na(farm)]
town <- town[!is.na(town)]
if (is.null(confidence) || !is.finite(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95
pct <- paste0(100 * confidence, "%")
n1 <- as.numeric(length(farm))          # sizes as numbers: their products can pass R's largest integer
n2 <- as.numeric(length(town))

# R's standard test. Its W is the U for x (243). These data have ties. R 4.6.0
# or later gives exact results that allow for the ties. Older versions warn and
# use a normal approximation with continuity correction, as exact = FALSE does
# (two sided P = 0.5279).
# Use alternative = "less" for the lower side P and "greater" for the upper.
print(wilcox.test(farm, town, conf.int = TRUE, conf.level = confidence))

# Medians, rank sum, U, U' and theta
r <- rank(c(farm, town))                  # tied values share a mid-rank
ranksum <- sum(r[1:n1])
U <- ranksum - n1 * (n1 + 1) / 2
Uprime <- n1 * n2 - U
theta <- Uprime / (n1 * n2)
cat("x: n =", n1, "  median =", median(farm), "  rank sum =", ranksum, "\n")
cat("y: n =", n2, "  median =", median(town), "\n")
cat("U =", U, "  U' =", Uprime, "\n")

# Theta: 95% confidence interval by method 5 of Newcombe (2006b). Each search
# stops just short of the end that would solve the equation if theta is 0 or 1.
z <- qnorm((1 + confidence) / 2)
h <- (n1 + n2) / 2 - 1
e <- 1e-9
f <- function(y, s) y + s * z * sqrt(y * (1 - y) *
       (1 + h * ((1 - y) / (2 - y) + y / (1 + y))) / (n1 * n2)) - theta
ci <- c(uniroot(f, c(0, 1 - e), s = 1, tol = 1e-10)$root,     # lower limit
        uniroot(f, c(e, 1), s = -1, tol = 1e-10)$root)        # upper limit
cat(sprintf("Theta = %.6f (%s CI: %.6f to %.6f)\n", theta, pct, ci[1], ci[2]))

# As the report does, use the normal approximation (adjusted for ties, without a
# continuity correction) when both samples are above 100 or the exact
# distribution would need more than a million cells.
N <- n1 + n2
ties <- tabulate(match(r, unique(r)))
tie_sum <- sum(ties^3 - ties)
cells <- if (tie_sum > 0) n1 + n1 * (n1 + 1) * N - n1 * (n1 + 1) * (2 * n1 + 1) / 3 + 1 else
  n1 * (floor(n2 / 2) + 1)
if ((n1 > 100 && n2 > 100) || cells > 1e6) {
  se_u <- if (tie_sum > 0) sqrt(n1 * n2 / (12 * N * (N - 1)) * (N^3 - N - tie_sum)) else
    sqrt(n1 * n2 * (N + 1) / 12)
  z_u <- (U - n1 * n2 / 2) / se_u
  cat(sprintf("Normalised statistic = %.6f%s\n", z_u, if (tie_sum > 0) " (adjusted for ties)" else ""))
  lower <- pnorm(z_u)                     # each tail as itself
  upper <- pnorm(z_u, lower.tail = FALSE)
} else if (tie_sum == 0) {
  # Without ties the report counts P(U <= u) by Neumann's procedure: the
  # generating function of U built up one value of the smaller sample at a time
  # (times 1 - x^(m2 + i), then divided by 1 - x^i), and the far tail by symmetry
  u_at_most <- function(iv) {
    if (iv < 0) return(0)
    m1 <- min(n1, n2); m2 <- max(n1, n2); lim <- iv + 1
    w <- numeric(lim + 1); w[1] <- 1
    binom <- 1
    for (i in seq_len(m1)) {
      binom <- binom * (m2 + i) / i
      top <- min(i * m2 + 1, lim)
      low <- i + m2 + 1
      if (top >= low) w[low:top] <- w[low:top] - w[1:(top - low + 1)]
      if (top > i) {                      # running sums along each residue class of i
        k <- ceiling(top / i)
        w[1:top] <- t(apply(matrix(c(w[1:top], numeric(k * i - top)), nrow = i), 1, cumsum))[1:top]
      }
    }
    min(1, max(0, cumsum(w[1:lim] / binom)[lim]))
  }
  iv <- floor(U)
  if (2 * iv <= n1 * n2) {
    lower <- u_at_most(iv)
    upper <- if (iv == 0) 1 else 1 - u_at_most(iv - 1)
  } else {
    upper <- u_at_most(n1 * n2 - iv)
    lower <- if (iv == n1 * n2) 1 else 1 - u_at_most(n1 * n2 - iv - 1)
  }
} else {
  # Exact P given the ties, in any version of R: count the ways of choosing n1
  # of the ranks, by their sum. Ranks are doubled to make mid-ranks whole numbers;
  # no n1 of them sum to more than S, the sum of the n1 largest.
  r2 <- 2 * r
  S <- sum(sort(r2, decreasing = TRUE)[seq_len(n1)])
  ways <- matrix(0, n1 + 1, S + 1)        # rows: how many ranks, columns: sum
  ways[1, 1] <- 1
  for (v in r2[r2 <= S]) ways[-1, (v + 1):(S + 1)] <-
    ways[-1, (v + 1):(S + 1)] + ways[-(n1 + 1), 1:(S + 1 - v)]
  p <- ways[n1 + 1, ] / choose(n1 + n2, n1) # P(doubled rank sum = 0, 1, ... S)
  w <- 2 * ranksum + 1                    # position of the observed value
  lower <- sum(p[1:w])                    # each side includes the observed U
  upper <- sum(p[w:(S + 1)])
}
cat("Lower side P =", round(lower, 4), "  Upper side P =", round(upper, 4),
    "  Two sided P =", round(min(1, 2 * min(lower, upper)), 4), "\n")

# Confidence interval for the difference: K from the exact distribution of U
# without ties, then the Kth smallest and Kth largest of the n1 * n2 differences.
# For these data R 4.6.0 or later gives the same limits but labels them 95.2
# percent, as it allows for the ties. For other tied data its limits can differ.
# As in the report, K is from the normal approximation instead when the samples
# are large and the distribution of U would be too large to count.
tail_area <- (1 - confidence) / 2
approximate_k <- ((n1 > 30 && n2 > 30) || n1 > 100 || n2 > 100) &&
  (n1 * n2 + 1 > 200000 || 1 + min(n1, n2) + floor(n1 * n2 / 2) > 100000)
if (approximate_k) {
  K <- round(n1 * (N + 1) / 2) + floor(qnorm(tail_area) * sqrt(n1 * n2 * N / 12)) -
    round(n1 * (n1 + 1) / 2)
  coverage <- 100 * confidence
} else {
  K <- qwilcox(tail_area, n1, n2)
  coverage <- 100 * (1 - 2 * pwilcox(K - 1, n1, n2))
}
d <- sort(outer(farm, town, "-"))
# As in the report, there is no interval (nor median difference) with fewer than
# 4 values in a sample, or when even the widest interval, from the smallest to the
# largest difference, falls short of the confidence asked for (K = 0)
if (n1 < 4 || n2 < 4) {
  cat("confidence interval not calculated with fewer than 4 observations in either sample\n")
} else if (K == 0) {
  cat("confidence interval not calculated: the samples are too small for ", pct, " confidence\n", sep = "")
} else {
  cat(sprintf("%.2f%% confidence interval for the difference: K = %d%s\n",
              coverage, K, if (approximate_k) " (approx)" else ""))
  cat(sprintf("median difference = %g   CI = %g to %g\n",
              median(d), d[K], rev(d)[K]))
}

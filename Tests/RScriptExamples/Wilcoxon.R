# Wilcoxon signed ranks test: the StatsDirect help example (Conover 1999) in R
first  <- c(86, 71, 77, 68, 91, 72, 77, 91, 70, 71, 88, 87)
second <- c(88, 77, 76, 64, 96, 72, 65, 90, 65, 80, 81, 72)
d <- first - second                       # one difference is 0 and some are tied
n <- length(d)

# Match the selected analysis by excluding zero differences before ranking.
# On R 4.6 or later the raw paired call uses Pratt ranks (V = 48.5), while
# StatsDirect and Conover exclude zeros before ranking (V = 41.5).
nz <- d[d != 0]
print(wilcox.test(nz, exact = TRUE, correct = FALSE))

# Number of non-zero differences and the sum of ranks for positive differences
r <- rank(abs(nz))                        # tied values share a mid-rank
Tplus <- sum(r[nz > 0])
cat("Number of non-zero differences ranked =", length(nz), "\n")
cat("Sum of ranks for positive differences =", Tplus, "\n")

# Independently enumerate all 2^11 equally likely sign assignments in this
# example. Each side includes the observed positive rank sum.
assignments <- as.matrix(expand.grid(rep(list(c(0, 1)), length(r))))
positive_sums <- drop(assignments %*% r)
lower <- mean(positive_sums <= Tplus)
upper <- mean(positive_sums >= Tplus)
cat("Lower side P =", round(lower, 4), "  Upper side P =", round(upper, 4),
    "  Two sided P =", round(min(1, 2 * min(lower, upper)), 4), "\n")

# Confidence interval, from all n differences: K from the exact distribution of
# the statistic without ties, then the Kth smallest and Kth largest of the
# n(n + 1)/2 averages of two differences (each is also averaged with itself).
# With fewer than 6 differences K is 0 and there is no 95% interval.
# StatsDirect's median difference is the median of these averages, which R calls
# the (pseudo)median; it is not median(d), which is 1 here.
# R 4.6.0 or later gives the same limits for these data but works out the level
# given the ties (96.2 percent in R 4.6.1). For other tied data its limits can
# differ.
K <- qsignrank(0.025, n)
a <- outer(d, d, "+") / 2
a <- sort(a[upper.tri(a, diag = TRUE)])
cat(sprintf("%.1f%% confidence interval for difference between population medians:\n",
            100 * (1 - 2 * psignrank(K - 1, n))))
cat(sprintf("K = %g   Median difference = %g (%g to %g)\n",
            K, median(a), a[K], rev(a)[K]))

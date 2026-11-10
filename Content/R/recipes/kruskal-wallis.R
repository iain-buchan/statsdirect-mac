# StatsDirect recipe: Kruskal-Wallis test with its adjustment for ties, as the help shows it in R.
# From the help's R code (nonparametric_methods/kruskal_wallis.htm); the data and settings above come from the run.
# data: yield...
# settings: confidence = confidence, sided = sided

# Kruskal-Wallis test: the StatsDirect help example (Conover 1999, p. 291) in R
yield <- lapply(yield, function(v) v[!is.na(v)])    # missing values are left out
y <- unlist(yield)
g <- factor(rep(names(yield), lengths(yield)))
k <- nlevels(g)
N <- length(y)
ni <- lengths(yield)
if (is.null(confidence) || !is.finite(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95
alpha <- min(confidence, 1 - confidence)
one_sided <- identical(as.character(sided), "1")

# R's standard test. Its chi-squared is StatsDirect's T adjusted for ties.
print(kruskal.test(y, g))
pv <- function(p) if (p < 0.0001) "P < 0.0001" else paste("P =", round(p, 4))

# Mean ranks, and T before and after the adjustment for ties
r <- rank(y)
meanrank <- tapply(r, g, mean)
T0 <- 12 / (N * (N + 1)) * sum(ni * meanrank^2) - 3 * (N + 1)
ties <- table(y)
Tadj <- T0 / (1 - sum(ties^3 - ties) / (N^3 - N))
cat("Mean rank:", round(meanrank, 2), "\n")
cat(sprintf("T = %.6f   Adjusted for ties: T = %.6f   P = %.3g\n",
            T0, Tadj, pchisq(Tadj, k - 1, lower.tail = FALSE)))

# All pairwise comparisons (Dwass-Steel-Critchlow-Fligner): for each pair a
# Mann-Whitney statistic from the ranks within the pair, with its variance
# adjusted for ties, referred to the studentized range for k groups
pairs <- combn(k, 2)
if (!one_sided) {
  cat("Critical q (range) =", round(qtukey(1 - alpha, k, Inf), 5), "\n")
  for (j in seq_len(ncol(pairs))) {
    a <- yield[[pairs[1, j]]]
    b <- yield[[pairs[2, j]]]
    na <- length(a)
    nb <- length(b)
    rp <- rank(c(a, b))
    tp <- table(c(a, b))
    v <- na * nb / 12 * (na + nb + 1 - sum(tp^3 - tp) / ((na + nb) * (na + nb - 1)))
    q <- sqrt(2) * (sum(rp[1:na]) - na * (na + nb + 1) / 2) / sqrt(v)
    cat(sprintf("%s vs %s:  |q| = %.6f  %s\n", names(yield)[pairs[1, j]],
                names(yield)[pairs[2, j]], abs(q),
                pv(ptukey(abs(q), k, Inf, lower.tail = FALSE))))
  }
}

# All pairwise comparisons (Conover-Iman): differences between mean ranks
# against t with N - k degrees of freedom, using the adjusted T
s2 <- (sum(r^2) - N * (N + 1)^2 / 4) / (N - 1)
tails <- if (one_sided) 1 else 2
critical_t <- qt(alpha / tails, N - k, lower.tail = FALSE)
cat("Critical t (", N - k, " df) = ", round(critical_t, 6), "\n", sep = "")
for (j in seq_len(ncol(pairs))) {
  i1 <- pairs[1, j]
  i2 <- pairs[2, j]
  difference <- meanrank[i1] - meanrank[i2]
  d <- abs(difference)
  se <- sqrt(s2 * (N - 1 - Tadj) / (N - k)) * sqrt(1 / ni[i1] + 1 / ni[i2])
  comparison <- if (!one_sided) "vs" else if (difference > 0) ">" else "<"
  cat(sprintf("%s %s %s:  %.6f against %.6f  %s\n", names(yield)[i1], comparison,
              names(yield)[i2], d, critical_t * se,
              pv(tails * pt(d / se, N - k, lower.tail = FALSE))))
}

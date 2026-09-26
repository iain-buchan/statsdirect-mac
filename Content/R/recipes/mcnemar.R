# McNemar analyses paired binary outcomes; pairs must be independent of each other.
# The exact binomial test concerns the direction among discordant pairs. Its CI is
# for that conditional proportion, not a risk-difference or odds-ratio interval.
counts <- sd_matrix(lapply(sd_columns("scrap"), sd_numeric))
result <- mcnemar.test(counts, correct = FALSE)
print(result)
print(mcnemar.test(counts, correct = TRUE))
b <- counts[1, 2]; c <- counts[2, 1]
if (b + c > 0) {
  exact_result <- binom.test(b, b + c, p = 0.5, conf.level = confidence)
  print(exact_result)
}

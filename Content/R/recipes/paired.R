# Paired inference uses aligned complete pairs and independent pairs; inspect differences.
# Exact small-sample t inference assumes normally distributed differences.
# Missing pairs are omitted here; complete-case analysis can introduce selection bias.
columns <- lapply(sd_columns(), sd_numeric)
data <- sd_matrix(columns)
data <- data[complete.cases(data), , drop = FALSE]
x <- data[, 1]
if (ncol(data) == 2) {
  y <- data[, 2]
  result <- t.test(x, y, paired = TRUE, conf.level = confidence)
} else {
  result <- t.test(x, mu = 0, conf.level = confidence)
}
print(result)
# This reproduces the tail in the observed direction only. Choosing that direction
# after seeing the data is not a valid prespecified one-sided test. For a planned
# directional hypothesis, use t.test(..., alternative="greater") or "less" as specified.
one_sided_p <- result$p.value / 2
print(c(one_sided_p = one_sided_p))
if (isTRUE(sd_parameter("doAgreement", FALSE)) && ncol(data) == 2) {
  differences <- x - y
  paired_means <- (x + y) / 2
  mean_difference <- mean(differences)
  # Approximate limits for individual differences at the chosen coverage level,
  # assuming normal differences with stable mean/variance across measurement size.
  # These are NOT confidence limits for the mean or for the limits themselves.
  # Assess trends, proportional bias and practical acceptability separately.
  agreement_limits <- mean_difference + c(-1, 1) * qnorm((1 + confidence) / 2) * sd(differences)
  agreement <- c(mean_difference = mean_difference, lower = agreement_limits[1], upper = agreement_limits[2])
  print(agreement)
  pdf("agreement.pdf", width = 8, height = 5)
  tryCatch({
    plot(paired_means, differences, xlab = "Mean of paired measurements", ylab = "First minus second",
         ylim = range(c(differences, agreement_limits)), pch = 19)
    abline(h = mean_difference, col = "#23695f")
    abline(h = agreement_limits, lty = 2, col = "#23695f")
  }, finally = dev.off())
  cat("Agreement chart saved to", normalizePath("agreement.pdf"), "\n")
}

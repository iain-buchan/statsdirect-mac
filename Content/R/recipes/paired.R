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
one_sided_p <- result$p.value / 2  # Direction of the observed difference.
print(c(one_sided_p = one_sided_p))
if (isTRUE(sd_parameter("doAgreement", FALSE)) && ncol(data) == 2) {
  differences <- x - y
  paired_means <- (x + y) / 2
  mean_difference <- mean(differences)
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

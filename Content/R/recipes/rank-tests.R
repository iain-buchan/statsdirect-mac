# Rank methods still need design assumptions. Paired differences must be independent
# between pairs; the signed-rank location interpretation also assumes symmetry.
# Mann-Whitney is not simply a test of medians without additional shape assumptions.
# Independent-group tests require independence within and between the groups.
# Omission of missing observations does not establish absence of selection bias.
columns <- lapply(sd_columns(), sd_numeric)
if (operation == "Wilcoxon") {
  data <- sd_matrix(columns)
  data <- data[complete.cases(data), , drop = FALSE]
  differences <- if (ncol(data) == 2) data[, 1] - data[, 2] else data[, 1]
  result <- wilcox.test(differences, mu = 0, exact = NULL, correct = TRUE)
} else if (operation == "MannWhitney") {
  result <- wilcox.test(na.omit(columns[[1]]), na.omit(columns[[2]]), exact = NULL, correct = TRUE)
} else if (operation == "Smirnov") {
  result <- ks.test(na.omit(columns[[1]]), na.omit(columns[[2]]), exact = NULL)
} else {
  result <- kruskal.test(lapply(columns, na.omit))
}
print(result)
# Exact/asymptotic choices, ties and continuity corrections may differ from StatsDirect.

# Each row is an aligned pair; rows must be independent for this inference.
# Complete-case selection can introduce bias. Correlation is not agreement or causation.
data <- sd_matrix(lapply(sd_columns(), sd_numeric))
data <- data[complete.cases(data), , drop = FALSE]
method <- if (operation == "Spearman") "spearman" else "kendall"
result <- cor.test(data[, 1], data[, 2], method = method, exact = NULL)
print(result)
# R chooses its own exact/asymptotic algorithm; tied-data P values can differ from StatsDirect.

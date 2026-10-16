# Independent numerical reference for the selected BarPlotFrequency worked example.
# Every plotted value is checked; this file does not call the application recipe.
emit <- function(x) cat(formatC(as.double(x), digits = 8, format = "f"), "\n")
raw <- list(c(1, 2, 2, 3, 3, 3), c(1, 1, 2, 3))
counts <- sapply(raw, function(x) as.double(table(factor(x, levels = 1:3))))
proportions <- sweep(counts, 2, colSums(counts), "/")
values <- t(proportions)
emit(c(dim(counts), as.vector(counts), as.vector(proportions), dim(values), as.vector(values)))
category <- seq_len(ncol(values)) - 0.5
for (i in seq_len(nrow(values))) {
  lower <- category - 0.3 + (i - 1) * 0.3
  emit(c(rep(0, ncol(values)), values[i, ], lower, lower + 0.3))
}

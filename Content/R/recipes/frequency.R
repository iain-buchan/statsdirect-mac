# StatsDirect recipe: Frequencies, as the help shows it in R.
# From the help's R code (basic_descriptive_statistics/frequencies.htm); the data and settings above come from the run.
# data: response
# repeat: data
# settings: sort_by = sortBy, sort_order = sortOrder

# Frequencies and cumulative percentages for each selected column.
observed <- !is.na(response) & response != "* (missing)"
n <- sum(observed)
missing <- length(response) - n
counts <- table(response[observed])

# Numeric labels precede text, with ordinal spelling used to break ties.
labels <- names(counts)
number <- suppressWarnings(as.numeric(labels))
decimal <- grepl("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$", trimws(labels))
number[!decimal | !is.finite(number)] <- NA_real_
by_value <- order(is.na(number), number, labels, method = "radix")
descending <- identical(sort_order, "desc")
if (identical(sort_by, "frequency")) {
  count_key <- if (descending) -counts[by_value] else counts[by_value]
  by_value <- by_value[order(count_key, method = "radix")]
} else if (descending) {
  by_value <- rev(by_value)
}
counts <- counts[by_value, drop = FALSE]
print(counts)

cat("Total =", length(response))
if (missing > 0) cat(sprintf(" (of which %d missing: the percentages are of the other %d)", missing, n))
cat("\n")
cat("Value  Frequency  Relative %  Cumulative  Cumulative Relative %\n")
if (missing > 0) cat("* (missing)", missing, "NA NA NA\n")
cumulative <- cumsum(counts)
for (i in seq_along(counts)) {
  cat(names(counts)[i], counts[i], 100 * counts[i] / n, cumulative[i],
      100 * cumulative[i] / n, "\n")
}

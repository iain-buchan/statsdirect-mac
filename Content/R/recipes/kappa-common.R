# Use the report's saved grade order when available. Older records contain only
# the labels. Sort their numbers by value and their text by UTF-16 code units,
# as the report does, without depending on the locale in which R runs.
kappa_numeric_labels <- function(labels) {
  decimal <- trimws(labels)
  numeric <- grepl("^[+-]?(?:[0-9][0-9,]*(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$", decimal, perl = TRUE)
  value <- rep(NA_real_, length(labels))
  value[numeric] <- as.numeric(gsub(",", "", decimal[numeric], fixed = TRUE))
  value
}

kappa_grade_order <- function(labels, saved) {
  labels <- unique(as.character(labels[!is.na(labels)]))
  saved <- unlist(saved, use.names = FALSE)
  if (length(saved) == length(labels) && setequal(saved, labels)) return(saved)
  number <- kappa_numeric_labels(labels)
  ordinal <- vapply(iconv(enc2utf8(labels), from = "UTF-8", to = "UTF-16BE", toRaw = TRUE),
                    function(bytes) paste(sprintf("%02x", as.integer(bytes)), collapse = ""), "")
  labels[order(labels != "", !is.finite(number), ifelse(is.finite(number), number, 0), ordinal, method = "radix")]
}

# Invert the Pearson goodness-of-fit statistic for the three cells in
# Donner and Eliasziw's common correlation model, pooling disagreements.
kappa_donner_interval <- function(counts, confidence) {
  if (nrow(counts) != 2 || ncol(counts) != 2) return(NULL)
  observed <- round(c(counts[1, 1], counts[1, 2] + counts[2, 1], counts[2, 2]))
  if (observed[1] + observed[2] == 0 || observed[2] + observed[3] == 0) return(NULL)
  n <- sum(observed)
  p <- (observed[1] + observed[2] / 2) / n
  q <- 1 - p
  pq <- p * q
  minimum <- -min(p / q, q / p)
  estimate <- max(minimum, 1 - observed[2] / (2 * n * pq))
  critical <- qchisq(confidence, 1)
  nonzero <- observed > 0
  lack_of_fit <- function(pi) {
    expected <- n * pmax(0, c(p^2 + pi * pq, 2 * pq * (1 - pi), q^2 + pi * pq))
    sum((observed[nonzero] - expected[nonzero])^2 / expected[nonzero]) +
      sum(expected[!nonzero]) - critical
  }
  lower <- if (minimum < estimate && lack_of_fit(minimum) > 0)
    uniroot(lack_of_fit, c(minimum, estimate), tol = 1e-12)$root else minimum
  upper <- if (observed[2] > 0)
    uniroot(lack_of_fit, c(estimate, 1), tol = 1e-12)$root else 1
  c(lower, upper)
}

# StatsDirect recipe: F test of two variances, as the help shows it in R.
# From the help's R code (parametric_methods/f_variance_ratio.htm); the data and settings above come from the run.
# data: slight, marked

# F (variance ratio) test: the StatsDirect help example (scores of patients with
# slight or no symptoms and with marked symptoms) in R

# R's standard test. Its F is the first sample's variance over the second's, so
# the sample with the larger variance goes first to get StatsDirect's F; its P is
# two sided.
slight <- slight[!is.na(slight)]
marked <- marked[!is.na(marked)]
if (!exists("slight_title")) slight_title <- "First sample"
if (!exists("marked_title")) marked_title <- "Second sample"
# Match the report's two-pass double accumulation when ordering near ties.
report_variance <- function(x) {
  m <- Reduce(`+`, x) / length(x)
  Reduce(`+`, (x - m) * (x - m)) / (length(x) - 1)
}
if (report_variance(slight) > report_variance(marked)) {
  high <- slight; low <- marked
  high_title <- slight_title; low_title <- marked_title
} else {
  high <- marked; low <- slight
  high_title <- marked_title; low_title <- slight_title
}
f <- var.test(high, low)
f$data.name <- paste(high_title, "and", low_title)
print(f)

# The report's lines: each variance with its degrees of freedom, F, the upper
# tail P and its double, the two sided P
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
cat(high_title, "  DF =", length(high) - 1, "  Variance =", six(var(high)),
    "\n")
cat(low_title, "  DF =", length(low) - 1, "  Variance =", six(var(low)),
    "\n")
cat("F =", six(f$statistic), "\n")
p <- pf(f$statistic, f$parameter[1], f$parameter[2], lower.tail = FALSE)
cat(sprintf("Upper side P = %.4f   Two sided P = %.4f\n", p, 2 * min(p, 1 - p)))

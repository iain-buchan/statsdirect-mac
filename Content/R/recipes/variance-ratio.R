# StatsDirect recipe: F test of two variances, as the help shows it in R.
# From the help's R code (parametric_methods/f_variance_ratio.htm); the data and settings above come from the run.
# data: slight, marked

# F (variance ratio) test: the StatsDirect help example (scores of patients with
# slight or no symptoms and with marked symptoms) in R

# R's standard test. Its F is the first sample's variance over the second's, so
# the sample with the larger variance goes first to get StatsDirect's F; its P is
# two sided.
f <- var.test(marked, slight)
print(f)

# The report's lines: each variance with its degrees of freedom, F, the upper
# tail P and its double, the two sided P
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
cat("Marked symptoms   DF =", length(marked) - 1, "  Variance =", six(var(marked)),
    "\n")
cat("Slight/no symptoms   DF =", length(slight) - 1, "  Variance =", six(var(slight)),
    "\n")
cat("F =", six(f$statistic), "\n")
p <- pf(f$statistic, f$parameter[1], f$parameter[2], lower.tail = FALSE)
cat(sprintf("Upper side P = %.4f   Two sided P = %.4f\n", p, 2 * min(p, 1 - p)))
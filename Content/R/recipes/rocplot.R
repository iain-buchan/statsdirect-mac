# StatsDirect recipe: ROC Curve Analysis, as the help shows it in R.
# From the help's R code (nonparametric_methods/roc.htm); the data and settings above come from the run.
# data: present, absent

# ROC curve: the StatsDirect help example (Aziz et al. 1996, the sperm deformity
# index of men whose partners did and did not conceive; the test workbook's Graphics
# worksheet columns SDI conceived and SDI not conceived) in R
m <- length(present)                  # condition present (conceived): 42
n <- length(absent)                   # condition absent (not conceived): 116
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)

# Base R has no ROC function, but the area under the ROC curve is the probability
# that a randomly chosen positive scores higher than a randomly chosen negative
# (a tie counting a half), which is the rank sum statistic W that wilcox.test reports
# (the Mann-Whitney U) divided by m * n. The P value R prints with it tests the null of
# no difference between the groups, under which the area is 0.5.
w <- wilcox.test(present, absent)
print(w)
theta <- as.numeric(w$statistic) / (m * n)

# The curve: sensitivity against 1 - specificity with each observed value in turn
# as the cut-off, a test being positive at or above it. StatsDirect reads high
# values as positive because the mean is higher in the condition present group (with
# the groups the other way round it counts values at or below each cut-off as positive,
# which this script does not do).
cuts <- sort(unique(c(present, absent)))
sens <- sapply(cuts, function(k) mean(present >= k))
spec <- sapply(cuts, function(k) mean(absent < k))

# The area by the trapezoidal rule, from (1, 1) down the steps to (0, 0). With a
# step at every observed value this is the same number as the Wilcoxon estimate.
x <- c(0, rev(1 - spec), 1)
y <- c(0, rev(sens), 1)
auc <- sum(diff(x) * (y[-1] + y[-length(y)]) / 2)
cat("Area under ROC curve by extended trapezoidal rule =", six(auc), "\n")
cat("Wilcoxon estimate of area under ROC curve =", six(theta), "\n")

# DeLong's standard error: for each positive, the proportion of negatives it beats
# (a tie a half), and for each negative, the proportion of positives that beat it.
# The variances of these two sets of placements give the variance of the area.
beats <- outer(present, absent, function(p, a) (p > a) + (p == a) / 2)
se <- sqrt(var(rowMeans(beats)) / m + var(colMeans(beats)) / n)
ci <- pmin(1, pmax(0, theta + c(-1, 1) * qnorm(0.975) * se))   # kept within 0 to 1
cat(paste0("DeLong standard error = ", six(se), ": 95% CI = ", six(ci[1]), " to ",
           six(ci[2]), "\n"))

# The optimum cut-off: the observed value that maximises weight * sensitivity +
# specificity (the smallest such value if several tie); weight 1 treats the two
# as equally important. The cut-off calculator lets you move away from it.
weight <- 1
best <- which.max(weight * sens + spec)
cut <- cuts[best]
a <- sum(present >= cut)              # true positives
b <- sum(absent >= cut)               # false positives
cc <- m - a                           # false negatives (the report's c)
d <- n - b                            # true negatives
cat("Optimum cut-off point selected =", cut, "\n")
cat("Table at cut-off:   a =", a, "  b =", b, "\n")
cat("                    c =", cc, "  d =", d, "\n")

# Sensitivity, specificity and the predictive values at the cut-off, with the exact
# (Clopper-Pearson) 95% confidence limits that binom.test gives. When a proportion
# is 0 or 1 StatsDirect marks its limits as a 97.5% one-sided interval.
report <- function(label, r, N) {
  limits <- binom.test(r, N)$conf.int
  cat(paste0(label, " = ", six(r / N), " (", six(limits[1]), " to ", six(limits[2]),
             ")\n"))
}
report("sensitivity (95% CI)", a, m)
report("specificity (95% CI)", d, n)
report("Predictive value of +ve test", a, a + b)
report("Predictive value of -ve test", d, cc + d)

# With sensitivity weighted twice as important as specificity (weight 2)
best2 <- which.max(2 * sens + spec)
cat("Cut-off with weight 2 =", cuts[best2], "  sensitivity =", six(sens[best2]),
    "  specificity =", six(spec[best2]), "\n")

# The ROC plot: a marker at each cut-off, joined in order, the diagonal of no
# discrimination, and a larger marker at the optimum cut-off
plot(1 - spec, sens, type = "b", pch = 1, xlim = c(0, 1), ylim = c(0, 1), asp = 1,
     xlab = "1-Specificity", ylab = "Sensitivity", main = "ROC plot")
abline(0, 1)
points(1 - spec[best], sens[best], pch = 16, cex = 2)
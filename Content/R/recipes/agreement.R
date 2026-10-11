# StatsDirect recipe: Agreement of raters (intraclass correlation), as the help shows it in R.
# From the help's R code (agreement/intraclass.htm); the data and settings above come from the run.
# data: raters...
# settings: confidence = ci

flow <- do.call(cbind, raters)
# Agreement of continuous measurements: the StatsDirect help example (Bland and Altman
# 1996a, four peak flow readings on each of 20 children; the test workbook's Agreement
# worksheet columns 1st to 4th) in R
pct <- paste0(100 * confidence, "%")
n <- nrow(flow)
m <- ncol(flow)

# R's standard one way analysis of variance of the readings by child: its between
# children and residual (within children) mean squares give the one way random
# effects intra-class correlation and the within-subjects standard deviation
long <- data.frame(reading = as.vector(flow), child = factor(rep(1:n, m)))
a <- anova(lm(reading ~ child, data = long))
print(a)

# The report's lines to 6 places. The interval for the coefficient comes from the F
# distribution of MSB/MSW on n - 1 and n(m - 1) degrees of freedom
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
msb <- a["child", "Mean Sq"]
msw <- a["Residuals", "Mean Sq"]
icc <- (msb - msw) / (msb + (m - 1) * msw)
f <- msb / msw
fu <- qf((1 + confidence) / 2, n - 1, n * (m - 1))
fl <- qf(0.025, n - 1, n * (m - 1))
cat("Intra-class correlation coefficient (one way random effects) =", six(icc),
    "(95% CI =", six((f / fu - 1) / (f / fu + m - 1)), "to",
    six((f / fl - 1) / (f / fl + m - 1)), ")\n")
sw <- sqrt(msw)
cat("Estimated within-subjects standard deviation =", six(sw), "\n")

# Each child's standard deviation against the child's mean: Kendall's tau b, with the
# continuity corrected normal approximation to its P value (the ties rule out the
# exact test)
child_sd <- apply(flow, 1, sd)
child_mean <- rowMeans(flow)
kt <- cor.test(child_sd, child_mean, method = "kendall", exact = FALSE,
               continuity = TRUE)
cat("For within-subjects sd vs. mean, Kendall's tau b =", six(kt$estimate),
    " two sided", pv(kt$p.value), "\n")

# The repeatability coefficient: for 95% of pairs of readings on the same child, the
# two readings differ by less than root 2 times 1.96 times the within-subjects
# standard deviation
cat("Repeatability (for alpha = 0.05) =", six(sqrt(2) * qnorm((1 + confidence) / 2) * sw), "\n")

# The report's three plots: each child's standard deviation, then the largest
# difference between two of the child's readings, against the child's mean; and the
# ordered sums of the absolute deviations of each child's readings from their mean
# against chi-square quantiles on m - 1 degrees of freedom
largest <- apply(flow, 1, function(r) {
  d <- outer(r, r, "-")[upper.tri(diag(m))]
  d[which.max(abs(d))]
})
par(mfrow = c(1, 3))
plot(child_mean, child_sd, xlab = "subject mean", ylab = "subject standard deviation",
     main = "Repeatability Plot")
plot(child_mean, largest, xlab = "subject mean", ylab = "largest difference",
     main = "Agreement Plot")
abline(h = mean(largest), lty = 2)
plot(qchisq(seq(0.01, 0.99, length.out = n), m - 1),
     sort(rowSums(abs(flow - child_mean))), xlab = paste0("chi-square (", m - 1, ")"),
     ylab = "Sum(|x-mean(x)|)", main = "Q-Q Plot")
# StatsDirect recipe: Agreement of raters (intraclass correlation), as the help shows it in R.
# From the help's R code (agreement/intraclass.htm); the data and settings above come from the run.
# data: raters...
# settings: confidence = ci
# hand-edited: omit incomplete subjects before all summaries and plots

flow <- do.call(cbind, raters)
flow <- flow[complete.cases(flow), , drop = FALSE]
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
# A figure that cannot be calculated is shown as *, as the report shows it: tau and
# its P are undefined when every subject has the same standard deviation or mean.
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
msb <- a["child", "Mean Sq"]
msw <- a["Residuals", "Mean Sq"]
icc <- (msb - msw) / (msb + (m - 1) * msw)
f <- msb / msw
fu <- qf((1 + confidence) / 2, n - 1, n * (m - 1))
fl <- qf((1 - confidence) / 2, n - 1, n * (m - 1))
cat("Intra-class correlation coefficient (one way random effects) =", six(icc),
    paste0("(", pct, " CI ="), six((f / fu - 1) / (f / fu + m - 1)), "to",
    six((f / fl - 1) / (f / fl + m - 1)), ")\n")
sw <- sqrt(msw)
cat("Estimated within-subjects standard deviation =", six(sw), "\n")

# Kendall's tau between each subject's standard deviation and mean. The report
# treats computed values equal to 1 part in 10^12 as ties, with an additional
# rounding allowance for the standard deviations.
child_sd <- apply(flow, 1, sd)
child_mean <- rowMeans(flow)
same <- function(v, tolerance = 0) {
  o <- order(v)
  for (j in seq_along(o)[-1]) {
    a <- v[o[j - 1]]; b <- v[o[j]]
    if (abs(a - b) <= max(tolerance, 1e-12 * max(abs(a), abs(b)))) v[o[j]] <- a
  }
  v
}
ksd <- same(child_sd, 4e-15 * max(abs(flow)))
kmean <- same(child_mean)
tied <- anyDuplicated(ksd) > 0 || anyDuplicated(kmean) > 0
kt <- cor.test(ksd, kmean, method = "kendall", exact = FALSE, continuity = TRUE)
if (!tied && n <= 170) {
  # The distribution is symmetric. Use its small tail directly rather than
  # subtracting an almost-one CDF, which can lose a tiny positive-association P.
  kt$p.value <- cor.test(ksd, if (kt$estimate > 0) -kmean else kmean,
                         method = "kendall", exact = TRUE)$p.value
} else if (!tied && n <= 1000) {
  # The report counts permutations through 1,000 subjects. R's exact Kendall
  # test divides by n!, which overflows beyond 170. Normalised probabilities
  # avoid that overflow: inserting subject j adds 0 to j-1 discordant pairs.
  pairs <- n * (n - 1) / 2
  s <- round(kt$estimate * pairs)
  if (abs(s) == pairs) kt$p.value <- min(1, 2 * exp(-lgamma(n + 1))) else {
    p <- 1
    for (j in 2:n) {
      cs <- cumsum(c(p, numeric(j - 1)))
      next_p <- (cs - c(numeric(j), cs)[seq_along(cs)]) / j
      half <- seq_len((length(next_p) + 1) %/% 2)
      next_p[length(next_p) + 1 - half] <- next_p[half]
      p <- pmax(0, next_p)
    }
    kt$p.value <- min(1, 2 * sum(p[seq_len((pairs - abs(s)) %/% 2 + 1)]))
  }
} else if (!tied) {
  # Above 1,000 subjects the report takes the tail of S from an Edgeworth series
  # in |S| - 1, whose figures this follows.
  s <- abs(round(kt$estimate * n * (n - 1) / 2))
  x <- (s - 1) / sqrt((2 * n^3 + 3 * n^2 - 5 * n - 6) / 18)
  h <- numeric(15); h[1] <- x; h[2] <- x^2 - 1
  for (i in 3:15) h[i] <- x * h[i - 1] - (i - 1) * h[i - 2]
  inverse_n <- 1 / n
  sc1 <- h[3] * (-0.09 + inverse_n * (0.045 + inverse_n * (-0.5325 + inverse_n * 0.506)))
  sc2 <- h[5] * (0.036735 + inverse_n * (-0.036735 + inverse_n * 0.3214)) +
    h[7] * (0.00405 + inverse_n * (-0.023336 + inverse_n * 0.07787))
  sc3 <- h[9] * (-0.0033061 - inverse_n * 0.0065166) + h[11] * (-0.0001215 + inverse_n * 0.0025927) +
    inverse_n * (h[13] * 0.00014878 + h[15] * 0.0000027338)
  sc <- inverse_n * (sc1 + inverse_n * (sc2 + inverse_n * sc3))
  upper_tail <- min(1, max(0, pnorm(x, lower.tail = FALSE) + sc * 0.398942 * exp(-0.5 * x^2)))
  kt$p.value <- min(1, 2 * upper_tail)
}
cat("For within-subjects sd vs. mean, Kendall's tau", if (tied) "b =" else "=", six(kt$estimate),
    " two sided", pv(kt$p.value), "\n")

# The selected proportion of differences between repeated readings lies within
# this repeatability coefficient, under the normal model.
cat(sprintf("Repeatability (for alpha = %g) = ", 1 - confidence),
    six(sqrt(2) * qnorm((1 + confidence) / 2) * sw), "\n", sep = "")

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

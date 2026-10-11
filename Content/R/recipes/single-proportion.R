# StatsDirect recipe: Single proportion with its exact and approximate limits, as the help shows it in R.
# From the help's R code (proportions/single.htm); the data and settings above come from the run.
# settings: n = n, r = r, pi0 = qpi, confidence = cco
# hand-edited: the confidence level and the data come from the run, as the header says

# Single proportion: the StatsDirect help example (Armitage and Berry 1994, p. 119,
# 65 of 100 patients preferred analgesic Y) in R

# R's standard test gives the exact (Clopper-Pearson) confidence interval and an
# exact two sided P. StatsDirect's two sided P is the total probability of the
# counts no more likely than the observed count; the two agree here and in the
# other cases tried (for example 7 of 12 against 0.3: 0.0524 from both).
pct <- paste0(100 * confidence, "%")
print(binom.test(r, n, p = pi0))

# The report's lines, to 6 decimal places, P values to 4
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
ci <- binom.test(r, n, p = pi0)$conf.int
cat("Total = ", n, ",  response = ", r, "\n", sep = "")
cat("Proportion =", six(r / n), "\n")
cat("Exact (Clopper-Pearson)", pct, "confidence interval =", six(ci[1]), "to", six(ci[2]),
    "\n")

# One sided P: the smaller of the two tail probabilities, each including the
# observed count (alternative = "less" and "greater" in binom.test give them)
lower <- pbinom(r, n, pi0)                # P(count <= r)
upper <- pbinom(r - 1, n, pi0, lower.tail = FALSE)   # P(count >= r)
cat("Binomial one sided", pv(min(lower, upper)), "\n")
cat("Binomial two sided", pv(binom.test(r, n, p = pi0)$p.value), "\n")

# The Wilson score interval, which prop.test gives when its continuity
# correction is turned off
wilson <- prop.test(r, n, correct = FALSE)$conf.int
cat("Approximate (Wilson)", pct, "mid-P confidence interval =", six(wilson[1]), "to",
    six(wilson[2]), "\n")

# Mid-P: half the probability of the observed count is taken off the smaller
# tail, and the two sided mid-P is twice the one sided
mid <- min(lower, upper) - dbinom(r, n, pi0) / 2
cat("Binomial one sided mid-", pv(mid), "\n", sep = "")
cat("Binomial two sided mid-", pv(2 * mid), "\n", sep = "")
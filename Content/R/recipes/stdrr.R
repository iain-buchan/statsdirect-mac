# StatsDirect recipe: Standardized rates of two groups compared, as the help shows them in R.
# From the help's R code (rates/standardize_compare_two_rates.htm); the data and settings above come from the run.
# data: a = a, pt1 = pt1, b = b, pt2 = pt2, ref = ref, strata = strata
# settings: per = nunit, confidence = cco

per <- as.numeric(per)
if (is.null(ref)) ref <- pt2   # the reference population: the non-exposed group when none is given
if (is.null(strata)) strata <- paste("Stratum", seq_along(a))
# Standardize and compare two rates: the StatsDirect help example (Newman 2001, deaths
# in a cohort of men treated for schizophrenia and in the Alberta population, in eight
# age strata; the test workbook's Rates worksheet columns d1, pt1, d2, pt2, ref and
# age strata) in R
pct <- paste0(100 * confidence, "%")
k <- length(a)
z <- qnorm((1 + confidence) / 2)     # for 95% confidence intervals
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)

# R's standard test compares the two crude rates: its estimate is the ratio of the
# rates and its confidence interval is the exact one of the report, from the binomial
# distribution of the exposed deaths among all deaths, conditional on their total
crude <- poisson.test(c(sum(a), sum(b)), c(sum(pt1), sum(pt2)), conf.level = confidence)
print(crude)

# The same test on each stratum gives the stratum rate ratios with their exact
# intervals; the weight of a stratum is its share of the reference population
rr <- (a / pt1) / (b / pt2)
exact <- sapply(1:k, function(i) {
  poisson.test(c(a[i], b[i]), c(pt1[i], pt2[i]), conf.level = confidence)$conf.int
})
w <- ref / sum(ref)
cat("Stratum rate ratios with exact Poisson", pct, "CI and weights\n")
print(data.frame(stratum = c(1:k, "All"), RR = six(c(rr, crude$estimate)),
                 lower = six(c(exact[1, ], crude$conf.int[1])),
                 upper = six(c(exact[2, ], crude$conf.int[2])), weight = six(c(w, 1)),
                 label = c(strata, "All (crude)")), row.names = FALSE)

# The crude rates with exact Poisson intervals: poisson.test on one count gives the same
# limits as the chi-square (gamma) quantiles of the report's formula
crude_ci <- function(events, time) {
  r <- poisson.test(events, time, conf.level = confidence)
  per * c(r$estimate, r$conf.int)
}
e <- crude_ci(sum(a), sum(pt1))
cat("Crude rate exposed =", six(e[1]), "\n")
cat("Exact", pct, "CI =", six(e[2]), "to", six(e[3]), "\n")
ne <- crude_ci(sum(b), sum(pt2))
cat("Crude rate not exposed =", six(ne[1]), "\n")
cat("Exact", pct, "CI =", six(ne[2]), "to", six(ne[3]), "\n")

# Base R has no standardisation function, so the directly standardised rates follow
# the formulae above: each population's stratum rates weighted by the reference
# population, with the Poisson variance of that weighted sum (Chiang) and a normal
# interval; the ratio of the two rates has a normal interval on the log scale
dsr <- function(events, time) {
  rate <- sum(w * events / time)
  v <- sum(w^2 * events / time^2)
  c(rate = rate, v = v, lower = rate - z * sqrt(v), upper = rate + z * sqrt(v))
}
s1 <- dsr(a, pt1)
s2 <- dsr(b, pt2)
cat("Standardized rate exposed =", six(per * s1["rate"]), "\n")
cat("Approximate", pct, "CI =", six(per * s1["lower"]), "to", six(per * s1["upper"]), "\n")
cat("Standardized rate not exposed =", six(per * s2["rate"]), "\n")
cat("Approximate", pct, "CI =", six(per * s2["lower"]), "to", six(per * s2["upper"]), "\n")
srr <- s1["rate"] / s2["rate"]
se_log <- sqrt(s1["v"] / s1["rate"]^2 + s2["v"] / s2["rate"]^2)
cat("Standardized rate ratio =", six(srr), "\n")
cat("Approximate", pct, "CI =", six(exp(log(srr) - z * se_log)), "to",
    six(exp(log(srr) + z * se_log)), "\n")

# The plot that follows in the report: each stratum's rate ratio and exact interval,
# a square that grows with the stratum's weight, then the crude and the standardized
# ratios as diamonds, on a log scale with a line at a ratio of one
# (a stratum with no exposed events has lower limit 0, which a log axis cannot show)
est <- c(rr, crude$estimate, srr)
lower <- c(exact[1, ], crude$conf.int[1], exp(log(srr) - z * se_log))
upper <- c(exact[2, ], crude$conf.int[2], exp(log(srr) + z * se_log))
y <- (k + 2):1
par(mar = c(5, 7, 4, 2))
plot(NA, xlim = range(lower, upper), ylim = c(0.5, k + 2.5), log = "x", yaxt = "n",
     ylab = "", xlab = paste0("rate ratio (", pct, " confidence interval)"),
     main = "Stratified rate ratio plot (direct standardization)")
axis(2, at = y, labels = c(strata, "All (crude)", "Standardized"), las = 1,
     tick = FALSE)
abline(v = 1, lty = 3)
segments(lower, y, upper, y)
points(rr, y[1:k], pch = 15, cex = 0.5 + 2 * sqrt(w / max(w)))
points(est[k + 1:2], y[k + 1:2], pch = 18, cex = 2.5)
abline(v = srr, lty = 2)

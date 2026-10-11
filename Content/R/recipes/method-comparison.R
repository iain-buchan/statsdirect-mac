# StatsDirect recipe: Method comparison regression (Deming) with the mcr package, as the help shows it in R.
# From the help's R code (agreement/mcr.htm); the data and settings above come from the run.
# data: plasma = testData, serum = referenceData
# settings: error_ratio = error-ratio, confidence = ci, seed = seed, do.deming.jackknife = do.deming.jackknife, do.deming.bootstrap = do.deming.bootstrap, do.deming.analytical = do.deming.analytical, do.wdeming.jackknife = do.wdeming.jackknife, do.wdeming.nestedbootstrap = do.wdeming.nestedbootstrap, do.paba = do.paba, do.paba.nestedbootstrap = do.paba.nestedbootstrap, do.pabalarge = do.pabalarge, do.pabalarge.nestedbootstrap = do.pabalarge.nestedbootstrap

# Method comparison regression: the StatsDirect help example (the creatinine data of
# the mcr package, serum and plasma creatinine in 108 subjects; the test workbook's
# Agreement worksheet columns Serum Creatinine and Plasma Creatinine hold the same
# pairs) in R. StatsDirect runs this analysis through the mcr package, so install it
# first with install.packages("mcr")
if (!requireNamespace("mcr", quietly = TRUE)) install.packages("mcr", repos = "https://cloud.r-project.org")
library(mcr)

# Deming regression of the test method (plasma) on the reference method (serum) with
# an error ratio of 1, its standard errors and confidence intervals from Linnet's
# jackknife: the package's summary, then its coefficient table to 6 places
# the regressions the run asked for, each by the package, from the run's seed where the limits are bootstrapped
chosen <- names(Filter(isTRUE, list(do.deming.jackknife = do.deming.jackknife, do.deming.bootstrap = do.deming.bootstrap, do.deming.analytical = do.deming.analytical, do.wdeming.jackknife = do.wdeming.jackknife, do.wdeming.nestedbootstrap = do.wdeming.nestedbootstrap, do.paba = do.paba, do.paba.nestedbootstrap = do.paba.nestedbootstrap, do.pabalarge = do.pabalarge, do.pabalarge.nestedbootstrap = do.pabalarge.nestedbootstrap)))   # the regressions the run ticked
regressions <- list(do.deming.jackknife = c("Deming", "jackknife"), do.deming.bootstrap = c("Deming", "bootstrap"), do.deming.analytical = c("Deming", "analytical"), do.wdeming.jackknife = c("WDeming", "jackknife"), do.wdeming.nestedbootstrap = c("WDeming", "nestedbootstrap"), do.paba = c("PaBa", "bootstrap"), do.paba.nestedbootstrap = c("PaBa", "nestedbootstrap"), do.pabalarge = c("PaBaLarge", "bootstrap"), do.pabalarge.nestedbootstrap = c("PaBaLarge", "nestedbootstrap"))
set.seed(seed)
fits <- lapply(chosen, function(name) mcreg(serum, plasma, error.ratio = error_ratio, method.reg = regressions[[name]][1], method.ci = regressions[[name]][2], alpha = 1 - confidence, mref.name = "Reference", mtest.name = "Test"))
for (fit in fits) invisible(printSummary(fit))
fit <- fits[[1]]
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
est <- getCoefficients(fit)
cat("Sample size:", length(serum), "\n")
for (term in c("Slope", "Intercept")) {
  cat(paste0(term, ":"), six(est[term, "EST"]), six(est[term, "SE"]),
      six(est[term, "LCI"]), "to", six(est[term, "UCI"]), "\n")
}

# The same arithmetic without the package. With an error ratio of 1 the Deming line
# is the orthogonal regression, from the sums of squares and products about the
# means. The jackknife refits the line leaving each pair out in turn; the standard
# error is that of the pseudo-values n b - (n - 1) b(-i) over root n, and the limits
# use t on n - 2 degrees of freedom (Linnet 1993)
if ("do.deming.jackknife" %in% chosen) {
deming <- function(x, y) {
  sxx <- sum((x - mean(x))^2)
  syy <- sum((y - mean(y))^2)
  sxy <- sum((x - mean(x)) * (y - mean(y)))
  b <- (syy - sxx + sqrt((syy - sxx)^2 + 4 * sxy^2)) / (2 * sxy)
  c(Intercept = mean(y) - b * mean(x), Slope = b)
}
n <- length(serum)
whole <- deming(serum, plasma)
left_out <- t(sapply(1:n, function(i) deming(serum[-i], plasma[-i])))
pseudo <- n * rep(whole, each = n) - (n - 1) * left_out
se <- apply(pseudo, 2, sd) / sqrt(n)
for (term in c("Slope", "Intercept")) {
  cat(paste0(term, ":"), six(whole[term]), six(se[term]),
      six(whole[term] - qt(0.975, n - 2) * se[term]), "to",
      six(whole[term] + qt(0.975, n - 2) * se[term]), "\n")
}
}

# The report's plot: the test method against the reference method with the Deming
# line, its confidence band and the line of identity
plot(fit, x.lab = "Reference", y.lab = "Test")
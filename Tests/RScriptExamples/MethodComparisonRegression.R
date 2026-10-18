# Method comparison regression: the StatsDirect help example (the creatinine data of
# the mcr package, serum and plasma creatinine in 108 subjects; the test workbook's
# Agreement worksheet columns Serum Creatinine and Plasma Creatinine hold the same
# pairs) in R. StatsDirect runs this analysis through the mcr package, so install it
# first with install.packages("mcr")
if (!requireNamespace("mcr", quietly = TRUE)) install.packages("mcr", repos = "https://cloud.r-project.org")
library(mcr)
data(creatinine)
complete <- complete.cases(creatinine)
serum <- creatinine$serum.crea[complete]
plasma <- creatinine$plasma.crea[complete]

# Deming regression of the test method (plasma) on the reference method (serum) with
# an error ratio of 1, its standard errors and confidence intervals from Linnet's
# jackknife: the package's summary, then its coefficient table to 6 places
fit <- mcreg(serum, plasma, error.ratio = 1, method.reg = "Deming",
             method.ci = "jackknife", mref.name = "Serum Creatinine",
             mtest.name = "Plasma Creatinine")
invisible(printSummary(fit))

# The same arithmetic without the package, as a check on it that prints nothing. With an error
# ratio of 1 the Deming line is the orthogonal regression from the sums of squares and products
# about the means; the jackknife refits the line leaving each pair out in turn, the standard error
# being that of the pseudo-values n b - (n - 1) b(-i) over root n (Linnet 1993).
deming <- function(x, y) {
  sxx <- sum((x - mean(x))^2); syy <- sum((y - mean(y))^2); sxy <- sum((x - mean(x)) * (y - mean(y)))
  b <- (syy - sxx + sqrt((syy - sxx)^2 + 4 * sxy^2)) / (2 * sxy)
  c(Intercept = mean(y) - b * mean(x), Slope = b)
}
n <- length(serum)
whole <- deming(serum, plasma)
left_out <- t(sapply(1:n, function(i) deming(serum[-i], plasma[-i])))
pseudo <- n * rep(whole, each = n) - (n - 1) * left_out
se <- apply(pseudo, 2, sd) / sqrt(n)
est <- getCoefficients(fit)
stopifnot(isTRUE(all.equal(unname(whole[c("Slope", "Intercept")]), unname(est[c("Slope", "Intercept"), "EST"]), tolerance = 1e-8)),
          isTRUE(all.equal(unname(se[c("Slope", "Intercept")]), unname(est[c("Slope", "Intercept"), "SE"]), tolerance = 1e-6)))

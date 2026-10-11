# StatsDirect recipe: Simple linear regression with its limits, as the help shows it in R.
# From the help's R code (regression_and_correlation/simple_linear.htm); the data and settings above come from the run.
# data: increase, weight
# settings: confidence = gamma
# hand-edited: the confidence level and the data come from the run, as the header says

# Simple linear regression and correlation: the StatsDirect help example (Armitage
# and Berry 1994, birth weight and percentage weight gain of 32 babies) in R

# R's standard regression: the coefficients, their standard errors and t tests
pct <- paste0(100 * confidence, "%")
fit <- lm(increase ~ weight)
print(summary(fit))
print(confint(fit))

# R's correlation test gives r, its Fisher z interval, t and the two sided P
print(cor.test(weight, increase))

# The report's lines to 6 places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
b <- coef(fit)
se <- summary(fit)$coefficients["weight", "Std. Error"]
n <- length(weight)
ct <- cor.test(weight, increase, conf.level = confidence)
cat("Equation: % Increase =", six(b[2]), "Birth Weight +", six(b[1]), "\n")
cat("Standard Error of slope =", six(se), "\n")
cat(pct, "CI for population value of slope =", six(confint(fit)[2, 1]), "to",
    six(confint(fit)[2, 2]), "\n")
cat("Correlation coefficient (r) =", six(ct$estimate), " (r2 =", six(ct$estimate^2),
    ")\n")
cat(pct, "CI for r (Fisher's z transformed) =", six(ct$conf.int[1]), "to",
    six(ct$conf.int[2]), "\n")
cat("t with", n - 2, "DF =", six(ct$statistic), "\n")
cat("Two sided", pv(ct$p.value), "\n")

# Power of the test of r at the 5% level: Fisher's z of r is about normal with
# standard deviation 1 / root(n - 3), so the power against zero is the two tails
# beyond the 5% points
z <- abs(atanh(ct$estimate)) * sqrt(n - 3)
power <- pnorm(z - qnorm((1 + confidence) / 2)) + pnorm(-z - qnorm((1 + confidence) / 2))
cat("Power (for 5% significance) =",
    paste0(formatC(100 * power, digits = 2, format = "f"), "%"), "\n")
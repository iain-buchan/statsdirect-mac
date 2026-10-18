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
print(confint(fit, level = confidence))

# R's correlation test gives r, its Fisher z interval, t and the two sided P
ct <- cor.test(weight, increase, conf.level = confidence)
print(ct)

# The report's lines to 6 places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
b <- coef(fit)
se <- summary(fit)$coefficients["weight", "Std. Error"]
n <- length(weight)
cat("Equation: % Increase =", six(b[2]), "Birth Weight +", six(b[1]), "\n")
cat(pct, "CI for population value of slope =", six(confint(fit, level = confidence)[2, 1]), "to",
    six(confint(fit, level = confidence)[2, 2]), "\n")
cat("R squared =", six(ct$estimate^2), "\n")

# Power of the test of r at the 5% level: Fisher's z of r is about normal with
# standard deviation 1 / root(n - 3), so the power against zero is the two tails
# beyond the 5% points
z <- abs(atanh(ct$estimate)) * sqrt(n - 3)
power <- pnorm(z - qnorm(0.975)) + pnorm(-z - qnorm(0.975))
cat("Power (for 5% significance) =",
    paste0(formatC(100 * power, digits = 2, format = "f"), "%"), "\n")

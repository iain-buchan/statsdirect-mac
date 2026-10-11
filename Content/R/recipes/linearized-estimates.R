# StatsDirect recipe: Linearized regression estimates, as the help shows them in R.
# From the help's R code (regression_and_correlation/linear_estimates.htm); the data and settings above come from the run.
# data: kwh, size
# settings: model = model

cat("The model fitted in StatsDirect:", c("Exponential", "Geometric / power", "Hyperbolic")[as.integer(model) + 1], "\n")   # the help fits all three
# Linearized regression estimates: an illustration with the electricity
# consumption and home size data of the polynomial regression topic (McClave and
# Dietrich 1991, the test workbook's Home Size and KW Hrs/Mnth) in R

# Each model is a straight line after a transformation, fitted by ordinary least
# squares on the transformed scale; R's standard regression gives the line, its
# correlation coefficient and the standard error of the estimate (the residual
# standard error on the transformed scale)
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
report <- function(model, fit, a, b) {
  cat(model, "\n")
  cat("A =", six(a), "  B =", six(b), "\n")
  r <- sqrt(summary(fit)$r.squared)
  cat("Correlation coefficient (r) =", six(r), "  (r2 =", six(r^2), ")\n")
  cat("Standard error of estimate =", six(summary(fit)$sigma), "\n")
}

# Exponential, Y = a exp(b x): log Y against x, so A is exp of the intercept
fit <- lm(log(kwh) ~ size)
report("(Exponential)  Y = a * exp(b * x)", fit, exp(coef(fit)[1]), coef(fit)[2])

# Geometric (power), Y = a x^b: log Y against log x
fit <- lm(log(kwh) ~ log(size))
report("(Geometric / Power)  Y = a * x^b", fit, exp(coef(fit)[1]), coef(fit)[2])

# Hyperbolic, Y = x / (a + b x): 1/Y against 1/x, so a is the slope and b the
# intercept
fit <- lm(I(1 / kwh) ~ I(1 / size))
report("(Hyperbolic)  Y = x / (a + b * x)", fit, coef(fit)[2], coef(fit)[1])
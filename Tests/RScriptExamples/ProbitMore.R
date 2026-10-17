# Probit analysis, logit model: the StatsDirect help example (Finney 1971, age at
# menarche of 3918 Warsaw girls) in R
age <- c(9.21, 10.21, 10.58, 10.83, 11.08, 11.33, 11.58, 11.83, 12.08, 12.33, 12.58,
         12.83, 13.08, 13.33, 13.58, 13.83, 14.08, 14.33, 14.58, 14.83, 15.08, 15.33,
         15.58, 15.83, 17.58)
girls <- c(376, 200, 93, 120, 90, 88, 105, 111, 100, 93, 100, 108, 99, 106, 105, 117,
           98, 97, 120, 102, 122, 111, 94, 114, 1049)
menses <- c(0, 0, 0, 2, 2, 5, 10, 17, 16, 29, 39, 51, 47, 67, 81, 88, 79, 90, 113, 95,
            117, 107, 92, 112, 1049)

# R's standard model for a proportion responding at each dose level: a binomial
# regression with the logit link (the doses are ages here, not logged)
fit <- glm(cbind(menses, girls - menses) ~ age, family = binomial)
# One more iteration from the converged coefficients leaves them unchanged and
# gives the standard errors from the final weights, as the report computes them
fit <- glm(cbind(menses, girls - menses) ~ age, family = binomial, start = coef(fit))
print(summary(fit))

# The report's lines to 6 places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
a <- coef(fit)[1]
b <- coef(fit)[2]
v <- vcov(fit)
# Evaluate the expected information at the final fitted probabilities, rather
# than retain the penultimate IRLS weights cached by glm's summary method.
X <- cbind(1, age)
probability <- unname(fitted(fit))
v <- solve(crossprod(X, X * (girls * probability * (1 - probability))))
# StatsDirect follows Finney in taking the logit as half the log odds, so that its
# scale is close to the probit's: its constant and slope are half of R's
cat("constant =", six(a / 2), "\n")
cat("slope =", six(b / 2), "\n")

# The dose for a given proportion p is (logit(p) - a) / b; its confidence interval
# without heterogeneity is Fieller's, from the variances and covariance of a and b
dose_for <- function(p) (qlogis(p) - a) / b
fieller <- function(p, conf = 0.95) {
  m <- dose_for(p)
  z <- qnorm((1 + conf) / 2)
  g <- z^2 * v[2, 2] / b^2
  vm <- v[1, 1] + 2 * m * v[1, 2] + m^2 * v[2, 2]
  half <- z / abs(b) * sqrt(vm - g * (v[1, 1] - v[1, 2]^2 / v[2, 2]))
  centre <- m + g * (m + v[1, 2] / v[2, 2]) / (1 - g)
  c(centre - half / (1 - g), centre + half / (1 - g))
}
cat("Median * Dose =", six(dose_for(0.5)), "\n")
cat("Confidence interval (No Heterogeneity) =", six(fieller(0.5)[1]), "to",
    six(fieller(0.5)[2]), "\n")
cat("* Dose for centile 90 =", six(dose_for(0.9)), "\n")
cat("Confidence interval (No Heterogeneity) =", six(fieller(0.9)[1]), "to",
    six(fieller(0.9)[2]), "\n")

# Heterogeneity of the observed proportions about the fitted curve: Pearson's
# chi-square with n - 2 degrees of freedom; the test of the slope is b over its
# standard error
chi <- sum(residuals(fit, type = "pearson")^2)
cat("Chi2 (heterogeneity of deviations from model) =", six(chi),
    paste0("(", fit$df.residual, " df)"),
    pv(pchisq(chi, fit$df.residual, lower.tail = FALSE)), "\n")
t_slope <- b / sqrt(v[2, 2])
cat("t for slope =", six(t_slope), paste0("(", fit$df.residual, " df)"),
    pv(2 * pt(-abs(t_slope), fit$df.residual)), "\n")

# The additional-statistics report lists each binomial fitted count and residual.
# Obtain these directly from R's independent glm fit.
working_weights <- 4 * girls * probability * (1 - probability)
working_response <- (a + b * age) / 2 + (menses / girls - probability) / (2 * probability * (1 - probability))
x_bar <- weighted.mean(age, working_weights)
y_bar <- weighted.mean(working_response, working_weights)
cat("Weighted Sxx =", six(sum(working_weights * (age-x_bar)^2)), "; Sxy =",
    six(sum(working_weights * (age-x_bar) * (working_response-y_bar))), "; Syy =",
    six(sum(working_weights * (working_response-y_bar)^2)), "\n")
cat("Variance of slope =", six(v[2,2]/4), "; standard error =", six(sqrt(v[2,2])/2), "\n")
dose_response_table <- data.frame(index = seq_along(girls), subjects = girls, responses = menses,
  expected = unname(fitted(fit)) * girls, deviation = menses - unname(fitted(fit)) * girls)
print(dose_response_table, row.names = FALSE)

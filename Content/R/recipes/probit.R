# StatsDirect recipe: Probit Model, as the help shows it in R.
# From the help's R code (regression_and_correlation/probit_analysis.htm); the data and settings above come from the run.
# data: age, girls, menses
# settings: confidence = conf, log_doses = calc-log10-doses, nc = nc, nrc = nrc, centile = qld

if (isTRUE(log_doses)) age <- log10(age)   # the doses as logarithms, as the run asked; the doses found are given back as doses
back <- if (isTRUE(log_doses)) function(v) 10^v else identity
if (!is.null(nc) && !is.null(nrc) && nc > 0 && nrc > 0) cat("NOTE: the report allows for the natural response of", nrc, "of", nc, "controls; this script fits the responses as they are\n")
# Probit analysis, logit model: the StatsDirect help example (Finney 1971, age at
# menarche of 3918 Warsaw girls) in R

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
cat("Median * Dose =", six(back(dose_for(0.5))), "\n")
cat("Confidence interval (No Heterogeneity) =", six(back(fieller(0.5)[1])), "to",
    six(back(fieller(0.5)[2])), "\n")
cat("* Dose for centile", centile, "=", six(back(dose_for(centile / 100))), "\n")
cat("Confidence interval (No Heterogeneity) =", six(back(fieller(centile / 100)[1])), "to",
    six(back(fieller(centile / 100)[2])), "\n")

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
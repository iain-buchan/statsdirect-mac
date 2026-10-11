# StatsDirect recipe: Poisson regression of counts with an exposure, as the help shows it in R.
# From the help's R code (regression_and_correlation/poisson.htm); the data and settings above come from the run.
# data: response = response, exposure = exposure, predictors... = predictors, weight = weight
# settings: confidence = gamma, intercept = intercept

# Poisson regression: the StatsDirect help example (Armitage, Berry and Matthews
# 2001, response in veterans and non-veterans by age group, with the subject-exposure
# of exposure) in R

# R's standard model: a Poisson regression of the counts with the log of the
# exposure as an offset; the age group factor gives the same dummy variables as
# the report, with the youngest group as the baseline
pct <- paste0(100 * confidence, "%")
model <- if (intercept) response ~ . else response ~ . + 0   # the formula as a variable, so that the echo of the call has no stray figure
fit <- glm(model, offset = if (is.null(exposure)) NULL else log(exposure), data = as.data.frame(predictors, optional = TRUE), family = poisson, weights = weight)
print(summary(fit))

# The report's lines to 6 places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
dev <- fit$deviance
lr <- fit$null.deviance - dev
cat("Deviance goodness of fit chi-square =", six(dev), " df =", fit$df.residual, " ",
    pv(pchisq(dev, fit$df.residual, lower.tail = FALSE)), "\n")
df_lr <- fit$df.null - fit$df.residual
cat("Deviance (likelihood ratio) chi-square =", six(lr), " df =", df_lr, " ",
    pv(pchisq(lr, df_lr, lower.tail = FALSE)), "\n")
s <- summary(fit)$coefficients
lab <- if (intercept) c("Intercept", names(predictors)) else names(predictors)
slopes <- if (intercept) seq_len(nrow(s))[-1] else seq_len(nrow(s))
for (i in seq_len(nrow(s))) {
  cat(lab[i], " b", i - 1, " = ", six(s[i, 1]), "  z = ", six(s[i, 3]), "  ",
      pv(s[i, 4]), "\n", sep = "")
}

signed <- paste0(ifelse(s[slopes, 1] >= 0, "+", ""), six(s[slopes, 1]), " ", lab[slopes])
cat("log(response)", if (is.null(exposure)) "" else "[offset log(exposure)]", "=", if (intercept) six(s[1, 1]) else "", paste(signed, collapse = " "), "\n")

# Incidence rate ratios: exp of the coefficients, with Wald limits (the intercept's
# row is the baseline rate per subject-year)
ci <- confint.default(fit, level = confidence)
for (i in seq_len(nrow(s))) {
  cat(lab[i], six(s[i, 1]), six(exp(s[i, 1])), six(exp(ci[i, 1])), "to",
      six(exp(ci[i, 2])), "\n")
}

# The report also gives the ratios in each veteran status: among the veterans
# each age group's rate relative to the youngest non-veterans is exp of the age
# coefficient plus the veteran coefficient, with the standard error of that sum
# from the covariance matrix; among the non-veterans they are the ratios above
vc <- vcov(fit)
first <- slopes[1]   # the first predictor, the veterans in the help
for (i in slopes[-1]) {
  est <- s[i, 1] + s[first, 1]
  se_sum <- sqrt(vc[i, i] + vc[first, first] + 2 * vc[i, first])
  half <- qnorm((1 + confidence) / 2) * se_sum
  cat(paste0(lab[first], " = 1:"), lab[i], six(s[i, 1]), six(exp(est)), six(exp(est - half)), "to",
      six(exp(est + half)), "\n")
}

# The model analysis: the log likelihood (as R's logLik gives it), the information
# criteria on the deviance scale, the two pseudo R-squares (1 minus the ratio of
# the deviances; 1 minus the ratio of the log likelihoods, McFadden's, with the
# offset alone as the null model), Pearson's chi-square and the over-dispersion
# scale, which is Pearson's chi-square over its degrees of freedom
ll <- as.numeric(logLik(fit))
ll0 <- as.numeric(logLik(glm(response ~ 1, offset = if (is.null(exposure)) NULL else log(exposure), family = poisson, weights = weight)))
k <- length(coef(fit))
n <- length(response)
cat("Log likelihood with all covariates =", six(ll), "\n")
cat("Deviance with all covariates =", six(dev), " df =", fit$df.residual,
    " rank =", k, "\n")
cat("Akaike information criterion =", six(dev + 2 * k), "\n")
cat("Schwarz information criterion =", six(dev + k * log(n)), "\n")
cat("Deviance with no covariates =", six(fit$null.deviance), "\n")
cat("Pseudo (deviance based) R-square =", six(1 - dev / fit$null.deviance), "\n")
cat("Pseudo (McFadden, likelihood ratio index) R-square =", six(1 - ll / ll0), "\n")
pearson <- sum(residuals(fit, type = "pearson")^2)
cat("Pearson goodness of fit =", six(pearson), " df =", fit$df.residual, " ",
    pv(pchisq(pearson, fit$df.residual, lower.tail = FALSE)), "\n")
scale <- pearson / fit$df.residual
cat("Over-dispersion scale parameter =", six(scale), "\n")
cat("Scaled G2 =", six(lr / scale), " df =", df_lr, " ",
    pv(pchisq(lr / scale, df_lr, lower.tail = FALSE)), "\n")
cat("Scaled Pearson goodness of fit =", six(pearson / scale), " df =", fit$df.residual,
    " ", pv(pchisq(pearson / scale, fit$df.residual, lower.tail = FALSE)), "\n")
cat("Scaled Deviance goodness of fit =", six(dev / scale), " df =", fit$df.residual,
    " ", pv(pchisq(dev / scale, fit$df.residual, lower.tail = FALSE)), "\n")
cat("Coefficients, standard errors, then the scaled standard errors and Wald z:\n")
for (i in seq_len(nrow(s))) {
  cat(lab[i], six(s[i, 1]), six(s[i, 2]), six(s[i, 2] * sqrt(scale)),
      six(s[i, 1] / (s[i, 2] * sqrt(scale))),
      pv(2 * pnorm(-abs(s[i, 1] / (s[i, 2] * sqrt(scale))))), "\n")
}
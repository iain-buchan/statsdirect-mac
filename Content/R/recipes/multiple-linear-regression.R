# StatsDirect recipe: Multiple linear regression, as the help shows it in R.
# From the help's R code (regression_and_correlation/multiple_linear.htm); the data and settings above come from the run.
# data: outcome = outcome, predictors... = predictors, weights = weights
# settings: confidence = ci, intercept = calculateIntercept

# Multiple linear regression: the StatsDirect help example (Armitage and Berry 1994,
# recovery time after a hypotensive drug, 53 patients) in R

# R's standard regression: coefficients, t tests, the F test, R squared and the
# adjusted R squared (Ra squared); its residual standard error is the root MSE
fit <- eval(bquote(lm(.(reformulate(sprintf("`%s`", names(predictors)), "outcome", intercept = intercept)), data = as.data.frame(predictors, optional = TRUE), weights = weights)))
print(summary(fit))
print(anova(fit))

# The report's lines to 6 places. The partial correlation r of each predictor is
# its t over root(t squared + residual degrees of freedom); the Durbin-Watson
# statistic is the sum of squared successive residual differences over the
# residual sum of squares
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
s <- summary(fit)$coefficients
df <- fit$df.residual
for (i in seq_len(nrow(s))) {
  cat(rownames(s)[i], " b", if (intercept) i - 1 else i, " = ", six(s[i, 1]),
      if (!intercept || i > 1) paste("  r =", six(s[i, 3] / sqrt(s[i, 3]^2 + df))) else "",
      "  t = ", six(s[i, 3]), "  ", pv(s[i, 4]), "\n", sep = "")
}
a <- anova(fit)
k <- length(predictors)
ssreg <- sum(a$"Sum Sq"[1:k])
ssres <- a$"Sum Sq"[k + 1]
cat("Regression", six(ssreg), k, six(ssreg / k), "\n")
cat("Residual", six(ssres), df, six(ssres / df), "\n")
cat(if (intercept) "Total (corrected)" else "Total (uncorrected)", six(ssreg + ssres), df + k, "\n")
if (intercept) cat("outcome =", six(s[1, 1]), paste("+", six(s[-1, 1]), rownames(s)[-1], collapse = " "), "\n") else cat("outcome =", paste("+", six(s[, 1]), rownames(s), collapse = " "), "\n")
cat("Root MSE =", six(sqrt(ssres / df)), "\n")
f <- summary(fit)$fstatistic
cat("F =", six(f[1]), " ", pv(pf(f[1], f[2], f[3], lower.tail = FALSE)), "\n")
cat("Multiple correlation coefficient (R) =", six(sqrt(summary(fit)$r.squared)), "\n")
cat("R2 =", paste0(six(100 * summary(fit)$r.squared), "%"), "\n")
cat("Ra2 =", paste0(six(100 * summary(fit)$adj.r.squared), "%"), "\n")
e <- residuals(fit)
cat("Durbin-Watson test statistic =", six(sum(diff(e)^2) / sum(e^2)), "\n")

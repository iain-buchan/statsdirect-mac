# StatsDirect recipe: Multiple linear regression, as the help shows it in R.
# From the help's R code (regression_and_correlation/multiple_linear.htm); the data and settings above come from the run.
# data: outcome = outcome, predictors... = predictors, weights = weights
# settings: confidence = ci, intercept = calculateIntercept

# Multiple linear regression: the StatsDirect help example (Armitage and Berry 1994,
# recovery time after a hypotensive drug, 53 patients) in R

# R's standard regression: coefficients, t tests, the F test, R squared and the
# adjusted R squared (Ra squared); its residual standard error is the root MSE
# Zero prior weights are excluded from the fitted sample and residual sequence.
keep <- complete.cases(outcome, predictors, weights)
if (!is.null(weights) && any(weights < 0, na.rm = TRUE)) stop("Weights must not be negative.")
if (!is.null(weights)) keep <- keep & weights > 0
outcome <- outcome[keep]
predictors <- lapply(predictors, function(v) v[keep])
if (!is.null(weights)) weights <- weights[keep]
sd_data <- as.data.frame(predictors, optional = TRUE)
sd_own <- tail(make.unique(c(names(sd_data), "outcome", "weights")), 2)
sd_data[sd_own] <- list(outcome, if (is.null(weights)) rep(1, length(outcome)) else weights)
sd_terms <- encodeString(names(predictors), quote = "`")
sd_terms[names(predictors) == "."] <- "I(`.`)"
model <- reformulate(sd_terms, response = as.name(sd_own[1]), intercept = intercept)
fit <- eval(bquote(lm(.(model), data = sd_data, weights = .(as.name(sd_own[2])))))
fit_summary <- summary(fit)
a <- anova(fit)
print(fit_summary)
print(a)

# The report's lines to 6 places. The partial correlation r of each predictor is
# its t over root(t squared + residual degrees of freedom); the Durbin-Watson
# statistic is the sum of squared successive residual differences over the
# residual sum of squares. With no residual degrees of freedom (as many rows as
# parameters) R gives NaN for each test, which the report shows as *
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
s <- fit_summary$coefficients
df <- tail(a$Df, 1)
slopes_all <- if (intercept) coef(fit)[-1] else coef(fit)
dropped <- names(predictors)[is.na(slopes_all)]
if (length(dropped)) cat(paste(dropped, collapse = ", "),
    "dropped from the model due to very high correlation with other variable(s) included.\n")
for (i in seq_len(nrow(s))) {
  cat(rownames(s)[i], " b", if (intercept) i - 1 else i, " = ", six(s[i, 1]),
      if (!intercept || i > 1) paste("  r =", six(s[i, 3] / sqrt(s[i, 3]^2 + df))) else "",
      "  t = ", six(s[i, 3]), "  ", pv(s[i, 4]), "\n", sep = "")
}
# ANOVA omits aliased predictors and ends with the residual row.
regression <- head(a, -1)
k <- sum(regression$Df)
ssreg <- sum(regression$"Sum Sq")
ssres <- tail(a$"Sum Sq", 1)
cat("Regression", six(ssreg), k, if (k > 0) six(ssreg / k) else "unavailable", "\n")
cat("Residual", six(ssres), df, six(ssres / df), "\n")
cat(if (intercept) "Total (corrected)" else "Total (uncorrected)", six(ssreg + ssres), df + k, "\n")
if (intercept) {
  slopes <- if (nrow(s) > 1) paste("+", six(s[-1, 1]), rownames(s)[-1], collapse = " ") else ""
  cat("outcome =", six(s[1, 1]), slopes, "\n")
} else {
  slopes <- if (nrow(s) > 0) paste("+", six(s[, 1]), rownames(s), collapse = " ") else "0"
  cat("outcome =", slopes, "\n")
}
cat("Root MSE =", six(sqrt(ssres / df)), "\n")
f <- fit_summary$fstatistic
if (!is.null(f)) cat("F =", six(f[1]), " ", pv(pf(f[1], f[2], f[3], lower.tail = FALSE)), "\n")
cat("Multiple correlation coefficient (R) =", six(sqrt(fit_summary$r.squared)), "\n")
cat("R2 =", paste0(six(100 * fit_summary$r.squared), "%"), "\n")
cat("Ra2 =", paste0(six(100 * fit_summary$adj.r.squared), "%"), "\n")
e <- residuals(fit)
cat("Durbin-Watson test statistic =", six(sum(diff(e)^2) / sum(e^2)), "\n")

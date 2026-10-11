# StatsDirect recipe: Polynomial regression, as the help shows it in R.
# From the help's R code (regression_and_correlation/polynomial.htm); the data and settings above come from the run.
# data: kwh, size
# settings: degree = degree

degree <- as.numeric(degree)
# Polynomial regression: the StatsDirect help example (McClave and Dietrich 1991,
# electricity consumption and home size, degree 2) in R

# R's standard regression on the size and its square (poly with raw = TRUE keeps
# the ordinary powers, so the coefficients are the report's b0, b1 and b2)
fit <- eval(bquote(lm(kwh ~ poly(size, .(degree), raw = TRUE))))
print(summary(fit))

# The report's lines to 6 places, as for multiple linear regression
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
s <- summary(fit)$coefficients
df <- fit$df.residual
lab <- c("Intercept", "x", paste0("x^", seq_len(degree)[-1]))
for (i in seq_len(nrow(s))) {
  cat(lab[i], " b", i - 1, "= ", six(s[i, 1]),
      if (i > 1) paste("  r =", six(s[i, 3] / sqrt(s[i, 3]^2 + df))) else "",
      "  t = ", six(s[i, 3]), "  ", pv(s[i, 4]), "\n", sep = "")
}
cat("y =", six(s[1, 1]), paste(paste0(ifelse(s[-1, 1] >= 0, "+", ""), six(s[-1, 1]), " ", lab[-1]), collapse = " "), "\n")
a <- anova(fit)
ssreg <- a$"Sum Sq"[1]
ssres <- a$"Sum Sq"[2]
cat("Regression", six(ssreg), degree, six(ssreg / degree), "\n")
cat("Residual", six(ssres), df, six(ssres / df), "\n")
cat("Total (corrected)", six(ssreg + ssres), df + degree, "\n")
cat("Root MSE =", six(sqrt(ssres / df)), "\n")
f <- summary(fit)$fstatistic
cat("F =", six(f[1]), " ", pv(pf(f[1], f[2], f[3], lower.tail = FALSE)), "\n")
cat("Multiple correlation coefficient (R) =", six(sqrt(summary(fit)$r.squared)), "\n")
cat("R2 =", paste0(six(100 * summary(fit)$r.squared), "%"), "\n")
cat("Ra2 =", paste0(six(100 * summary(fit)$adj.r.squared), "%"), "\n")
e <- residuals(fit)
cat("Durbin-Watson test statistic =", six(sum(diff(e)^2) / sum(e^2)), "\n")

# Area under the fitted curve between the smallest and largest home size, by
# integrating the polynomial, and the area under the data by the trapezoidal rule
b <- coef(fit)
curve_area <- integrate(function(x) sapply(x, function(v) sum(b * v^(0:degree))), min(size), max(size))
cat("AUC (polynomial function) =", six(curve_area$value), "\n")
trapezia <- sum(diff(size) * (head(kwh, -1) + tail(kwh, -1)) / 2)
cat("AUC (by trapezoidal rule) =", six(trapezia), "\n")
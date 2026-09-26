# Conventional small-sample coefficient inference assumes a linear conditional mean,
# independent constant-variance normal errors; predictor normality is not required.
# Coefficient intervals are not prediction intervals. Association alone is not causation.
# na.omit excludes incomplete rows and can introduce selection bias.
y <- sd_numeric(sd_columns("y")[[1]])
x <- sd_numeric(sd_columns("x")[[1]])
data <- as.data.frame(sd_matrix(list(y = y, x = x)))
model <- lm(y ~ x, data = data, na.action = na.omit)
result <- summary(model)
print(result)
print(confint(model, level = confidence))
# model is available for predict(), residuals() and further diagnostics.

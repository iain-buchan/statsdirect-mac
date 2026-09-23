y <- sd_numeric(sd_columns("y")[[1]])
x <- sd_numeric(sd_columns("x")[[1]])
data <- as.data.frame(sd_matrix(list(y = y, x = x)))
model <- lm(y ~ x, data = data, na.action = na.omit)
result <- summary(model)
print(result)
print(confint(model, level = confidence))
# model is available for predict(), residuals() and further diagnostics.

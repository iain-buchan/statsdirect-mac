columns <- lapply(sd_columns(), function(x) na.omit(sd_numeric(x)))
result <- lapply(columns, shapiro.test)
print(result)
# Shapiro-Wilk is reproduced here; the report's other normality diagnostics are not.

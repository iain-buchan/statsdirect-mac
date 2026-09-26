# A non-significant normality test does not prove normality; inspect plots and design.
# Do not select an analysis solely by a normality P value.
# Base R Shapiro-Wilk requires 3 to 5000 non-missing observations.
columns <- lapply(sd_columns(), function(x) na.omit(sd_numeric(x)))
result <- lapply(columns, shapiro.test)
print(result)
# Shapiro-Wilk is reproduced here; the report's other normality diagnostics are not.

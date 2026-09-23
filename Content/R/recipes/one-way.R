columns <- lapply(sd_columns(), function(x) na.omit(sd_numeric(x)))
data <- data.frame(value = unlist(columns, use.names = FALSE),
                   group = factor(rep(seq_along(columns), lengths(columns)), labels = names(columns)))
model <- aov(value ~ group, data = data)
result <- summary(model)
print(result)
# Extend with diagnostics or explicitly chosen post-hoc comparisons, e.g. TukeyHSD(model).

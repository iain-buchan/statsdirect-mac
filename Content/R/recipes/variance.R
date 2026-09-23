columns <- lapply(sd_columns(), function(x) na.omit(sd_numeric(x)))
# StatsDirect places the larger variance in the numerator.
if (var(columns[[1]]) < var(columns[[2]])) columns <- rev(columns)
result <- var.test(columns[[1]], columns[[2]], conf.level = confidence)
print(result)

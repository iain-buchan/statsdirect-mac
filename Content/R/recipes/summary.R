columns <- lapply(sd_columns(), function(x) na.omit(sd_numeric(x)))
result <- lapply(columns, function(x) {
  n <- length(x)
  se <- sd(x) / sqrt(n)
  list(n = n, mean = mean(x), sd = sd(x), se = se, median = median(x), min = min(x), max = max(x),
       mean_ci = mean(x) + c(-1, 1) * qt((1 + confidence) / 2, n - 1) * se,
       quantiles = quantile(x, probs = c(0.25, 0.5, 0.75), type = 7))
})
print(result)
# R type-7 quantiles are explicit; StatsDirect's centile/CI conventions and extra summaries can differ.

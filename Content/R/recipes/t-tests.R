# Assume independent observations; exact small-sample t inference models normal groups.
# Pooled inference additionally assumes equal population variances; Welch relaxes that
# equality and uses an approximate reference distribution. Inspect outliers and design.
columns <- lapply(sd_columns(), function(x) na.omit(sd_numeric(x)))
x <- columns[[1]]
if (operation == "TSingle") {
  result <- t.test(x, mu = sd_parameter("population-mean", 0), conf.level = confidence)
  print(result)
} else {
  y <- columns[[2]]
  # StatsDirect reports both equal-variance and Welch estimates.
  result <- t.test(x, y, var.equal = TRUE, conf.level = confidence)
  welch <- t.test(x, y, var.equal = FALSE, conf.level = confidence)
  print(result)
  print(welch)
}

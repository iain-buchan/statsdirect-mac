if (operation == "TSingleSummary") {
  n <- parameters$nx
  difference <- parameters$mu - parameters$mu0
  se <- parameters$sd1 / sqrt(n)
  df <- n - 1
} else {
  n1 <- parameters$nx1; n2 <- parameters$nx2
  difference <- parameters$um1 - parameters$um2
  pooled_variance <- ((n1 - 1) * parameters$sd1^2 + (n2 - 1) * parameters$sd2^2) / (n1 + n2 - 2)
  se <- sqrt(pooled_variance * (1 / n1 + 1 / n2))
  df <- n1 + n2 - 2
  v1 <- parameters$sd1^2 / n1; v2 <- parameters$sd2^2 / n2
  welch_df <- (v1 + v2)^2 / (v1^2 / (n1 - 1) + v2^2 / (n2 - 1))
  welch_t <- difference / sqrt(v1 + v2)
  welch <- list(statistic = welch_t, parameter = welch_df, p.value = 2 * pt(-abs(welch_t), welch_df),
                conf.int = difference + c(-1, 1) * qt((1 + confidence) / 2, welch_df) * sqrt(v1 + v2))
  print(welch)
}
t <- difference / se
result <- list(estimate = difference, statistic = t, parameter = df, p.value = 2 * pt(-abs(t), df),
               conf.int = difference + c(-1, 1) * qt((1 + confidence) / 2, df) * se)
print(result)

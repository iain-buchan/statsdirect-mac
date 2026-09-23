# The distribution form retains its fields as a named list.
p <- parameters[[1]]
x <- p$x; df <- p$df; df2 <- p$df2
cdf <- switch(operation,
  DistributionNormal = pnorm(x), DistributionT = pt(x, df),
  DistributionF = pf(x, df, df2), DistributionChiSquare = pchisq(x, df),
  DistributionQ = ptukey(x, nmeans = df2, df = df),
  DistributionNonCentralT = pt(x, df, ncp = df2),
  DistributionBinomial = pbinom(df2, size = df, prob = x),
  DistributionPoisson = ppois(df, lambda = df2))
upper <- 1 - cdf
# Discrete tails include the observed count on both sides.
if (operation == "DistributionBinomial") upper <- pbinom(df2 - 1, df, x, lower.tail = FALSE)
if (operation == "DistributionPoisson") upper <- ppois(df - 1, df2, lower.tail = FALSE)
result <- c(lower = cdf, upper = upper)
if (operation %in% c("DistributionNormal", "DistributionT")) result <- c(result, two_sided = 2 * min(cdf, upper))
print(result)

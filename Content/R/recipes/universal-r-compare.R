# StatsDirect recipe: Comparison of two universal R agreement coefficients, as the help shows it in R.
# From the help's R code (agreement/universal_agreement.htm); the data and settings above come from the run.
# settings: r1 = r1_in, r2 = r2_in, mu1 = mu1_in, mu2 = mu2_in, var1 = var1_in, var2 = var2_in, skew1 = gam1_in, skew2 = gam2_in, confidence = gamma

six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
p_type3 <- function(t, skew) {
  if (abs(skew) < 1e-7) return(pnorm(t))
  r <- 2 / abs(skew)
  if (skew > 0) pgamma(t + r, shape = r^2, rate = r) else
    pgamma(r - t, shape = r^2, rate = r, lower.tail = FALSE)
}
# Comparison example: R for two independent groups of observers, with the mean,
# variance and skewness of delta that each group's report gives. The difference is
# tested on the delta scale (Berry and Mielke 1997a): its variance and skewness come
# from the two groups' moments, and the P value for the difference is two sided, twice
# the lesser of its two tails. The P value under each group is that of its own R: the
# delta that the group observed is its mean delta times 1 - R
vard <- (mu1^2 * var2 + mu2^2 * var1) / (mu1^2 * mu2^2)
skewd <- (mu1^3 * var2^1.5 * skew2 - mu2^3 * var1^1.5 * skew1) /
  (mu1^3 * mu2^3 * vard^1.5)
cat("R:", six(r1), six(r2), six(r1 - r2), "\n")
cat("Delta:", six(mu1), six(mu2), six(mu1 - mu2), "\n")
cat("Variance:", six(var1), six(var2), six(vard), "\n")
cat("Skewness:", six(skew1), six(skew2), six(skewd), "\n")
lower <- p_type3((r1 - r2) / sqrt(vard), skewd)
upper <- p_type3((r2 - r1) / sqrt(vard), -skewd)
cat("Significance:", pv(p_type3((mu1 * (1 - r1) - mu1) / sqrt(var1), skew1)),
    pv(p_type3((mu2 * (1 - r2) - mu2) / sqrt(var2), skew2)),
    pv(min(1, 2 * min(lower, upper))), "\n")
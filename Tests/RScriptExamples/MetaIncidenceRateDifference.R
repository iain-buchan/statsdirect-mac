# Incidence rate meta-analysis: the StatsDirect help example (Rothman and Monson 1973,
# deaths among patients with trigeminal neuralgia in two age strata, exposed and not
# exposed; the test workbook's meta worksheet columns Exposed cases, Exposed
# person-time, Control cases, Control person-time and Age split) in R
a <- c(14, 76)        # cases in the exposed groups
pt1 <- c(1516, 949)   # person-years in the exposed groups
b <- c(10, 121)       # cases in the non-exposed groups
pt2 <- c(1701, 2245)  # person-years in the non-exposed groups
strata <- c("Age < 65", "Age >= 65")
k <- length(a)
z <- qnorm(0.975)     # for 95% confidence intervals
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}

# Base R has no meta-analysis function, so the pooling follows the formulae above: a
# fixed effects estimate weighted by inverse variance, Cochran's Q for heterogeneity,
# the DerSimonian-Laird moment estimate of the between-studies variance (tau squared,
# zero when Q is below its degrees of freedom) and the random effects estimate, whose
# weights add tau squared to each stratum's variance (two or more strata)
pool <- function(y, v) {
  w <- 1 / v
  fixed <- sum(w * y) / sum(w)
  q <- sum(w * (y - fixed)^2)
  tau2 <- max(0, (q - (k - 1)) / (sum(w) - sum(w^2) / sum(w)))
  wr <- 1 / (v + tau2)
  list(fixed = fixed, se = sqrt(1 / sum(w)), q = q, tau2 = tau2,
       random = sum(wr * y) / sum(wr), se_r = sqrt(1 / sum(wr)),
       fixed_pct = 100 * w / sum(w), random_pct = 100 * wr / sum(wr))
}
# The pooled part of the report; f back-transforms a log ratio to a ratio
summarise <- function(p, name, null, f = identity) {
  ci <- function(est, se) {
    paste0("(95% CI = ", six(f(est - z * se)), " to ", six(f(est + z * se)), ")")
  }
  cat("Fixed effects (inverse variance)\n")
  cat("Pooled", name, "=", six(f(p$fixed)), ci(p$fixed, p$se), "\n")
  cat("Z (test ", name, " differs from ", null, ") = ", six(p$fixed / p$se), "  ",
      pv(2 * pnorm(-abs(p$fixed / p$se))), "\n", sep = "")
  cat("Non-combinability of studies\n")
  cat("Cochran Q = ", six(p$q), "  (df = ", k - 1, ")  ",
      pv(pchisq(p$q, k - 1, lower.tail = FALSE)), "\n", sep = "")
  cat("Moment-based estimate of between studies variance =", six(p$tau2), "\n")
  # I2 is the share of Q beyond its degrees of freedom; StatsDirect adds a confidence
  # interval for it when there are at least three strata
  i2 <- max(0, 100 * (p$q - (k - 1)) / p$q)
  cat("I2 (inconsistency) = ",
      formatC(i2, digits = 1, format = "f", drop0trailing = TRUE), "%\n", sep = "")
  cat("Random effects (DerSimonian-Laird)\n")
  cat("Pooled", name, "=", six(f(p$random)), ci(p$random, p$se_r), "\n")
  cat("Z (test ", name, " differs from ", null, ") = ", six(p$random / p$se_r), "  ",
      pv(2 * pnorm(-abs(p$random / p$se_r))), "\n", sep = "")
}
# The forest plots that follow in the report: each stratum's estimate and interval, a
# box that grows with its weight, and the pooled estimate as a diamond at the foot
forest <- function(est, lower, upper, pooled, p_lower, p_upper, pct, main, xlab,
                   null, log = "") {
  par(mar = c(5, 7, 4, 2))
  y <- (k + 1):2
  plot(NA, xlim = range(lower, upper, p_lower, p_upper), ylim = c(0.5, k + 1.5),
       log = log, yaxt = "n", ylab = "", xlab = xlab, main = main)
  axis(2, at = c(y, 1), labels = c(strata, "combined"), las = 1, tick = FALSE)
  abline(v = null, lty = 3)
  segments(lower, y, upper, y)
  points(est, y, pch = 15, cex = 0.5 + 2 * sqrt(pct / 100))
  polygon(c(p_lower, pooled, p_upper, pooled), c(1, 1.2, 1, 0.8), col = "grey")
}

# Each stratum's incidence rate difference, with its approximate interval: the
# difference plus and minus z standard errors, from the Poisson variance of the
# difference, a/pt1^2 + b/pt2^2, which the fixed effects weights invert
ird <- a / pt1 - b / pt2
v_ird <- a / pt1^2 + b / pt2^2
se_ird <- sqrt(v_ird)
res <- pool(ird, v_ird)
cat("Incidence rate difference (IRD) meta-analysis\n")
print(data.frame(stratum = 1:k, IRD = six(ird), lower = six(ird - z * se_ird),
                 upper = six(ird + z * se_ird), strata), row.names = FALSE)
# The report's next table: the standardised effect is the difference itself, with its
# variance beside the weights
print(data.frame(stratum = 1:k, effect = six(ird), variance = six(v_ird),
                 fixed = six(res$fixed_pct), random = six(res$random_pct), strata),
      row.names = FALSE)
summarise(res, "IRD", 0)
forest(ird, ird - z * se_ird, ird + z * se_ird, res$fixed, res$fixed - z * res$se,
       res$fixed + z * res$se, res$fixed_pct,
       "Incidence rate difference meta-analysis plot [fixed effects]",
       "incidence rate difference (95% confidence interval)", 0)
forest(ird, ird - z * se_ird, ird + z * se_ird, res$random, res$random - z * res$se_r,
       res$random + z * res$se_r, res$random_pct,
       "Incidence rate difference meta-analysis plot [random effects]",
       "incidence rate difference (95% confidence interval)", 0)

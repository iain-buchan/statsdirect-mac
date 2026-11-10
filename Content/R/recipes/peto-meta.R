# StatsDirect recipe: Peto odds ratio meta-analysis, as the help shows it in R.
# From the help's R code (meta_analysis/peto.htm); the data and settings above come from the run.
# data: aspirin, aspirin_deaths, control, control_deaths, study
# settings: confidence = gamma, exact_meta = metaExact

# Keep only studies with all inputs needed for this analysis.
keep <- complete.cases(aspirin, aspirin_deaths, control, control_deaths)
if (any(!keep)) cat("(", sum(!keep), " other rows not used)\n", sep = "")
aspirin <- aspirin[keep]
aspirin_deaths <- aspirin_deaths[keep]
control <- control[keep]
control_deaths <- control_deaths[keep]
study <- study[keep]
if (is.null(study)) study <- paste("Trial", seq_along(aspirin))
# Peto odds ratio meta-analysis: the StatsDirect help example (Fleiss 1993, deaths after
# heart attack in seven trials of aspirin; the test workbook's Meta-analysis worksheet
# columns Exposed total, Exposed cases, Non-exposed total, Non-exposed cases and Study)
# in R

# Base R has no meta-analysis function, so each study's fourfold table is worked as the
# formulae above give it: a and b are the deaths on aspirin and on control, cc and dd
# the survivors (not c and d, which would hide two of R's own functions), and n is the
# size of the study
pct <- paste0(100 * confidence, "%")
a <- aspirin_deaths
b <- control_deaths
cc <- aspirin - aspirin_deaths
dd <- control - control_deaths
n <- a + b + cc + dd
print(data.frame(study, a, b, cc, dd))
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}

# O - E is the number of deaths on aspirin less the number expected if aspirin had no
# effect; V is the hypergeometric variance of that number, and it is also the weight of
# the study. The Peto odds ratio is exp((O - E) / V), with its interval from the normal
# distribution. A study without a variance (no deaths, or deaths of every subject, a
# group of nobody, or one subject) has no odds ratio: it is listed as excluded, and k
# is the number of studies pooled
E <- (a + b) * (a + cc) / n
oe <- ifelse(n > 0, a - E, 0)
V <- ifelse(n > 1, (a + b) * (cc + dd) * (a + cc) * (b + dd) / (n^2 * (n - 1)), 0)
included <- V > 0
k <- sum(included)
note <- ifelse(included, "", "* (excluded)")
z <- qnorm((1 + confidence) / 2)
or <- ifelse(included, exp(oe / V), NA)
lower <- ifelse(included, exp((oe - z * sqrt(V)) / V), NA)
upper <- ifelse(included, exp((oe + z * sqrt(V)) / V), NA)
cat("Stratum, O-E, odds ratio,", pct, "CI:\n")
for (i in seq_along(a)) {
  cat(i, six(oe[i]), six(or[i]), six(lower[i]), six(upper[i]), study[i], note[i], "\n")
}

# The standardised effect is the log odds ratio, (O - E) / V, whose variance is 1 / V;
# the weights are the V as percentages of their total
cat("Stratum, standardised effect, variance, % weight:\n")
for (i in seq_along(a)) {
  cat(i, six(log(or[i])), six(if (included[i]) 1 / V[i] else NA), six(100 * V[i] / sum(V)),
      study[i], note[i], "\n")
}

# Each study's test of no effect: z = (O - E) / sqrt(V) against the normal distribution
zi <- ifelse(included, oe / sqrt(V), NA)
cat("Stratum, V, z, P (two sided):\n")
for (i in seq_along(a)) {
  cat(i, six(V[i]), six(zi[i]), pv(2 * pnorm(-abs(zi[i]))), study[i], note[i], "\n")
}

# The pooled odds ratio (fixed effects): the sums of O - E and of V take the place of
# the single study's in the same formulae (an excluded study adds nothing to either)
sum_oe <- sum(oe)
sum_V <- sum(V)
pooled <- exp(sum_oe / sum_V)
pooled_lower <- exp((sum_oe - z * sqrt(sum_V)) / sum_V)
pooled_upper <- exp((sum_oe + z * sqrt(sum_V)) / sum_V)
z_pooled <- sum_oe / sqrt(sum_V)
cat("Pooled odds ratio = ", six(pooled), " (", pct, "CI = ", six(pooled_lower), " to ",
    six(pooled_upper), ")\n", sep = "")
cat("Z (test of odds ratio differs from 1) =", six(z_pooled), " ",
    pv(2 * pnorm(-abs(z_pooled))), "\n")

# Non-combinability: Cochran's Q is the weighted sum of squared differences between the
# studies' log odds ratios and the pooled one, with the V as weights, referred to the
# chi-square distribution with k - 1 degrees of freedom. I-squared is 100 (Q - df) / Q,
# not below zero. Its default interval uses the non-central chi-square method of Hedges and
# Pigott (2001) that the report uses: Q is treated as a non-central chi-square variable
# on df degrees of freedom, and each limit is the non-centrality parameter at which the
# observed Q reaches the selected upper (lower limit) or lower (upper limit) tail,
# found with uniroot and pchisq; a limit is 0 when the central distribution already
# puts Q below that percentile. A non-centrality lambda gives
# I-squared = lambda / (df + lambda)
Q <- if (k > 1) sum((V * (log(or) - log(pooled))^2)[included]) else 0
dfq <- k - 1
cat("Cochran Q = ", six(Q), "  (df = ", dfq, ")  ",
    pv(pchisq(Q, dfq, lower.tail = FALSE)), "\n", sep = "")
one <- function(x) formatC(x, digits = 1, format = "f", drop0trailing = TRUE)
# I-squared interval: recorded exact/test-based choice.
# Older records have no preference: retain the non-central interval they used.
if (is.null(exact_meta)) exact_meta <- TRUE
df_i2 <- k - 1
i2 <- if (k < 2) NA_real_ else if (Q == 0) 0 else max(0, 100 * (Q - df_i2) / Q)
i2_ci <- rep(NA_real_, 2)
if (k >= 2 && confidence > 0 && confidence < 1) {
  if (isTRUE(exact_meta)) {
    # Invert the non-central chi-square CDF (Hedges & Pigott, 2001).
    lambda <- function(p) {
      if (pchisq(Q, df_i2) <= p) 0 else
        uniroot(function(l) pchisq(Q, df_i2, ncp = l) - p,
                c(0, 10 * Q + 100), tol = 1e-10)$root
    }
    lim <- c(lambda((1 + confidence) / 2), lambda((1 - confidence) / 2))
    i2_ci <- 100 * lim / (df_i2 + lim)
  } else if (k >= 3 || Q > k) {
    # Test-based log(H) interval (Higgins & Thompson, 2002), as in
    # StatsDirect's MIT Meta.IsquareNcc. H is at least one; with two studies
    # only Q > k gives a standard error (the first form below).
    h2 <- max(1, Q / df_i2)
    se_log_h <- if (Q > k) 0.5 * (log(Q) - log(df_i2)) /
      (sqrt(2 * Q) - sqrt(2 * k - 3)) else
      sqrt((1 - 1 / (3 * (k - 2)^2)) / (2 * (k - 2)))
    h_limits <- exp(log(sqrt(h2)) + c(-1, 1) * z * se_log_h)
    h_limits[1] <- max(1, h_limits[1])
    i2_ci <- 100 * (1 - 1 / h_limits^2)
  }
}
if (k < 2) cat("I2 not calculated: at least two studies are required.\n") else if (anyNA(i2_ci))
  cat("I2 (inconsistency) =", one(i2), "% (interval unavailable for this number of studies and confidence level)\n") else
  cat("I2 (inconsistency) = ", one(i2), "% (", pct, "CI = ",
      one(i2_ci[1]), "% to ", one(i2_ci[2]), "%)\n", sep = "")
# End of I-squared interval.

# Bias indicators, which the report gives only when more than three studies are
# pooled. Each study's standard error of the log odds ratio is 1 / sqrt(V).
# Begg and Mazumdar's test is Kendall's tau between the standardised deviates of the
# studies from the pooled log odds ratio and their variances; the exact P holds when
# there are no ties among either, as here. The report notes the test's low power with
# fewer than eleven studies.
se <- ifelse(included, 1 / sqrt(V), NA)
# Egger's and Harbord's intervals are at the level of the bias tests, twice the
# analysis's alpha (90% for a 95% analysis); as the report has it, there is no
# figure when every study has the same precision or the line fits every study exactly
bias_level <- 1 - 2 * (1 - confidence)
if (!(bias_level > 0 && bias_level < 1)) bias_level <- 0.9
regression <- function(y, x, label, spread) {
  fit <- lm(y ~ x)
  if (spread && sum(residuals(fit)^2) > 1e-12 * sum(y^2)) {
    fit_ci <- confint(fit, level = bias_level)
    figures <- c(coef(fit)[1], fit_ci[1, 1], fit_ci[1, 2], summary(fit)$coefficients[1, 4])
  } else figures <- rep(NA, 4)
  cat(label, ": bias = ", six(figures[1]), " (", round(100 * bias_level, 2), "% CI = ",
      six(figures[2]), " to ", six(figures[3]), ")  ", pv(figures[4]), "\n", sep = "")
  invisible(unname(figures))
}
if (k > 3) {
  deviate <- (log(or) - log(pooled)) / sqrt(se^2 - 1 / sum_V)
  begg <- cor.test(deviate[included], se[included]^2, method = "kendall", exact = TRUE,
                   conf.level = confidence)
  cat("Begg-Mazumdar: Kendall's tau =", six(begg$estimate), " ", pv(begg$p.value),
      "(low power)\n")

  # Egger's test regresses each log odds ratio divided by its standard error on the
  # precision, 1 / standard error: the bias is the intercept, tested with Student's t on
  # k - 2 degrees of freedom
  precision <- 1 / se[included]
  egger_figures <- regression(log(or[included]) / se[included], precision, "Egger",
                      diff(range(precision)) > 1e-12 * max(precision))

  # Harbord's modification regresses the score O - E divided by sqrt(V) on sqrt(V). For
  # the Peto odds ratio that is the same regression as Egger's, since the log odds ratio
  # over its standard error is (O - E) / sqrt(V) and the precision is sqrt(V), so the two
  # tests agree
  root_v <- sqrt(V[included])
  harbord_figures <- regression(oe[included] / root_v, root_v, "Harbord-Egger",
                        sum((root_v - mean(root_v))^2) > 1e-12 * sum(root_v^2))
} else cat("Bias indicators need more than three studies with an estimate\n")

# The report's charts. First the bias assessment (funnel) plot: each log odds ratio
# against its standard error, the axis reversed so that the 95% cone about the pooled
# log odds ratio opens downwards
se_top <- max(se, na.rm = TRUE) * 1.05
plot(log(or), se, ylim = c(se_top, 0), xlab = "Log(Peto odds ratio)",
     ylab = "Standard error", main = "Bias assessment plot",
     xlim = range(log(or), log(pooled) + c(-1, 1) * z * se_top, na.rm = TRUE))
abline(v = log(pooled))
lines(log(pooled) + c(-1, 0, 1) * z * se_top, c(se_top, 0, se_top))

# The L'Abbe plot: the percentage of deaths on aspirin against that on control, each
# study drawn with a symbol whose size grows with its sample size, the line of
# equality, and the dashed curve on which a study with the pooled odds ratio lies
# whatever its control rate
plot(100 * b / (b + dd), 100 * a / (a + cc), xlim = c(0, 100), ylim = c(0, 100),
     cex = 3 * sqrt(n / max(n)), xlab = "control percent",
     ylab = "experimental percent",
     main = "L'Abbe plot (symbol size represents sample size)")
abline(0, 1)
pc <- 0:100
lines(pc, 100 * pooled * pc / (100 - pc + pooled * pc), lty = 2)

# The Peto odds ratio (forest) plot on a log scale: each study's odds ratio with its 95%
# interval and a square whose size grows with its weight, the line of no effect, and
# the pooled odds ratio and interval at the foot; an excluded study has a row without
# an estimate
rows <- length(a):1
par(mar = c(5, 6, 4, 8))
plot(c(lower, pooled_lower), c(rows, 0), type = "n", log = "x", yaxt = "n",
     xlim = range(lower, upper, pooled_lower, pooled_upper, na.rm = TRUE),
     ylim = c(-0.5, length(a) + 0.5), ylab = "",
     xlab = "Peto odds ratio (95% confidence interval)", main = "Peto odds ratio plot")
segments(lower, rows, upper, rows)
points(or, rows, pch = 15, cex = 3 * sqrt(V / max(V)))
segments(pooled_lower, 0, pooled_upper, 0)
points(pooled, 0, pch = 18, cex = 2)
abline(v = 1)
axis(2, at = c(rows, 0), labels = c(study, "combined"), las = 1)
label <- c(ifelse(included, sprintf("%.2f (%.2f, %.2f)", or, lower, upper), "excluded"),
           sprintf("%.2f (%.2f, %.2f)", pooled, pooled_lower, pooled_upper))
mtext(label, side = 4, at = c(rows, 0), las = 1, line = 1, cex = 0.8)
par(mar = c(5, 4, 4, 2) + 0.1)

# And the plot of O - E against V, both axes including the origin: the studies fall
# along the line through the origin with the slope of the pooled log odds ratio when
# all of them share one odds ratio
plot(V, oe, xlim = c(0, max(V)), ylim = range(0, oe, na.rm = TRUE), xlab = "Peto weights",
     ylab = "Observed-Expected", main = "Peto O-E vs. V plot")
abline(0, log(pooled))

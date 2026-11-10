# StatsDirect recipe: Proportion meta-analysis, as the help shows it in R.
# From the help's R code (meta_analysis/proportion.htm); the data and settings above come from the run.
# data: total, adherent, trial
# settings: confidence = gamma, method = method, exact_meta = metaExact

# Keep only studies with all inputs needed for this analysis.
keep <- complete.cases(total, adherent)
if (any(!keep)) cat("(", sum(!keep), " other rows not used)\n", sep = "")
total <- total[keep]
adherent <- adherent[keep]
trial <- trial[keep]
if (is.null(trial)) trial <- paste("Trial", seq_along(total))
# A study whose label is blank has its place among the studies kept, as in the report.
blank <- is.na(trial) | !nzchar(trimws(trial))
trial[blank] <- paste("stratum", which(blank))
# Proportion meta-analysis: the StatsDirect help example (adherence with medication in
# 22 fictitious trials; the test workbook's Meta-analysis worksheet columns Trial,
# Adherent and Total) in R

# Base R has no meta-analysis function, so the pooled proportions are computed as the
# formulae above give them: each proportion is transformed by the Freeman-Tukey double
# arcsine, pooled with inverse variance weights (n + 0.5), and the pooled transform is
# taken back to a proportion by the Stuart-Ord inverse, sin(x/2)^2
pct <- paste0(100 * confidence, "%")
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
k <- length(total)
if (k == 0) stop("At least one study must have a total and a number of outcomes")
z <- qnorm((1 + confidence) / 2)
p <- adherent / total

# Each study's proportion with its exact (Clopper-Pearson) 95% confidence interval, as
# binom.test() gives it; when every subject responds, as in the Zu trial, the interval
# is one sided and its lower limit is the 97.5% limit
ci <- t(sapply(seq_len(k), function(i) binom.test(adherent[i], total[i], conf.level = confidence)$conf.int))
one_sided <- ifelse(adherent == 0 | adherent == total,
                   paste0("[", 100 * (1 + confidence) / 2, "% one-sided CI]"), "")
cat("Method:", if (method == "doubleArcsine") "Miller (exact inverse Freeman-Tukey double arcsine)" else "Stuart-Ord (inverse double arcsine square root)", "\n")
print(data.frame(Study = seq_len(k), Proportion = six(p), Lower = six(ci[, 1]),
                 Upper = six(ci[, 2]), Trial = paste(trial, one_sided)),
      row.names = FALSE, right = FALSE)

# The transformed proportions, their variances and the fixed and random effects weights
x <- asin(sqrt(adherent / (total + 1))) + asin(sqrt((adherent + 1) / (total + 1)))
v <- 1 / (total + 0.5)
w <- 1 / v
xf <- sum(w * x) / sum(w)
se_f <- 1 / sqrt(sum(w))
q <- if (k > 1) sum(w * (x - xf)^2) else 0
spread <- sum(w) - sum(w^2) / sum(w)
tau2 <- if (k < 2 || spread == 0) 0 else max(0, (q - (k - 1)) / spread)
wr <- 1 / (tau2 + v)
xr <- sum(wr * x) / sum(wr)
se_r <- 1 / sqrt(sum(wr))
print(data.frame(Study = seq_len(k), Transform = six(x), Variance = six(v),
                 Fixed = six(100 * w / sum(w)), Random = six(100 * wr / sum(wr)),
                 Trial = paste(trial, one_sided)), row.names = FALSE, right = FALSE)

hmn <- length(total) / sum(1 / total)   # the harmonic mean of study sizes for the Miller inverse
inv <- function(t) {
  if (method != "doubleArcsine") return(sin(t / 2)^2)
  # The exact inverse folds back beyond its attainable range; return the boundary instead.
  if (t <= asin(sqrt(1 / (hmn + 1)))) return(0)
  if (t >= asin(sqrt(hmn / (hmn + 1))) + pi / 2) return(1)
  0.5 * (1 - sign(cos(t)) * sqrt(max(0, 1 - (sin(t) + (sin(t) - 1 / sin(t)) / hmn)^2)))
}
# As the report has it, the pooled proportion is 0, with a lower limit of 0, when no
# study has a responder, and 1, with an upper limit of 1, when every subject of every
# study responds; the inverse transform alone would leave them just inside
fixed <- c(inv(xf), inv(xf - z * se_f), inv(xf + z * se_f))
if (all(adherent == 0)) fixed[1:2] <- 0 else if (all(adherent == total)) fixed[c(1, 3)] <- 1
cat("Fixed effects (inverse variance)\n")
cat("Pooled proportion = ", six(fixed[1]), " (", pct, " CI = ", six(fixed[2]),
    " to ", six(fixed[3]), ")\n", sep = "")

cat("Non-combinability of studies\n")
cat("Cochran Q = ", six(q), "  (df = ", k - 1, ")  ",
    pv(if (k > 1) pchisq(q, k - 1, lower.tail = FALSE) else NA_real_), "\n", sep = "")
cat("Moment-based estimate of between studies variance =", six(tau2), "\n")
one <- function(x) formatC(x, digits = 1, format = "f")
# I-squared interval: recorded exact/test-based choice.
# Older records have no preference: retain the non-central interval they used.
if (is.null(exact_meta)) exact_meta <- TRUE
df_i2 <- k - 1
i2 <- if (k < 2) NA_real_ else if (q == 0) 0 else max(0, 100 * (q - df_i2) / q)
i2_ci <- rep(NA_real_, 2)
if (k >= 2 && confidence > 0 && confidence < 1) {
  if (isTRUE(exact_meta)) {
    # Invert the non-central chi-square CDF (Hedges & Pigott, 2001).
    lambda <- function(p) {
      if (pchisq(q, df_i2) <= p) 0 else
        uniroot(function(l) pchisq(q, df_i2, ncp = l) - p,
                c(0, 10 * q + 100), tol = 1e-10)$root
    }
    lim <- c(lambda((1 + confidence) / 2), lambda((1 - confidence) / 2))
    i2_ci <- 100 * lim / (df_i2 + lim)
  } else if (k >= 3 || q > k) {
    # Test-based log(H) interval (Higgins & Thompson, 2002), as in
    # StatsDirect's MIT Meta.IsquareNcc. H is at least one; with two studies
    # only Q > k gives a standard error (the first form below).
    h2 <- max(1, q / df_i2)
    se_log_h <- if (q > k) 0.5 * (log(q) - log(df_i2)) /
      (sqrt(2 * q) - sqrt(2 * k - 3)) else
      sqrt((1 - 1 / (3 * (k - 2)^2)) / (2 * (k - 2)))
    h_limits <- exp(log(sqrt(h2)) + c(-1, 1) * z * se_log_h)
    h_limits[1] <- max(1, h_limits[1])
    i2_ci <- 100 * (1 - 1 / h_limits^2)
  }
}
if (k < 2) cat("I2 not calculated: at least two studies are required.\n") else if (anyNA(i2_ci))
  cat("I2 (inconsistency) =", one(i2), "% (interval unavailable for this number of studies and confidence level)\n") else
  cat("I2 (inconsistency) = ", one(i2), "% (", pct, " CI = ",
      one(i2_ci[1]), "% to ", one(i2_ci[2]), "%)\n", sep = "")
# End of I-squared interval.

cat("Random effects (DerSimonian-Laird)\n")
cat("Pooled proportion = ", six(inv(xr)), " (", pct, " CI = ", six(inv(xr - z * se_r)),
    " to ", six(inv(xr + z * se_r)), ")\n", sep = "")

# Bias indicators, all on the proportion scale with each study's standard error taken
# from its exact confidence interval, which the report gives only with more than three
# studies. Begg-Mazumdar: Kendall's tau between the standardised deviates from the
# pooled proportion and the variances, with the exact P that cor.test() gives when
# there are no ties (with ties the report gives tau-b and a continuity corrected normal
# approximation, cor.test(..., exact = FALSE, continuity = TRUE)); the report notes
# the test's low power with fewer than eleven studies. Egger: the intercept of the regression of the standardised
# proportion on precision, with its t test
cat("Bias indicators\n")
se <- (ci[, 2] - ci[, 1]) / 2 / z
pf <- fixed[1]
# Egger's interval is at the level of the bias tests, twice the analysis's alpha
# (90% for a 95% analysis); as the report has it, there is no figure when every
# study has the same precision or the line fits every study exactly
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
  wx <- 1 / se^2
  ts <- (p - sum(p * wx) / sum(wx)) / sqrt(se^2 - 1 / sum(wx))
  tied <- anyDuplicated(ts) > 0 || anyDuplicated(se^2) > 0
  begg <- cor.test(ts, se^2, method = "kendall", exact = if (tied) FALSE else NULL,
                   continuity = TRUE, conf.level = confidence)
  cat("Begg-Mazumdar: Kendall's tau =", six(begg$estimate), " ", pv(begg$p.value),
      if (k < 11 && !is.na(begg$estimate)) "(low power)\n" else "\n")
  egger_figures <- regression(p / se, 1 / se, "Egger", diff(range(1 / se)) > 1e-12 * max(1 / se))

  # Harbord's test as StatsDirect adapts it to proportions: each study's score is the
  # excess of responders over the number expected at the pooled fixed effects proportion,
  # with the binomial variance, and the bias is the intercept of the regression of
  # score / sqrt(variance) on sqrt(variance). A pooled proportion of 0 or 1 leaves no
  # score a variance, and the report then gives no figure
  if (pf > 0 && pf < 1) {
    score <- adherent - total * pf
    vs <- total * pf * (1 - pf)
    harbord_figures <- regression(score / sqrt(vs), sqrt(vs), "Harbord",
                                  sum((sqrt(vs) - mean(sqrt(vs)))^2) > 1e-12 * sum(vs))
  } else {
    harbord_figures <- rep(NA, 4)
    cat("Harbord: bias = * (", round(100 * bias_level, 2), "% CI = * to *)  P = *\n", sep = "")
  }
} else cat("Bias indicators need more than three studies with an estimate\n")

# The report's charts: a funnel plot of each proportion against its standard error,
# with the pooled fixed effects proportion and its 95% limits, then a forest plot for
# each model with the studies in order from the top and the pooled estimate at the foot
plot(p, se, ylim = rev(c(0, max(se))), xlim = c(0, 1), xlab = "Proportion",
     ylab = "Standard error", main = "Bias assessment plot")
abline(v = pf)
s <- seq(0, max(se), length.out = 50)
lines(pf - z * s, s, lty = 2)
lines(pf + z * s, s, lty = 2)
forest <- function(est, lower, upper, weight, title) {
  rows <- c(trial, "combined")
  y <- rev(seq_along(rows))
  old <- par(mar = c(5, 7, 4, 10))
  plot(est, y, type = "n", xlim = c(0, 1), yaxt = "n", ylab = "",
       xlab = paste0("proportion (", pct, " confidence interval)"), main = title)
  segments(lower, y, upper, y)
  points(est[1:k], y[1:k], pch = 15, col = "grey", cex = 3 * sqrt(weight / max(weight)))
  points(est[1:k], y[1:k], pch = 20)
  points(est[k + 1], y[k + 1], pch = 18, cex = 2)
  abline(v = est[k + 1], lty = 3)
  axis(2, at = y, labels = rows, las = 1, tick = FALSE, cex.axis = 0.7)
  axis(4, at = y, tick = FALSE, las = 1, cex.axis = 0.7,
       labels = sprintf("%.2f (%.2f, %.2f)", est, lower, upper))
  par(old)
}
forest(c(p, fixed[1]), c(ci[, 1], fixed[2]), c(ci[, 2], fixed[3]), w,
       "Proportion meta-analysis plot [fixed effects]")
forest(c(p, inv(xr)), c(ci[, 1], inv(xr - z * se_r)), c(ci[, 2], inv(xr + z * se_r)),
       wr, "Proportion meta-analysis plot [random effects]")

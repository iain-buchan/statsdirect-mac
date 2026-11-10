# StatsDirect recipe: Incidence rate difference meta-analysis, as the help shows it in R.
# From the help's R code (meta_analysis/incidence_rate.htm); the data and settings above come from the run.
# data: pt1, a, pt2, b, strata
# settings: confidence = gamma, exact_meta = metaExact, continuity = metaCC

# Keep only studies with all inputs needed for this analysis.
keep <- complete.cases(pt1, a, pt2, b)
if (any(!keep)) cat("(", sum(!keep), " other rows not used)\n", sep = "")
pt1 <- pt1[keep]
a <- a[keep]
pt2 <- pt2[keep]
b <- b[keep]
strata <- strata[keep]
if (is.null(strata)) strata <- paste("Stratum", seq_along(a))
# A stratum whose label is blank has its place among the strata kept, as in the report.
blank <- is.na(strata) | !nzchar(trimws(strata))
strata[blank] <- paste("stratum", which(blank))
# Records saved before version 5.3.10 have neither of these settings: the exact
# methods are then taken to be on and the correction to be the program's default.
if (is.null(exact_meta)) exact_meta <- TRUE
if (is.null(continuity)) continuity <- -9
# Incidence rate meta-analysis: the StatsDirect help example (Rothman and Monson 1973,
# deaths among patients with trigeminal neuralgia in two age strata, exposed and not
# exposed; the test workbook's meta worksheet columns Exposed cases, Exposed
# person-time, Control cases, Control person-time and Age split) in R
pct <- paste0(100 * confidence, "%")
z <- qnorm((1 + confidence) / 2)     # for 95% confidence intervals
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
one <- function(x) formatC(x, digits = 1, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}

# A stratum is pooled when it has an event and both of its groups have person-time;
# the others are listed as excluded. k is the number pooled.
included <- a + b > 0 & pt1 > 0 & pt2 > 0
k <- sum(included)
if (k == 0) stop("None of the strata can be pooled: each of them has no events, or a group with no person-time.")
# A pooled stratum without an event in one of its groups has a continuity correction
# added to the events of both groups, for its variance alone: the
# constant chosen in the program's meta-analysis options if it is between 0 and 1,
# otherwise a half (the treatment arm correction is of the sizes of groups)
cc <- if (continuity > 0 && continuity < 1) continuity else 0.5
cced <- included & (a <= 0 | b <= 0)
ac <- ifelse(cced, a + cc, a)
bc <- ifelse(cced, b + cc, b)
note <- ifelse(!included, "* (excluded)", ifelse(cced, paste0("[CC = ", format(cc), "]"), ""))
shown <- trimws(paste(strata, note))

# Base R has no meta-analysis function, so the pooling follows the formulae above: a
# fixed effects estimate weighted by inverse variance, Cochran's Q for heterogeneity,
# the DerSimonian-Laird moment estimate of the between-studies variance (tau squared,
# zero when Q is below its degrees of freedom) and the random effects estimate, whose
# weights add tau squared to each stratum's variance (two or more strata)
pool <- function(y, v) {
  w <- ifelse(included, 1 / v, 0)
  y <- ifelse(included, y, 0)
  fixed <- sum(w * y) / sum(w)
  q <- if (k > 1) sum(w * (y - fixed)^2) else 0
  spread <- sum(w) - sum(w^2) / sum(w)
  tau2 <- if (k < 2 || spread == 0) 0 else max(0, (q - (k - 1)) / spread)
  wr <- ifelse(included, 1 / (v + tau2), 0)
  list(fixed = fixed, se = sqrt(1 / sum(w)), q = q, tau2 = tau2,
       random = sum(wr * y) / sum(wr), se_r = sqrt(1 / sum(wr)),
       fixed_pct = ifelse(included, 100 * w / sum(w), NA),
       random_pct = ifelse(included, 100 * wr / sum(wr), NA))
}
# The pooled part of the report; f back-transforms a log ratio to a ratio
summarise <- function(p, name, null, f = identity) {
  ci <- function(est, se) {
    paste0("(", pct, " CI = ", six(f(est - z * se)), " to ", six(f(est + z * se)), ")")
  }
  cat("Fixed effects (inverse variance)\n")
  cat("Pooled", name, "=", six(f(p$fixed)), ci(p$fixed, p$se), "\n")
  cat("Z (test ", name, " differs from ", null, ") = ", six(p$fixed / p$se), "  ",
      pv(2 * pnorm(-abs(p$fixed / p$se))), "\n", sep = "")
  cat("Non-combinability of studies\n")
  cat("Cochran Q = ", six(p$q), "  (df = ", k - 1, ")  ",
      pv(if (k > 1) pchisq(p$q, k - 1, lower.tail = FALSE) else NA_real_), "\n", sep = "")
  cat("Moment-based estimate of between studies variance =", six(p$tau2), "\n")
  # I2 is the share of Q beyond its degrees of freedom, with the interval of the
  # report. With the exact methods on, Q is treated as non-central chi-square and its
  # distribution function at the observed Q is inverted for the non-centrality
  # parameter lambda at each tail probability (a limit is 0 when even the central
  # distribution gives less); each limit is lambda / (df + lambda). With them off the
  # interval is the test-based one, which needs three strata, or two whose Q is above 2
  q <- p$q
  df_i2 <- k - 1
  i2 <- if (k < 2) NA_real_ else if (q == 0) 0 else max(0, 100 * (q - df_i2) / q)
  i2_ci <- rep(NA_real_, 2)
  if (k >= 2 && confidence > 0 && confidence < 1) {
    if (isTRUE(exact_meta)) {
      lambda <- function(prob) {
        if (pchisq(q, df_i2) <= prob) 0 else
          uniroot(function(l) pchisq(q, df_i2, ncp = l) - prob,
                  c(0, 10 * q + 100), tol = 1e-10)$root
      }
      lim <- c(lambda((1 + confidence) / 2), lambda((1 - confidence) / 2))
      i2_ci <- 100 * lim / (df_i2 + lim)
    } else if (k >= 3 || q > k) {
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
  cat("Random effects (DerSimonian-Laird)\n")
  cat("Pooled", name, "=", six(f(p$random)), ci(p$random, p$se_r), "\n")
  cat("Z (test ", name, " differs from ", null, ") = ", six(p$random / p$se_r), "  ",
      pv(2 * pnorm(-abs(p$random / p$se_r))), "\n", sep = "")
  invisible(c(i2, i2_ci))
}
# The bias indicators that end the report, which it gives only when more than three
# strata are pooled; y is each pooled stratum's effect and v its variance. Begg and
# Mazumdar's rank correlation is Kendall's tau between each stratum's deviation from
# the pooled effect, standardised by its variance less the pooled variance, and that
# variance: without ties cor.test gives the exact two sided P, and with ties tau b
# and the normal approximation with the continuity correction, as the report does;
# fewer than eleven strata give the test little power. Egger's test regresses each
# standardised effect (the effect over its standard error) on its precision (one
# over that standard error); the bias is the intercept, judged by a t test, and its
# interval is at the level of the bias tests, twice the analysis's alpha (90% for a
# 95% analysis). As the report has it, there is no figure when every stratum has the
# same precision or the line fits every stratum exactly
bias_indicators <- function(y, v) {
  cat("Bias indicators\n")
  if (k < 4) {
    cat("Bias indicators need more than three studies with an estimate\n")
    return(invisible(NULL))
  }
  w <- 1 / v
  dev <- (y - sum(w * y) / sum(w)) / sqrt(v - 1 / sum(w))
  tied <- anyDuplicated(dev) > 0 || anyDuplicated(v) > 0
  begg <- cor.test(dev, v, method = "kendall", exact = if (tied) FALSE else NULL,
                   continuity = TRUE)
  cat("Begg-Mazumdar: Kendall's tau = ", six(begg$estimate), "  ", pv(begg$p.value),
      if (k < 11 && !is.na(begg$estimate)) " (low power)", "\n", sep = "")
  bias_level <- 1 - 2 * (1 - confidence)
  if (!(bias_level > 0 && bias_level < 1)) bias_level <- 0.9
  se <- sqrt(v)
  effect <- y / se
  precision <- 1 / se
  fit <- lm(effect ~ precision)
  if (diff(range(precision)) > 1e-12 * max(precision) &&
      sum(residuals(fit)^2) > 1e-12 * sum(effect^2)) {
    bias <- coef(summary(fit))[1, ]
    limits <- confint(fit, level = bias_level)[1, ]
  } else bias <- limits <- c(Estimate = NA, "Pr(>|t|)" = NA)
  cat("Egger: bias = ", six(bias["Estimate"]), " (", round(100 * bias_level, 2), "% CI = ",
      six(limits[1]), " to ", six(limits[2]), ")  ", pv(bias["Pr(>|t|)"]), "\n", sep = "")
  invisible(list(begg = unname(c(begg$estimate, begg$p.value)),
                 egger = unname(c(bias["Estimate"], limits[1:2], bias["Pr(>|t|)"]))))
}
# The forest plots that follow in the report: each stratum's estimate and interval, a
# box that grows with its weight, and the pooled estimate as a diamond at the foot; an
# excluded stratum has a row without an estimate, and a limit of 0 or infinity runs to
# the edge of the plot
forest <- function(est, lower, upper, pooled, p_lower, p_upper, pct, main, xlab,
                   null, log = "") {
  par(mar = c(5, 7, 4, 2))
  rows <- length(est)
  y <- (rows + 1):2
  limits <- c(lower, upper, p_lower, p_upper)
  xlim <- range(limits[is.finite(limits) & (log == "" | limits > 0)])
  plot(NA, xlim = xlim, ylim = c(0.5, rows + 1.5),
       log = log, yaxt = "n", ylab = "", xlab = xlab, main = main)
  axis(2, at = c(y, 1), labels = c(strata, "combined"), las = 1, tick = FALSE)
  abline(v = null, lty = 3)
  segments(pmax(lower, xlim[1]), y, pmin(upper, xlim[2]), y)
  points(est, y, pch = 15, cex = 0.5 + 2 * sqrt(pct / 100))
  polygon(c(p_lower, pooled, p_upper, pooled), c(1, 1.2, 1, 0.8), col = "grey")
}

# Each stratum's incidence rate difference, with its approximate interval: the
# difference plus and minus z standard errors, from the Poisson variance of the
# difference, a/pt1^2 + b/pt2^2 (of the corrected events in a stratum without an event
# in one of its groups), which the fixed effects weights invert
ird <- ifelse(included, a / pt1 - b / pt2, NA)
v_ird <- ifelse(included, ac / pt1^2 + bc / pt2^2, NA)
se_ird <- sqrt(v_ird)
res <- pool(ird, v_ird)
cat("Incidence rate difference (IRD) meta-analysis\n")
print(data.frame(stratum = seq_along(a), IRD = six(ird), lower = six(ird - z * se_ird),
                 upper = six(ird + z * se_ird), strata = shown), row.names = FALSE)
# The report's next table: the standardised effect is the difference itself, with its
# variance beside the weights
print(data.frame(stratum = seq_along(a), effect = six(ird), variance = six(v_ird),
                 fixed = six(res$fixed_pct), random = six(res$random_pct), strata = shown),
      row.names = FALSE)
i2_figures <- summarise(res, "IRD", 0)
bias_figures <- bias_indicators(ird[included], v_ird[included])
forest(ird, ird - z * se_ird, ird + z * se_ird, res$fixed, res$fixed - z * res$se,
       res$fixed + z * res$se, res$fixed_pct,
       "Incidence rate difference meta-analysis plot [fixed effects]",
       paste0("incidence rate difference (", pct, " confidence interval)"), 0)
forest(ird, ird - z * se_ird, ird + z * se_ird, res$random, res$random - z * res$se_r,
       res$random + z * res$se_r, res$random_pct,
       "Incidence rate difference meta-analysis plot [random effects]",
       paste0("incidence rate difference (", pct, " confidence interval)"), 0)

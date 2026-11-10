# StatsDirect recipe: Effect size meta-analysis, as the help shows it in R.
# From the help's R code (meta_analysis/effect_size.htm); the data and settings above come from the run.
# data: en = en, em = em, es = es, cn = cn, cm = cm, cs = cs, gin = g, trial = strata
# settings: confidence = gamma, type = type, exact_meta = metaExact

# A supplied effect size needs only the two sample sizes; the other methods
# need both means and standard deviations as well.
keep <- if (type == "g") complete.cases(en, cn, gin) else complete.cases(en, cn, em, es, cm, cs)
if (any(!keep)) cat("(", sum(!keep), " other rows not used)\n", sep = "")
en <- en[keep]
em <- em[keep]
es <- es[keep]
cn <- cn[keep]
cm <- cm[keep]
cs <- cs[keep]
gin <- gin[keep]
trial <- trial[keep]
if (is.null(trial)) trial <- paste("Trial", seq_along(en))
# A study whose label is blank has its place among the studies kept, as in the report.
blank <- is.na(trial) | !nzchar(trimws(trial))
trial[blank] <- paste("stratum", which(blank))
# Effect size meta-analysis: the StatsDirect help example (Freemantle, personal
# communication, test outcomes of seven comparisons from six trials of an educational
# intervention; the test workbook's meta worksheet columns J to P) in R
pct <- paste0(100 * confidence, "%")
k <- length(en)

# Base R has no meta-analysis function, so the statistics are computed as the
# formulae above give them. g is the difference in means over the pooled standard
# deviation; d is g corrected for its small sample bias by J(N - 2), computed from
# the gamma function (lgamma is its logarithm), or from the usual approximation
# 1 - 3 / (4m - 1) when N - 2 is 200 or more
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
n <- en + cn
m <- n - 2
if (type == "g") g <- gin else {   # the effect sizes given, or from the means and standard deviations
  s <- sqrt(((en - 1) * es^2 + (cn - 1) * cs^2) / m)
  g <- (em - cm) / s
}
J <- ifelse(m < 200, exp(lgamma(m / 2) - lgamma((m - 1) / 2)) / sqrt(m / 2),
            1 - 3 / (4 * m - 1))
d <- if (type == "m") em - cm else J * g   # the weighted mean difference is the difference itself
z <- qnorm((1 + confidence) / 2)

# The approximate confidence interval for d uses its large sample variance. The
# exact interval for g comes from the noncentral t distribution: g times
# sqrt(ne * nc / N) is a t statistic on N - 2 degrees of freedom whose
# noncentrality parameter is the true effect size times the same factor, so each
# limit is the noncentrality parameter that puts the observed statistic at the
# 97.5th or the 2.5th percentile, found with uniroot and pt. R's pt is accurate
# for noncentrality parameters up to 37.62 (see its help page); here the largest is
# under 5, so a guard is only needed for a very large trial with a large effect
vard <- if (type == "m") es^2 / en + cs^2 / cn else n / (en * cn) + d^2 / (2 * n)
lcid <- d - z * sqrt(vard)
ucid <- d + z * sqrt(vard)
scale <- sqrt(en * cn / n)
ncp_limit <- function(t, df, hw, p) {
  f <- function(nc) pt(t, df, ncp = nc) - p
  uniroot(f, if (p > 0.5) c(t - 2 * hw, t) else c(t, t + 2 * hw), tol = 1e-10)$root
}
if (type != "m") {   # the exact limits and the table of g: not for a mean difference
hw <- z * sqrt(vard) * scale
lcig <- mapply(ncp_limit, g * scale, m, hw, (1 + confidence) / 2) / scale
ucig <- mapply(ncp_limit, g * scale, m, hw, (1 - confidence) / 2) / scale
print(data.frame(trial, J = six(J), g = six(g), exact_lower = six(lcig),
                 exact_upper = six(ucig)), row.names = FALSE)
}
print(data.frame(trial, en, cn, d = six(d), approx_lower = six(lcid),
                 approx_upper = six(ucid)), row.names = FALSE)

if (k == 1) {
  cat("% weights (fixed, random)\n")
  cat("Bias indicators\n")
  cat("Bias indicators need more than three studies with an estimate\n")
} else {
  # Fixed effects (Hedges-Olkin): d weighted by the inverse of its variance
  w <- 1 / vard
  dplus <- sum(w * d) / sum(w)
  se_dplus <- sqrt(1 / sum(w))
  cat("Fixed effects (Hedges-Olkin)\n")
  cat("Pooled effect size d+ = ", six(dplus), " (", pct, " CI = ", six(dplus - z * se_dplus),
      " to ", six(dplus + z * se_dplus), ")\n", sep = "")
  cat("Z (test d+ differs from 0) =", six(dplus / se_dplus), " ",
      pv(2 * pnorm(-abs(dplus / se_dplus))), "\n")

  # Cochran's Q and the DerSimonian-Laird between-study variance.
  Q <- sum(w * (d - dplus)^2)
  df <- k - 1
  spread <- sum(w) - sum(w^2) / sum(w)
  tausq <- if (spread == 0) 0 else max(0, (Q - df) / spread)
  one <- function(x) formatC(x, digits = 1, format = "f", drop0trailing = TRUE)
  cat("Non-combinability of studies\n")
  cat("Cochran Q = ", six(Q), "  (df = ", df, ")  ",
      pv(pchisq(Q, df, lower.tail = FALSE)), "\n", sep = "")
  cat("Moment-based estimate of between studies variance =", six(tausq), "\n")
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
  if (k < 2) cat("I-squared not calculated: at least two studies are required.\n") else if (anyNA(i2_ci))
    cat("I-squared (inconsistency) =", one(i2), "% (interval unavailable for this number of studies and confidence level)\n") else
    cat("I-squared (inconsistency) = ", one(i2), "% (", pct, " CI = ",
        one(i2_ci[1]), "% to ", one(i2_ci[2]), "%)\n", sep = "")
  # End of I-squared interval.

  # Random effects (DerSimonian-Laird): the between studies variance is added to
  # each study's variance before weighting
  wr <- 1 / (vard + tausq)
  dsd <- sum(wr * d) / sum(wr)
  se_dsd <- sqrt(1 / sum(wr))
  cat("Random effects (DerSimonian-Laird)\n")
  cat("Pooled d+ = ", six(dsd), " (", pct, " CI = ", six(dsd - z * se_dsd), " to ",
      six(dsd + z * se_dsd), ")\n", sep = "")
  cat("Z (test d+ differs from 0) =", six(dsd / se_dsd), " ",
      pv(2 * pnorm(-abs(dsd / se_dsd))), "\n")
  cat("% weights (fixed, random)\n")
  print(data.frame(trial, fixed = six(100 * w / sum(w)),
                   random = six(100 * wr / sum(wr))), row.names = FALSE)

  # Bias indicators. Begg and Mazumdar's test is Kendall's rank correlation between
  # each study's standardised deviation from the pooled effect and its variance,
  # with the exact P value; cor.test computes it by default only for fewer than 50
  # studies, so exact = TRUE asks for it whatever their number (with ties the program
  # uses tau-b with a normal approximation and a continuity correction instead, which
  # is cor.test(..., exact = FALSE, continuity = TRUE)).
  # The report notes the test's low power with fewer than eleven studies. Egger's test
  # regresses the standard normal deviate d / se on the precision 1 / se: the
  # intercept estimates the bias, judged on k - 2 degrees of freedom. The report gives
  # the bias indicators only with more than three studies.
  se <- sqrt(vard)
  cat("Bias indicators\n")
  # Egger's interval is at the level of the bias tests, twice the analysis's alpha
  # (90% for a 95% analysis); as the report has it, there is no figure when every
  # study has the same precision or the line fits every study exactly
  bias_level <- 1 - 2 * (1 - confidence)
  if (!(bias_level > 0 && bias_level < 1)) bias_level <- 0.9
  if (k > 3) {
    ts <- (d - dplus) / sqrt(vard - 1 / sum(w))
    tied <- anyDuplicated(ts) > 0 || anyDuplicated(vard) > 0
    begg <- cor.test(ts, vard, method = "kendall", exact = !tied, continuity = TRUE,
                     conf.level = confidence)
    power_note <- if (k < 11 && !is.na(begg$estimate)) "(low power)" else ""
    cat("Begg-Mazumdar: Kendall's tau =", six(begg$estimate), " ", pv(begg$p.value),
        power_note, "\n")
    egger <- lm(I(d / se) ~ I(1 / se))
    if (diff(range(1 / se)) > 1e-12 * max(1 / se) && sum(residuals(egger)^2) > 1e-12 * sum((d / se)^2)) {
      bias <- coef(summary(egger))[1, ]
      ci <- confint(egger, level = bias_level)[1, ]
    } else {
      bias <- c(Estimate = NA, "Pr(>|t|)" = NA)
      ci <- c(NA, NA)
    }
    egger_figures <- unname(c(bias["Estimate"], ci, bias["Pr(>|t|)"]))
    cat("Egger: bias = ", six(bias["Estimate"]), " (", round(100 * bias_level, 2), "% CI = ",
        six(ci[1]), " to ", six(ci[2]), ")  ",
        pv(bias["Pr(>|t|)"]), "\n", sep = "")
  } else cat("Bias indicators need more than three studies with an estimate\n")

  # The bias assessment plot that follows in the report: each study's d against its
  # standard error, with the smallest standard errors at the top, the fixed effects
  # pooled d+ as a vertical line and the limits expected around it as a funnel
  plot(d, se, ylim = rev(range(0, se)), xlim = range(lcid, ucid), pch = 1,
       xlab = "Effect size", ylab = "Standard error", main = "Bias assessment plot")
  abline(v = dplus)
  se_line <- seq(0, max(se), length.out = 100)
  lines(dplus + z * se_line, se_line)
  lines(dplus - z * se_line, se_line)

  # The forest plots: each study's d with its approximate interval and a square
  # proportional to its size, then the pooled estimate as a diamond, for the fixed
  # and the random effects models (the program prefixes the random effects label
  # with DL for DerSimonian-Laird)
  forest <- function(pooled, lower, upper, label) {
    y <- k:1 + 1
    plot(d, y, xlim = range(lcid, ucid, lower, upper), ylim = c(0.5, k + 1.5),
         yaxt = "n", ylab = "", xlab = "", main = label, pch = 15,
         cex = 1 + 2 * n / max(n))
    axis(2, at = c(y, 1), labels = c(trial, "pooled"), las = 1, tick = FALSE)
    segments(lcid, y, ucid, y)
    polygon(c(lower, pooled, upper, pooled), c(1, 1.25, 1, 0.75))
    abline(v = pooled, lty = 2)
    if (min(lcid) < 0) abline(v = 0)
    prefix <- if (grepl("random", label)) "DL " else ""
    mtext(paste0(prefix, "pooled effect size = ", six(pooled), "  (", pct, " CI = ",
                 six(lower), " to ", six(upper), ")"), side = 3, line = 0.3, cex = 0.9)
  }
  op <- par(mar = c(3, 9, 4, 1))
  forest(dplus, dplus - z * se_dplus, dplus + z * se_dplus,
         "Effect size meta-analysis plot [fixed effects]")
  forest(dsd, dsd - z * se_dsd, dsd + z * se_dsd,
         "Effect size meta-analysis plot [random effects]")
  par(op)
}

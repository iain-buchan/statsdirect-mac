# StatsDirect recipe: Mantel-Haenszel analysis of a series of 2 by 2 tables typed on screen, as the help shows it in R.
# From the help's R code (meta_analysis/mh.htm); the data and settings above come from the run.
# data: left = data, right = data
# settings: confidence = cco, exact_meta = try_exact, continuity = metaCC, delay_cc = delayContinuityCorrection

# each stratum's table from the two columns: the left column holds the exposed group's cases then non-cases, the right the unexposed group's
smokers_cancer <- left[c(TRUE, FALSE)]
smokers <- smokers_cancer + left[c(FALSE, TRUE)]
nonsmokers_cancer <- right[c(TRUE, FALSE)]
nonsmokers <- nonsmokers_cancer + right[c(FALSE, TRUE)]
strata <- paste("stratum", seq_along(smokers))
# Odds ratio meta-analysis (Mantel-Haenszel and exact): the StatsDirect help example
# (Armitage and Berry 1994, smoking among lung cancer patients and controls in ten
# case-control studies; the test workbook's Meta-analysis worksheet columns Smokers
# total, Smokers cancer, Control total and Control cancer) in R
pct <- paste0(100 * confidence, "%")

# Each study's fourfold table: a and b are the smokers and non-smokers with lung
# cancer, c and d the smokers and non-smokers among the controls (the workbook's
# "Control" columns are the non-smokers), so the odds ratio a d / (b c) is the odds
# of smoking among the patients relative to the controls
a <- smokers_cancer
b <- nonsmokers_cancer
c <- smokers - a
d <- nonsmokers - b
n <- a + b + c + d
tables <- array(rbind(a, b, c, d), dim = c(2, 2, length(a)),
                dimnames = list(smoking = c("smoker", "non-smoker"),
                                group = c("lung cancer", "control"), study = seq_along(a)))

# Older records without a stored method used exact limits.
if (is.null(exact_meta)) exact_meta <- TRUE
# Nor did they store the continuity correction: the program's default is the
# treatment arm correction, not delayed.
if (is.null(continuity)) continuity <- -9
if (is.null(delay_cc)) delay_cc <- FALSE

# The report's lines to 6 places
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
z <- qnorm((1 + confidence) / 2)

# A study is pooled when both of its groups have subjects and it has both an event
# and a subject without one; the others are listed as excluded. k is the number
# pooled. A pooled study with an empty cell has a continuity correction in every
# cell for its odds ratio and its variance (its exact limits use the cells as they
# are): the program's default, the treatment arm correction (Sweeting, Sutton and
# Lambert 2004), adds n1 / (n1 + n2) to the cells of the first group and
# n2 / (n1 + n2) to those of the second; a set correction between 0 and 1 is added
# to every cell, and any other value adds a half. The Mantel-Haenszel pooling uses
# the corrected cells too, or, with the correction delayed and some study with a d
# above 0, the cells as they are.
included <- a + c > 0 & b + d > 0 & !(a == 0 & b == 0) & !(c == 0 & d == 0)
k <- sum(included)
correct <- function(a, b, c, d) {
  x <- if (continuity == 0) 0.5 else continuity
  if (x == -9 && a + c > 0 && b + d > 0) {
    r <- (b + d) / (a + c)
    c(a + 1 / (r + 1), b + r / (r + 1), c + 1 / (r + 1), d + r / (r + 1))
  } else c(a, b, c, d) + if (x > 0 && x < 1) x else 0.5
}
cced <- included & (a <= 0 | b <= 0 | c <= 0 | d <= 0)
corrected <- cbind(a, b, c, d)
for (i in which(cced)) corrected[i, ] <- correct(a[i], b[i], c[i], d[i])
a1 <- corrected[, 1]
b1 <- corrected[, 2]
c1 <- corrected[, 3]
d1 <- corrected[, 4]
pool_raw <- isTRUE(delay_cc) && any(a * d != 0)
note <- ifelse(!included, "* (excluded)", ifelse(cced, paste0(if (isTRUE(delay_cc)) "[late CC = " else "[CC = ",
  if (continuity == -9) "treatment arm" else format(continuity), "]"), ""))

# The exact block below uses tighter root tolerances than R's standard exact test,
# and adds mid-P limits and P values, so it is calculated separately.

# The exact methods condition on every table's margins: given them, the total of
# the a cells has a distribution proportional to a product of hypergeometric terms
# times psi^a, where psi is the common odds ratio. The function returns the log of
# each term at psi = 1 over the support of the total (the terms are convolved on the
# natural scale, each table's rescaled to a maximum of 1 to keep within range)
conditional <- function(a, b, c, d) {
  exposed <- a + c
  unexposed <- b + d
  cases <- a + b
  coef <- 1
  start <- 0
  for (i in seq_along(a)) {
    x <- max(0, cases[i] - unexposed[i]):min(exposed[i], cases[i])
    p <- dhyper(x, exposed[i], unexposed[i], cases[i])
    p <- p / max(p)
    new <- numeric(length(coef) + length(p) - 1)
    for (j in seq_along(p)) {
      at <- j:(j + length(coef) - 1)
      new[at] <- new[at] + coef * p[j]
    }
    coef <- new / max(new)
    start <- start + x[1]
  }
  list(support = start + seq_along(coef) - 1, logc = log(coef))
}
# The probability of the part of the support that 'which' selects, at odds ratio psi
cond_p <- function(dist, psi, which) {
  lw <- dist$logc + dist$support * log(psi)
  w <- exp(lw - max(lw))
  sum(w[which]) / sum(w)
}
# Solve for psi on the log scale: the conditional mean equal to the observed total
# (the conditional maximum likelihood estimate), or a tail probability equal to
# alpha / 2 (an exact limit); 'half' counts half of the observed total's probability
# for the mid-P limits
cond_solve <- function(dist, target, s, side = "mean", half = FALSE) {
  f <- function(t) {
    if (side == "mean") {
      lw <- dist$logc + dist$support * t
      w <- exp(lw - max(lw))
      return(sum(dist$support * w) / sum(w) - s)
    }
    p <- if (side == "upper") cond_p(dist, exp(t), dist$support > s) else
      cond_p(dist, exp(t), dist$support < s)
    if (half) p + 0.5 * cond_p(dist, exp(t), dist$support == s) - target else
      p + cond_p(dist, exp(t), dist$support == s) - target
  }
  exp(uniroot(f, c(-30, 30), tol = 1e-10)$root)
}
exact_limits <- function(dist, s, level = 0.95, half = FALSE) {
  alpha <- (1 - level) / 2
  if (s == min(dist$support)) lower <- 0 else
    lower <- cond_solve(dist, alpha, s, "upper", half)
  if (s == max(dist$support)) upper <- Inf else
    upper <- cond_solve(dist, alpha, s, "lower", half)
  c(lower, upper)
}

# Each study's odds ratio and selected confidence interval; an excluded study's are
# 0, and 0 to infinity, as the report gives them.
or <- ifelse(included, a1 * d1 / (b1 * c1), 0)
v_woolf <- ifelse(included, 1 / a1 + 1 / b1 + 1 / c1 + 1 / d1, NA)
if (isTRUE(exact_meta)) {
  # Exact conditional limits use the study table as entered.
  limits <- vapply(seq_along(a), function(i) {
    if (included[i]) exact_limits(conditional(a[i], b[i], c[i], d[i]), a[i], level = confidence)
    else c(0, Inf)
  }, numeric(2))
  lci <- limits[1, ]
  uci <- limits[2, ]
  study_method <- "CML"
} else {
  # Woolf limits use the usual log-odds-ratio standard error.
  margin <- z * sqrt(v_woolf)
  lci <- ifelse(included, exp(log(or) - margin), 0)
  uci <- ifelse(included, exp(log(or) + margin), Inf)
  study_method <- "logit"
}
cat("Stratum, odds ratio, ", pct, " CI (", study_method, ")\n", sep = "")
for (i in seq_along(a)) {
  cat(i, six(or[i]), six(lci[i]), six(uci[i]), note[i], "\n")
}

# The Mantel-Haenszel estimate R / S, R the sum of a d / n and S that of b c / n
# (whose terms are the fixed effects weights), with the Robins, Breslow and Greenland
# interval, and the Mantel-Haenszel chi-square of the cells as they are, with the
# continuity correction. R's standard test gives them when it pools the cells the
# report pools; with corrected cells, a single study, or no S (the interval is then
# Sato's, without an upper limit) they come from the same formulae.
ap <- if (pool_raw) a else a1
bp <- if (pool_raw) b else b1
cp <- if (pool_raw) c else c1
dp <- if (pool_raw) d else d1
np <- ap + bp + cp + dp
R <- ifelse(included, ap * dp / np, 0)
S <- ifelse(included, bp * cp / np, 0)
P <- (ap + dp) / np
Q <- (bp + cp) / np
standard <- k >= 2 && sum(S) > 0 && (pool_raw || !any(cced))
if (standard) {
  # R's standard test: the Mantel-Haenszel estimate of the common odds ratio with a
  # confidence interval that equals the report's Robins, Breslow and Greenland
  # interval, and the Mantel-Haenszel chi-square with the continuity correction
  # (correct = TRUE is the default)
  r <- mantelhaen.test(tables[, , included, drop = FALSE], conf.level = confidence)
  or_mh <- unname(r$estimate)
  mh_ci <- unname(r$conf.int)
  x2 <- as.numeric(r$statistic)
} else {
  delta <- sum((a - (a + c) * (a + b) / n)[included])
  var_delta <- sum(((a + c) * (b + d) * (a + b) * (c + d) / (n^2 * (n - 1)))[included & n > 1])
  x2 <- (abs(delta) - if (abs(delta) >= 0.5) 0.5 else 0)^2 / var_delta
  if (sum(S) > 0) {
    or_mh <- sum(R) / sum(S)
    v_rbg <- sum(P * R) / (2 * sum(R)^2) + sum(Q * R + P * S) / (2 * sum(R) * sum(S)) +
      sum(Q * S) / (2 * sum(S)^2)
    mh_ci <- exp(log(or_mh) + c(-1, 1) * z * sqrt(v_rbg))
  } else {
    # Sato (1990): the limits are the odds ratios psi with (R - psi S)^2 no more than
    # z^2 psi W, W the sum of (Q + 1 / n) R + (P + 1 / n) S; without S there is no
    # upper limit
    or_mh <- NA
    w_sato <- sum(((Q + 1 / np) * R + (P + 1 / np) * S)[included])
    mh_ci <- c(sum(R)^2 / (z^2 * w_sato), Inf)
  }
}
wt_fixed <- 100 * S / sum(S)

# Heterogeneity: Breslow-Day compares each pooled study's a cell with its
# expectation under the pooled odds ratio (the root of a quadratic, or of its linear
# term when the pooled odds ratio is 1), and Cochran's Q is the weighted sum of
# squared deviations of the log odds ratios from the log of the pooled odds ratio,
# weighted by the inverse of each study's logit (Woolf) variance
cases <- a + b
controls <- c + d
exposed <- a + c
unexposed <- b + d
qa <- 1 - or_mh
qb <- unexposed - cases + (exposed + cases) * or_mh
qc <- -cases * exposed * or_mh
ea <- if (isTRUE(qa == 0)) -qc / qb else (-qb + sqrt(qb^2 - 4 * qa * qc)) / (2 * qa)
v_ea <- 1 / (1 / ea + 1 / (cases - ea) + 1 / (exposed - ea) +
               1 / (controls - exposed + ea))
bd <- if (k > 1) sum(((a - ea)^2 / v_ea)[included]) else 0
yi <- ifelse(included, log(or), NA)
w <- ifelse(included, 1 / v_woolf, 0)
q <- if (k > 1) sum((w * (yi - log(or_mh))^2)[included]) else 0

# DerSimonian-Laird: the moment estimate of the between studies variance (not less
# than zero), the random effects weights and the pooled odds ratio
spread <- sum(w)^2 - sum(w^2)
tau2 <- if (spread == 0) 0 else max(0, (q - (k - 1)) * sum(w) / spread)
w_re <- ifelse(included, 1 / (tau2 + v_woolf), 0)
wt_random <- 100 * w_re / sum(w_re)
or_re <- exp(sum((w_re * yi)[included]) / sum(w_re))
x2_re <- sum((w_re * yi)[included])^2 / sum(w_re)

# The report's second table: the standardised effect is the log odds ratio, with
# its logit (Woolf) variance, and the weights are percentages
vi <- v_woolf
cat("Stratum, standardized effect, variance, % weights (fixed, random)\n")
for (i in seq_along(a)) {
  cat(i, six(yi[i]), six(vi[i]), six(wt_fixed[i]), six(wt_random[i]), note[i], "\n")
}

cat("Fixed effects (Mantel-Haenszel, ", if (is.na(or_mh)) "Sato" else "Robins-Breslow-Greenland", ")\n", sep = "")
cat("Pooled odds ratio = ", if (is.na(or_mh)) "undefined" else six(or_mh), " (", pct, "CI = ",
    six(mh_ci[1]), " to ", six(mh_ci[2]), ")\n", sep = "")
cat("Chi2 (test odds ratio differs from 1) =", six(x2), " ", pv(pchisq(x2, 1, lower.tail = FALSE)), "\n")

# The pooled exact analysis: the conditional maximum likelihood estimate, the exact
# Fisher and mid-P limits, and the P values at odds ratio 1 (the Fisher two sided P
# sums the probabilities of totals no more probable than the one observed, within a
# relative 1e-7 as the report and fisher.test have it, so that a total exactly as
# probable is counted whatever its rounding); an observed total at an end of its
# support gives an estimate of 0 or infinity
if (isTRUE(exact_meta)) {
  all <- conditional(a, b, c, d)
  s <- sum(a)
  cml <- if (s == max(all$support)) Inf else if (s == min(all$support)) 0 else cond_solve(all, 0, s)
  fisher <- exact_limits(all, s, level = confidence)
  midp <- exact_limits(all, s, level = confidence, half = TRUE)
  p_upper <- cond_p(all, 1, all$support >= s)
  p_lower <- cond_p(all, 1, all$support <= s)
  p_at_s <- cond_p(all, 1, all$support == s)
  w1 <- exp(all$logc - max(all$logc))
  p2_fisher <- sum(w1[w1 <= w1[all$support == s] * (1 + 1e-7)]) / sum(w1)
  p1_mid <- min(p_upper - p_at_s / 2, 1 - (p_upper - p_at_s / 2))
  cat("Fixed effects (conditional maximum likelihood)\n")
  cat("Pooled odds ratio =", six(cml), "\n")
  cat("Exact Fisher", pct, "CI =", six(fisher[1]), "to", six(fisher[2]), "\n")
  cat("Exact Fisher one sided ", pv(min(p_upper, p_lower)), ", two sided ",
      pv(p2_fisher), "\n", sep = "")
  cat("Exact mid-P", pct, "CI =", six(midp[1]), "to", six(midp[2]), "\n")
  cat("Exact mid-P one sided ", pv(p1_mid), ", two sided ", pv(min(1, 2 * p1_mid)),
      "\n", sep = "")
}

df <- k - 1
one <- function(x) formatC(x, digits = 1, format = "f", drop0trailing = TRUE)
cat("Non-combinability of studies\n")
cat("Breslow-Day = ", six(bd), "  (df = ", df, ")  ",
    pv(pchisq(bd, df, lower.tail = FALSE)), "\n", sep = "")
cat("Cochran Q = ", six(q), "  (df = ", df, ")  ",
    pv(pchisq(q, df, lower.tail = FALSE)), "\n", sep = "")
cat("Moment-based estimate of between studies variance =", six(tau2), "\n")
# I-squared interval: recorded exact/test-based choice. Without a pooled odds ratio
# (Sato's interval) Q, and so I-squared, are undefined, as in the report.
df_i2 <- k - 1
i2 <- if (k < 2 || is.na(q)) NA_real_ else if (q == 0) 0 else max(0, 100 * (q - df_i2) / q)
i2_ci <- rep(NA_real_, 2)
if (k >= 2 && !is.na(q) && confidence > 0 && confidence < 1) {
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
  cat("I2 (inconsistency) = ", one(i2), "% (", pct, "CI = ",
      one(i2_ci[1]), "% to ", one(i2_ci[2]), "%)\n", sep = "")
# End of I-squared interval.

re_ci <- exp(log(or_re) + c(-1, 1) * z / sqrt(sum(w_re)))
cat("Random effects (DerSimonian-Laird)\n")
cat("Pooled odds ratio = ", six(or_re), " (", pct, "CI = ", six(re_ci[1]), " to ",
    six(re_ci[2]), ")\n", sep = "")
cat("Chi2 (test odds ratio differs from 1) =", six(x2_re), " (df = 1) ",
    pv(pchisq(x2_re, 1, lower.tail = FALSE)), "\n")

# Bias indicators, from the pooled studies' log odds ratios and their logit
# standard errors, which the report gives only when more than three studies are
# pooled. Begg-Mazumdar: Kendall's tau between the deviations of the log odds ratios
# from their weighted mean, standardised, and the variances; cor.test gives the
# exact two sided P because there are fewer than 50 studies and no ties. With tied
# variances the report uses tau-b and a continuity-corrected normal approximation,
# cor.test(..., exact = FALSE, continuity = TRUE). The report adds "(low power)"
# with fewer than eleven studies: the rank correlation test then has little power
se <- sqrt(v_woolf)
cat("Bias indicators\n")
# Egger's and Harbord's intervals are at the level of the bias tests, twice the
# analysis's alpha (90% for a 95% analysis), because the tests have low power; as
# the report has it, there is no figure when every study has the same precision or
# the line fits every study exactly
bias_level <- 1 - 2 * (1 - confidence)
if (!(bias_level > 0 && bias_level < 1)) bias_level <- 0.9
regression <- function(y, x, label, spread) {
  fit <- lm(y ~ x)
  if (spread && sum(residuals(fit)^2) > 1e-12 * sum(y^2)) {
    ci <- confint(fit, level = bias_level)
    figures <- c(coef(fit)[1], ci[1, 1], ci[1, 2], summary(fit)$coefficients[1, 4])
  } else figures <- rep(NA, 4)
  cat(label, ": bias = ", six(figures[1]), " (", round(100 * bias_level, 2), "% CI = ",
      six(figures[2]), " to ", six(figures[3]), ")  ", pv(figures[4]), "\n", sep = "")
  invisible(unname(figures))
}
if (k > 3) {
  dev <- (yi - sum((w * yi)[included]) / sum(w)) / sqrt(v_woolf - 1 / sum(w))
  begg <- cor.test(dev[included], v_woolf[included], method = "kendall", conf.level = confidence)
  cat("Begg-Mazumdar: Kendall's tau =", six(begg$estimate), " ", pv(begg$p.value),
      "(low power)\n")
  # Egger: the standardised effect regressed on precision, the intercept being the
  # bias
  precision <- 1 / se[included]
  egger_figures <- regression(yi[included] / se[included], precision, "Egger",
                      diff(range(precision)) > 1e-12 * max(precision))
  # Harbord-Egger: the same regression of each study's efficient score (a minus its
  # expectation) divided by the root of its hypergeometric variance, on that root,
  # from the cells as they are, in the studies whose score has a variance
  score <- a - cases * exposed / n
  v_score <- cases * controls * exposed * unexposed / (n^2 * (n - 1))
  scored <- included & n > 1 & v_score > 0
  if (sum(scored) > 3) {
    root_v <- sqrt(v_score[scored])
    harbord_figures <- regression(score[scored] / root_v, root_v, "Harbord-Egger",
                          sum((root_v - mean(root_v))^2) > 1e-12 * sum(root_v^2))
  } else {
    harbord_figures <- rep(NA, 4)
    cat("Harbord-Egger: bias = * (", round(100 * bias_level, 2), "% CI = * to *)  P = *\n", sep = "")
  }
} else cat("Bias indicators need more than three studies with an estimate\n")

# The report's charts. First the bias assessment (funnel) plot: each log odds ratio
# against its logit standard error, the axis reversed so that the 95% cone about the
# pooled Mantel-Haenszel log odds ratio opens downwards (no cone when that estimate
# is undefined)
centre <- log(or_mh)
se_top <- max(se, na.rm = TRUE) * 1.05
plot(yi, se, ylim = c(se_top, 0), xlab = "Log(Odds ratio)", ylab = "Standard error",
     main = "Bias assessment plot",
     xlim = range(yi, centre + c(-1, 1) * z * se_top, na.rm = TRUE))
if (!is.na(centre)) {
  abline(v = centre)
  lines(centre + c(-1, 0, 1) * z * se_top, c(se_top, 0, se_top))
}

# The L'Abbe plot: the percentage of each study's smokers who were lung cancer
# patients against the same percentage of its non-smokers, the symbol size growing
# with the study size, with the line of equality. The report adds a dashed line from
# the origin with the slope of the pooled odds ratio, which is the line of a risk
# ratio; the curve of the studies that share the pooled odds ratio is drawn here
p0 <- 100 * b / (b + d)
p1 <- 100 * a / (a + c)
plot(p0, p1, xlim = c(0, 100), ylim = c(0, 100), cex = 0.5 + 2 * sqrt(n / max(n)),
     xlab = "control percent", ylab = "experimental percent",
     main = "L'Abbe plot (symbol size represents sample size)")
abline(0, 1)
x0 <- seq(0, 1, 0.01)
if (!is.na(or_mh)) lines(100 * x0, 100 * or_mh * x0 / (1 + (or_mh - 1) * x0), lty = 2)

# The two forest plots: each study's odds ratio (the symbol area proportional to
# its weight) with its selected interval on a log scale, the line of no effect at 1,
# and the pooled estimate as a diamond at the foot with a dashed line up from it; an
# excluded study has a row without an estimate, and an infinite or zero limit runs to
# the edge of the plot. The report draws them only when the Mantel-Haenszel
# estimate is defined.
forest <- function(pooled, lower, upper, weights, main, label) {
  y <- (length(a) + 1):2
  two <- function(x) formatC(x, digits = 2, format = "f")
  limits <- c(1, lci[included], uci[included], lower, upper)
  xlim <- range(limits[is.finite(limits) & limits > 0])
  par(mar = c(5, 8, 4, 9))
  plot(NA, xlim = xlim, ylim = c(0.5, length(a) + 1.5),
       log = "x", yaxt = "n", xlab = paste0("odds ratio (", pct, " confidence interval)"),
       ylab = "", main = main)
  abline(v = 1)
  segments(pooled, 1, pooled, length(a) + 1, lty = 2)
  segments(pmax(lci, xlim[1])[included], y[included], pmin(uci, xlim[2])[included], y[included])
  points(or[included], y[included], pch = 15, cex = 0.5 + 2 * sqrt(weights[included] / max(weights)))
  polygon(c(lower, pooled, upper, pooled), c(1, 1.3, 1, 0.7), col = "grey")
  axis(2, at = c(y, 1), labels = c(strata, label), las = 1,
       tick = FALSE)
  axis(4, at = c(y, 1), tick = FALSE, las = 1,
       labels = c(ifelse(included, paste0(two(or), " (", two(lci), ", ", two(uci), ")"), "excluded"),
                  paste0(two(pooled), " (", two(lower), ", ", two(upper), ")")))
}
if (!is.na(or_mh)) {
  forest(or_mh, mh_ci[1], mh_ci[2], wt_fixed,
         "Odds ratio meta-analysis plot [fixed effects]", "combined [fixed]")
  forest(or_re, re_ci[1], re_ci[2], wt_random,
         "Odds ratio meta-analysis plot [random effects]", "combined [random]")
}
par(mar = c(5, 4, 4, 2) + 0.1)

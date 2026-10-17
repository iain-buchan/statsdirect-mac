# StatsDirect recipe: one selected ROC chart and its chosen cutoff analysis.
# hand-edited: all selected series, comparison operators, confidence and weighting.
# data: positives... = P1, negatives... = A1
# settings: chart = chartSettings, cutoffs = rocCutoffs

if (!length(positives) || length(positives) != length(negatives))
  stop("Select one present and one absent column for every ROC series.")
roc_comparison <- as.integer(sd_chart_get("comparison", if (mean(positives[[length(positives)]], na.rm = TRUE) > mean(negatives[[length(negatives)]], na.rm = TRUE)) 1L else 3L))
if (length(roc_comparison) != 1L || !roc_comparison %in% 1:4) stop("Choose a valid ROC comparison operator.")
roc_confidence <- sd_chart_get("confidence", .95)
if (length(roc_confidence) != 1L || !is.finite(roc_confidence) || roc_confidence <= 0 || roc_confidence >= 1)
  stop("The ROC confidence level must lie between zero and one.")
roc_weight <- sd_chart_get("weight", 1)
if (length(roc_weight) != 1L || !is.finite(roc_weight) || roc_weight <= 0) roc_weight <- 1
roc_show_cutoff <- isTRUE(sd_chart_get("showOptimumCutOff", TRUE))
roc_labels <- sd_chart_strings(sd_chart_get("seriesTitles", names(positives)))
if (length(roc_labels) != length(positives)) roc_labels <- paste("Series", seq_along(positives))
roc_saved_cutoffs <- if (is.null(cutoffs)) list() else cutoffs
roc_compare <- function(value, cutoff, comparison) switch(as.character(comparison),
  `1` = value >= cutoff, `2` = value > cutoff, `3` = value <= cutoff, `4` = value < cutoff)
roc_interval <- function(success, total) {
  if (!total) return(c(estimate = NA_real_, lower = NA_real_, upper = NA_real_))
  ci <- binom.test(success, total, conf.level = roc_confidence)$conf.int
  c(estimate = success / total, lower = ci[1L], upper = ci[2L])
}
roc_series <- lapply(seq_along(positives), function(i) {
  present <- positives[[i]][is.finite(positives[[i]])]
  absent <- negatives[[i]][is.finite(negatives[[i]])]
  m <- length(present); n <- length(absent)
  if (!m || !n) stop("Each ROC series needs finite observations in both groups.")
  saved <- if (length(roc_saved_cutoffs) >= i) roc_saved_cutoffs[[i]] else list()
  comparison <- if (length(saved$comparison)) as.integer(saved$comparison) else roc_comparison
  weight <- if (length(saved$weight)) as.double(saved$weight) else roc_weight
  if (!is.finite(weight) || weight <= 0) weight <- 1
  cuts <- sort(c(present, absent))
  sens <- vapply(cuts, function(cut) mean(roc_compare(present, cut, comparison)), 0.0)
  spec <- vapply(cuts, function(cut) mean(!roc_compare(absent, cut, comparison)), 0.0)
  best <- which.max(weight * sens + spec)
  cut <- if (length(saved$cutoff) && is.finite(saved$cutoff)) saved$cutoff else cuts[best]
  a <- sum(roc_compare(present, cut, comparison)); b <- sum(roc_compare(absent, cut, comparison))
  cc <- m - a; d <- n - b
  beats <- outer(present, absent, function(p, q) (p > q) + (p == q) / 2)
  if (comparison %in% c(3L, 4L)) beats <- 1 - beats
  theta <- mean(beats)
  se <- if (m > 1L && n > 1L) sqrt(var(rowMeans(beats)) / m + var(colMeans(beats)) / n) else NA_real_
  ci <- pmin(1, pmax(0, theta + c(-1, 1) * qnorm((1 + roc_confidence) / 2) * se))
  order <- if (comparison %in% c(1L, 2L)) rev(seq_along(cuts)) else seq_along(cuts)
  xx <- c(0, (1 - spec)[order], 1); yy <- c(0, sens[order], 1)
  auc <- sum(diff(xx) * (head(yy, -1L) + tail(yy, -1L)) / 2)
  list(present = present, absent = absent, cuts = cuts, sensitivity = sens, specificity = spec,
       auc = auc, theta = theta, se = se, confidence = ci, comparison = comparison, weight = weight,
       cutoff = cut, optimum = cuts[best], a = a, b = b, c = cc, d = d,
       proportions = rbind(sensitivity = roc_interval(a, m), specificity = roc_interval(d, n),
         positive_predictive_value = roc_interval(a, a + b), negative_predictive_value = roc_interval(d, cc + d)))
})
roc_before_pty <- par("pty")
par(pty = "s") # The native ROC plotting area is square.
sd_chart_frame(c(0, 1), c(0, 1), "ROC plot", "1-Specificity", "Sensitivity", legend_labels = roc_labels)
abline(0, 1)
for (i in seq_along(roc_series)) {
  s <- roc_series[[i]]; marker <- sd_chart_marker(i)
  lines(1 - s$specificity, s$sensitivity, col = marker$lineColor, lwd = marker$lwd, lty = marker$lty)
  sd_chart_points(1 - s$specificity, s$sensitivity, marker)
  cat(roc_labels[i], ": AUC =", s$auc, "; rank estimate =", s$theta, "; DeLong SE =", s$se,
      ";", 100 * roc_confidence, "% CI =", s$confidence[1L], "to", s$confidence[2L], "\n")
  if (roc_show_cutoff) {
    cutoff_marker <- sd_chart_marker(length(roc_series) + i)
    sd_chart_points(s$b / length(s$absent), s$a / length(s$present), cutoff_marker)
    cat("Selected cutoff =", s$cutoff, "; weight =", s$weight, "; a =", s$a, "; b =", s$b, "; c =", s$c, "; d =", s$d, "\n")
    print(s$proportions)
  }
}
sd_chart_legend(roc_labels)
sd_chart_finish()
par(pty = roc_before_pty)

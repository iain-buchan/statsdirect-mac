# StatsDirect recipe: the survival and cumulative hazard plots of a Cox regression, drawn after the regression above.
# settings: use_tics = use-tics, use_markers = use-markers, split = group
# hand-edited: the plots StatsDirect draws for this follow-on; the fit and its data are the regression's, the choices are the follow-on's

# The survival and cumulative hazard plots, as StatsDirect draws them: the
# baseline curves (a subject whose predictors are all 0), split by the strata
# when the model has them, else by one binary predictor (that predictor at each
# of its two values, the other predictors 0) or not at all, as the follow-on
# chose from the same list of choices; a split by a predictor adds the plot of
# -log(-log(survival)) against log(time), in which the two groups run side by
# side if their hazards are proportional. Tics mark censored times and markers
# every observed time when the follow-on asked for them.
predictor_frame <- as.data.frame(predictors)
binary <- names(predictor_frame)[vapply(predictor_frame, function(v) length(unique(v[!is.na(v)])) == 2, logical(1))]
split_choices <- if (!is.null(stratum)) "Strata" else c(binary, "None")
split_by <- if (is.null(split)) split_choices[1] else split_choices[which(unlist(split))[1]]
if (is.na(split_by)) split_by <- split_choices[1]
if (is.null(use_tics)) use_tics <- FALSE
if (is.null(use_markers)) use_markers <- FALSE
baseline_rows <- as.data.frame(lapply(predictor_frame, function(v) 0))
grouped <- split_by != "Strata" && split_by != "None"
if (grouped) {
  group_values <- sort(unique(predictor_frame[[split_by]][!is.na(predictor_frame[[split_by]])]))
  baseline_rows <- baseline_rows[rep(1, 2), , drop = FALSE]
  baseline_rows[[split_by]] <- group_values
}
curves <- survfit(fit, newdata = baseline_rows, stype = 1, ctype = 1)
curve_count <- if (grouped) 2L else max(1L, length(curves$strata))
curve_labels <- if (grouped) paste0(substr(split_by, 1, 20), "=", group_values) else if (!is.null(stratum)) paste("Stratum", seq_len(curve_count)) else NULL
scale_suffix <- if (grouped) "(individual)" else "(baseline)"
cox_plot <- function(fun, main, ylab, ylim = NULL) {
  arguments <- list(curves, col = seq_len(curve_count), lty = 1, mark.time = use_tics, conf.int = FALSE,
                    xlab = "Time", ylab = paste(ylab, scale_suffix), main = main)
  if (!is.null(fun)) arguments$fun <- fun
  if (!is.null(ylim)) arguments$ylim <- ylim
  do.call(plot, arguments)
  if (use_markers) {
    s <- summary(curves, censored = FALSE)
    value <- if (identical(fun, "cumhaz")) s$cumhaz else s$surv
    if (curve_count > 1L) {
      member <- if (grouped) rep(seq_len(curve_count), each = length(s$time)) else as.integer(s$strata)
      if (grouped) { value <- as.vector(value); time <- rep(s$time, times = curve_count) } else time <- s$time
      points(time, value, col = member, pch = member)
    } else points(s$time, value, pch = 1)
  }
  if (!is.null(curve_labels)) legend("topright", legend = curve_labels, col = seq_len(curve_count), lty = 1, bty = "n")
}
cox_plot(NULL, "Survival Plot (Cox regression)", "Survival Probability", ylim = c(0, 1))
cox_plot("cumhaz", "Hazard Plot (Cox regression)", "Cumulative Hazard")
if (grouped) {
  s <- summary(curves, censored = FALSE)
  loglog <- -log(-log(s$surv))
  keep <- is.finite(loglog)   # not finite at survival 0 or 1: the point is left out, as StatsDirect leaves it
  plot(range(log(s$time[rowSums(keep) > 0])), range(loglog[keep]), type = "n",
       xlab = "log(Time)", ylab = "-log(-log(Survival))", main = "Log-log plot (parallel groups if hazards proportional)")
  for (g in seq_len(curve_count)) {
    ok <- keep[, g]
    lines(log(s$time[ok]), loglog[ok, g], col = g, type = "b", pch = g)
  }
  legend("topright", legend = curve_labels, col = seq_len(curve_count), lty = 1, pch = seq_len(curve_count), bty = "n")
}

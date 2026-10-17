# StatsDirect recipe: the selected survival proportions and confidence limits.
# hand-edited: replay the supplied curves, rather than fitting a different survival model.
# data: times... = xdatNew, events... = cdatNew, proportions... = ydatNew, lowers... = ydatlNew, uppers... = ydatuNew
# settings: chart = chartSettings

survival_curves <- sd_chart_get("curves", NULL)
survival_numbers <- function(x) {
  if (!is.list(x)) return(as.numeric(x))
  vapply(x, function(value) if (length(value)) as.numeric(value) else NA_real_, 0.0)
}
if (is.null(survival_curves)) {
  if (!length(times) || length(times) != length(proportions) || length(times) != length(events))
    stop("Select times, events and survival proportions for each group.")
  shapes <- sd_chart_get("curveShapes", list())
  lower_index <- upper_index <- 0L
  survival_curves <- lapply(seq_along(times), function(i) {
    shape <- if (length(shapes) >= i) shapes[[i]] else list(hasLower = length(lowers) == length(times), hasUpper = length(uppers) == length(times))
    lower <- upper <- NULL
    if (isTRUE(shape$hasLower)) { lower_index <<- lower_index + 1L; lower <- lowers[[if (length(lowers) == length(times)) i else lower_index]] }
    if (isTRUE(shape$hasUpper)) { upper_index <<- upper_index + 1L; upper <- uppers[[if (length(uppers) == length(times)) i else upper_index]] }
    list(x = times[[i]], y = proportions[[i]], event = events[[i]], lower = lower, upper = upper)
  })
}
survival_curves <- lapply(survival_curves, function(s) {
  s <- lapply(s[c("x", "y", "lower", "upper", "event")], survival_numbers)
  if (length(s$x) != length(s$y) || length(s$x) != length(s$event))
    stop("Each survival group must have equally long time, event and proportion columns.")
  s
})
survival_labels <- sd_chart_strings(sd_chart_get("seriesTitles", seq_along(survival_curves)))
if (length(survival_labels) != length(survival_curves)) survival_labels <- as.character(seq_along(survival_curves))
survival_ci_groups <- vapply(survival_curves, function(s) length(s$lower) == length(s$x) && length(s$upper) == length(s$x), logical(1))
survival_ci <- any(survival_ci_groups)
survival_event_markers <- isTRUE(sd_chart_get("showEventMarkers", TRUE))
survival_censor_tics <- isTRUE(sd_chart_get("showCensorshipTics", FALSE))
survival_coloured_ci <- isTRUE(sd_chart_get("useSeriesColourForConfidenceIntervals", FALSE))
survival_range <- range(unlist(lapply(survival_curves, function(s) s$x[is.finite(s$x) & is.finite(s$y) & is.finite(s$event) & s$event != -1])), finite = TRUE)
if (!all(is.finite(survival_range))) stop("The selected survival curves contain no complete observations.")
survival_limits <- sd_chart_frame(survival_range, c(0, 1), "Survival plot", "Times", "Survival proportion",
                                  legend_labels = survival_labels)
survival_ci_marker <- sd_chart_marker(length(survival_curves) + 1L)
for (i in seq_along(survival_curves)) {
  s <- survival_curves[[i]]; marker <- sd_chart_marker(i)
  valid <- is.finite(s$x) & is.finite(s$y) & is.finite(s$event) & s$event != -1
  x <- s$x[valid]; y <- s$y[valid]; event <- s$event[valid]
  # The native chart starts at S=1 at the left axis edge and preserves the supplied row order.
  if (length(x)) {
    previous_x <- c(survival_limits$xlim[1L], head(x, -1L)); previous_y <- c(1, head(y, -1L))
    segments(previous_x, previous_y, x, previous_y, col = marker$lineColor, lwd = marker$lwd, lty = marker$lty)
    segments(x, previous_y, x, y, col = marker$lineColor, lwd = marker$lwd, lty = marker$lty)
    if (survival_event_markers) sd_chart_points(x[event > 0], y[event > 0], marker)
    if (survival_censor_tics && any(event == 0)) {
      # A physical seven-point tick remains the same size on every axis scale.
      tick_y <- grconvertY(grconvertY(y[event == 0], "user", "inches") + 7 / 72, "inches", "user")
      segments(x[event == 0], y[event == 0], x[event == 0], tick_y, col = marker$lineColor, lwd = marker$lwd)
    }
    if (survival_ci_groups[i]) {
      keep <- valid & s$event > 0 & is.finite(s$lower) & is.finite(s$upper)
      segments(s$x[keep], s$lower[keep], s$x[keep], s$upper[keep],
               col = if (survival_coloured_ci) marker$lineColor else survival_ci_marker$lineColor,
               lwd = survival_ci_marker$lwd, lty = survival_ci_marker$lty)
    }
  }
  cat(survival_labels[i], ":", length(x), "selected survival proportions\n")
}
sd_chart_legend(survival_labels)
sd_chart_finish()

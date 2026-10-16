# StatsDirect recipe: one selected chart of centres and lower/upper error limits.
# hand-edited: replay the selected chart data and final options instead of the help illustration.
# data: centres... = ydatNew, error_xs... = xdatNew, uppers... = ydatuNew, lowers... = ydatlNew
# settings: chart = chartSettings

if (!is.list(centres) || !length(centres) || length(centres) != length(error_xs) ||
    length(centres) != length(uppers) || length(centres) != length(lowers))
  stop("Select X, centre, lower-limit and upper-limit columns for every series.")
error_labels <- as.character(unlist(sd_chart_get("seriesTitles", names(centres)), use.names = FALSE))
if (length(error_labels) != length(centres)) error_labels <- names(centres)
if (is.null(error_labels)) error_labels <- paste("Series", seq_along(centres))
error_series <- lapply(seq_along(centres), function(i) {
  n <- c(length(error_xs[[i]]), length(centres[[i]]), length(lowers[[i]]), length(uppers[[i]]))
  if (length(unique(n)) != 1L) stop("The four columns in each error-bar series must have the same number of rows.")
  ok <- is.finite(error_xs[[i]]) & is.finite(centres[[i]]) &
    is.finite(lowers[[i]]) & is.finite(uppers[[i]])
  list(x = error_xs[[i]][ok], y = centres[[i]][ok],
       lower = lowers[[i]][ok], upper = uppers[[i]][ok], label = error_labels[i])
})
if (!any(vapply(error_series, function(s) length(s$x) > 0L, logical(1))))
  stop("The selected error-bar series contain no complete numeric rows.")
error_legend <- isTRUE(sd_chart_get("showLegend", FALSE)) && length(error_series) > 1L
sd_chart_frame(range(unlist(lapply(error_series, function(s) s$x)), finite = TRUE),
               range(unlist(lapply(error_series, function(s) c(s$lower, s$y, s$upper))), finite = TRUE),
               default_title = "Error bar plot", xlab = names(error_xs)[1L], ylab = names(centres)[1L],
               legend_labels = if (error_legend) error_labels else NULL)
error_used <- list()
error_offsets <- isTRUE(sd_chart_get("checkForOffsets", TRUE))
error_join <- isTRUE(sd_chart_get("joinMarkersWithLines", FALSE))
error_markers <- isTRUE(sd_chart_get("plotMarkers", TRUE))
for (i in seq_along(error_series)) {
  s <- error_series[[i]]
  m <- sd_chart_marker(i)
  safe_x <- s$x
  # As in the native chart, avoid overlapping bars in device coordinates.
  # This is a line width plus a gap, never one unit of the selected data.
  for (j in seq_along(safe_x)) {
    if (error_offsets) repeat {
      pixel <- grconvertX(safe_x[j], from = "user", to = "device")
      key <- as.character(round(pixel))
      prior <- error_used[[key]]
      overlap <- !is.null(prior) && any(s$lower[j] < prior[, 2L] & s$upper[j] > prior[, 1L])
      if (!overlap) {
        error_used[[key]] <- rbind(prior, c(s$lower[j], s$upper[j]))
        break
      }
      safe_x[j] <- grconvertX(pixel + max(1, m$lwd) + 1, from = "device", to = "user")
    }
  }
  pixels <- grconvertX(safe_x, from = "user", to = "device")
  cap_left <- grconvertX(pixels - 10, from = "device", to = "user")
  cap_right <- grconvertX(pixels + 10, from = "device", to = "user")
  segments(safe_x, s$lower, safe_x, s$upper, col = m$col, lwd = m$lwd)
  segments(cap_left, s$lower, cap_right, s$lower, col = m$col, lwd = m$lwd)
  segments(cap_left, s$upper, cap_right, s$upper, col = m$col, lwd = m$lwd)
  if (error_markers)
    sd_chart_points(safe_x, s$y, m)
  # Error-bar connecting lines follow the selected row order, including safe offsets.
  if (error_join && length(safe_x))
    lines(c(s$x[1L], safe_x), c(s$y[1L], s$y),
          col = m$lineColor, lwd = m$lwd, lty = m$lty)
  error_series[[i]]$plot_x <- safe_x
  cat(s$label, ":", length(s$x), "complete error bars\n")
  for (j in seq_along(s$x))
    cat(format(s$x[j], digits = 15), format(s$y[j], digits = 15),
        format(s$lower[j], digits = 15), "to", format(s$upper[j], digits = 15), "\n")
}
if (error_legend)
  sd_chart_legend(error_labels)
sd_chart_finish()

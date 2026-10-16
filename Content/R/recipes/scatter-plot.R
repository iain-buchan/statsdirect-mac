# StatsDirect recipe: one selected XY chart with the saved chart options.
# hand-edited: replay the selected chart data and final options instead of the help illustration.
# data: ys... = Ynew, xs... = Xnew
# settings: chart = chartSettings

if (!is.list(xs) || !is.list(ys) || !length(xs) || length(xs) != length(ys))
  stop("Select one X column and one Y column for each plotted series.")
xy_labels <- as.character(unlist(sd_chart_get("seriesTitles", names(xs)), use.names = FALSE))
if (length(xy_labels) != length(xs)) xy_labels <- names(xs)
if (is.null(xy_labels)) xy_labels <- paste("Series", seq_along(xs))
xy_series <- lapply(seq_along(xs), function(i) {
  if (length(xs[[i]]) != length(ys[[i]]))
    stop("The X and Y columns in each series must have the same number of rows.")
  ok <- is.finite(xs[[i]]) & is.finite(ys[[i]])
  x <- xs[[i]][ok]
  y <- ys[[i]][ok]
  # Native connecting lines sort by X, then descending Y for equal X.
  o <- order(x, -y)
  list(x = x[o], y = y[o], label = xy_labels[i])
})
if (!any(vapply(xy_series, function(s) length(s$x) > 0L, logical(1))))
  stop("The selected XY series contain no complete numeric pairs.")
xy_join <- isTRUE(sd_chart_get("joinMarkersWithLines", FALSE))
xy_markers <- isTRUE(sd_chart_get("plotMarkers", TRUE))
xy_legend <- isTRUE(sd_chart_get("showLegend", FALSE)) && length(xy_series) > 1L
sd_chart_frame(range(unlist(lapply(xy_series, function(s) s$x)), finite = TRUE),
               range(unlist(lapply(xy_series, function(s) s$y)), finite = TRUE),
               default_title = "Scatter plot", xlab = names(xs)[1L], ylab = names(ys)[1L],
               legend_labels = if (xy_legend) xy_labels else NULL)
for (i in seq_along(xy_series)) {
  s <- xy_series[[i]]
  m <- sd_chart_marker(i)
  if (xy_join && length(s$x) > 1L)
    lines(s$x, s$y, col = m$lineColor, lwd = m$lwd, lty = m$lty)
  if (xy_markers && length(s$x)) {
    # Native scatter markers are drawn once at each distinct position.
    keep <- !duplicated(data.frame(x = s$x, y = s$y))
    sd_chart_points(s$x[keep], s$y[keep], m)
  }
  if (length(s$x))
    cat(s$label, ":", length(s$x), "complete pairs; X", min(s$x), "to", max(s$x),
        "; Y", min(s$y), "to", max(s$y), "\n")
  else cat(s$label, ": no complete pairs\n")
}
if (xy_legend)
  sd_chart_legend(xy_labels)
sd_chart_finish()

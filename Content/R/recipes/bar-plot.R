# StatsDirect recipe: one bar chart from the selected values and final chart options.
# data: group = labels, series... = values
# settings: chart = chartSettings
# hand-edited: chart settings and selected data replace the help's teaching examples.

bar_original_chart <- chart
if (!length(series) || length(unique(lengths(series))) != 1L)
  stop("Bar series must have the same positive number of observations.")
bar_values <- do.call(rbind, series)
storage.mode(bar_values) <- "double"
if (!ncol(bar_values) || any(!is.finite(bar_values) & !is.na(bar_values)))
  stop("Bar values must be finite numbers or missing values.")
bar_labels <- sd_chart_strings(sd_chart_get("seriesTitles", group))
if (length(bar_labels) != ncol(bar_values)) bar_labels <- group
if (length(bar_labels) != ncol(bar_values)) bar_labels <- as.character(seq_len(ncol(bar_values)))
colnames(bar_values) <- bar_labels
bar_stacked <- isTRUE(sd_chart_get("stacked", FALSE))
bar_percent <- bar_stacked && isTRUE(sd_chart_get("stacked100Percent", FALSE))
bar_rotated <- bar_stacked && isTRUE(sd_chart_get("rotateWhenStacked", TRUE))
if (bar_rotated) bar_values <- t(bar_values)
if (bar_percent) {
  totals <- colSums(bar_values, na.rm = TRUE)
  bar_values <- sweep(bar_values, 2L, totals, "/") * 100
  bar_values[, totals <= 0] <- NA_real_
}
bar_horizontal <- isTRUE(sd_chart_get("horizontal", FALSE))
bar_width <- sd_chart_get("maxBarWidth", if (bar_stacked) 0.6 else 0.6 / nrow(bar_values))
bar_width <- min(if (bar_stacked) 1 else 1 / nrow(bar_values), max(0.01, bar_width))
bar_height <- if (bar_stacked) colSums(bar_values, na.rm = TRUE) else bar_values
value_limits <- range(c(0, bar_height), finite = TRUE)
if (diff(value_limits) == 0) value_limits <- c(0, 1)
if (bar_percent) value_limits <- c(0, 100)
category_limits <- c(0, ncol(bar_values))
if (bar_horizontal && is.list(chart)) {
  old_axis <- chart[["x"]]; chart$x <- chart[["y"]]; chart$y <- old_axis
  old_title <- chart$xTitle; chart$xTitle <- chart$yTitle; chart$yTitle <- old_title
}
bar_legend_labels <- if (bar_stacked ||
  (isTRUE(sd_chart_get("showLegend", nrow(bar_values) > 1L)) && nrow(bar_values) > 1L)) rownames(bar_values) else NULL
if (bar_stacked && is.list(chart)) chart$showLegend <- TRUE
sd_chart_frame(if (bar_horizontal) value_limits else category_limits,
               if (bar_horizontal) category_limits else value_limits,
               default_title = "Bar chart", x_axis = bar_horizontal, y_axis = !bar_horizontal,
               category_labels = colnames(bar_values), legend_labels = bar_legend_labels)
centres <- seq_len(ncol(bar_values)) - 0.5
if (bar_horizontal) centres <- rev(centres)
sd_chart_axis(if (bar_horizontal) 2L else 1L, at = centres,
              labels = colnames(bar_values), tick = FALSE)
bar_segments <- vector("list", nrow(bar_values))
for (i in seq_len(nrow(bar_values))) {
  marker <- sd_chart_marker(i)
  bottom <- if (bar_stacked && i > 1L)
    colSums(bar_values[seq_len(i - 1L), , drop = FALSE], na.rm = TRUE) else rep(0, ncol(bar_values))
  position <- if (bar_horizontal) nrow(bar_values) - i else i - 1L
  low <- centres - if (bar_stacked) bar_width / 2 else bar_width * nrow(bar_values) / 2 - position * bar_width
  high <- low + bar_width
  top <- bottom + bar_values[i, ]
  bar_segments[[i]] <- list(lower = bottom, upper = top, categoryLower = low, categoryUpper = high)
  # Bar fills are independent of whether point markers are hollow: colour
  # charts use solid fills; monochrome charts use the selected fill pattern.
  raw_markers <- sd_chart_get("markers", list())
  raw_marker <- if (length(raw_markers)) raw_markers[[1L + (i - 1L) %% length(raw_markers)]] else list()
  fill_style <- if (isTRUE(sd_chart_get("useColour", TRUE))) 1L else raw_marker$fillStyle
  if (length(fill_style) != 1L || !fill_style %in% 0:4) fill_style <- 0L
  fill <- if (fill_style == 0L) NA else marker$col
  density <- if (fill_style %in% 2:4) 16 else NULL
  angle <- if (fill_style == 3L) 135 else 45
  if (bar_horizontal)
    rect(bottom, low, top, high, col = fill, border = marker$lineColor, lwd = marker$lwd, lty = marker$lty,
         density = density, angle = angle)
  else rect(low, bottom, high, top, col = fill, border = marker$lineColor, lwd = marker$lwd, lty = marker$lty,
            density = density, angle = angle)
  if (fill_style == 4L) {
    if (bar_horizontal) rect(bottom, low, top, high, col = fill, border = NA, density = 16, angle = 135)
    else rect(low, bottom, high, top, col = fill, border = NA, density = 16, angle = 135)
  }
}
sd_chart_legend(bar_legend_labels, fill = TRUE)
sd_chart_finish()
chart <- bar_original_chart

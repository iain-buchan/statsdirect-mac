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
bar_height <- if (bar_stacked) colSums(bar_values, na.rm = TRUE) else bar_values
value_limits <- range(c(0, bar_height), finite = TRUE)
if (diff(value_limits) == 0) value_limits <- c(0, 1)
if (bar_percent) value_limits <- c(0, 100)
# Keep missing entries in the result matrix, but draw them as empty segments.
bar_drawing <- bar_values
bar_drawing[is.na(bar_drawing)] <- 0
if (bar_horizontal) bar_drawing <- bar_drawing[, rev(seq_len(ncol(bar_drawing))), drop = FALSE]
bar_positions <- barplot(bar_drawing, beside = !bar_stacked, plot = FALSE)
category_limits <- range(bar_positions) + c(-0.6, 0.6)
if (bar_horizontal && is.list(chart)) {
  old_axis <- chart[["x"]]; chart$x <- chart[["y"]]; chart$y <- old_axis
  old_title <- chart$xTitle; chart$xTitle <- chart$yTitle; chart$yTitle <- old_title
}
bar_legend_labels <- rownames(bar_values)
if (bar_stacked && is.list(chart)) chart$showLegend <- TRUE
sd_chart_frame(if (bar_horizontal) value_limits else category_limits,
               if (bar_horizontal) category_limits else value_limits,
               default_title = "Bar chart", x_axis = bar_horizontal, y_axis = !bar_horizontal,
               category_labels = colnames(bar_values), legend_labels = bar_legend_labels)
bar_markers <- lapply(seq_len(nrow(bar_values)), sd_chart_marker)
bar_colours <- if (isTRUE(sd_chart_get("useColour", TRUE)))
  vapply(bar_markers, function(m) m$col, character(1)) else gray.colors(nrow(bar_values), start = .25, end = .85)
for (i in seq_along(bar_markers)) bar_markers[[i]]$col <- bar_colours[i]
barplot(bar_drawing, beside = !bar_stacked, horiz = bar_horizontal, add = TRUE,
        axes = FALSE, axisnames = FALSE, col = bar_colours, border = bar_colours)
sd_chart_axis(if (bar_horizontal) 2L else 1L,
              at = if (bar_stacked) as.numeric(bar_positions) else colMeans(bar_positions),
              labels = colnames(bar_drawing), tick = FALSE)
sd_chart_legend(bar_legend_labels, markers = bar_markers, fill = TRUE)
sd_chart_finish()
chart <- bar_original_chart

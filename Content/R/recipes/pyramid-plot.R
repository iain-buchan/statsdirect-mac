# StatsDirect recipe: one population pyramid for the selected counts and labels.
# hand-edited: replay the selected chart data and final options instead of the help illustration.
# data: males = male, females = female, band = labels
# settings: chart = chartSettings

if (is.null(males) || any(males < 0, na.rm = TRUE))
  stop("Select non-negative population counts.")
pyramid_totals <- is.null(females)
if (!pyramid_totals && (length(females) != length(males) || any(females < 0, na.rm = TRUE)))
  stop("The two population columns must have matching row counts and non-negative counts.")
pyramid_ok <- is.finite(males) & if (pyramid_totals) TRUE else is.finite(females)
pyramid_rows <- which(pyramid_ok)
pyramid_males <- males[pyramid_ok] / if (pyramid_totals) 2 else 1
pyramid_females <- if (pyramid_totals) pyramid_males else females[pyramid_ok]
pyramid_labels <- rep("", length(pyramid_rows))
if (!is.null(band))
  for (i in seq_along(pyramid_rows)) {
    row <- pyramid_rows[i]
    label <- if (row <= length(band)) as.character(band[row]) else NA_character_
    pyramid_labels[i] <- if (is.na(label) || !nzchar(trimws(label))) paste("group", row) else substr(label, 1L, 50L)
  }
# Match the native plot's scale clamp, including the raw count in totals mode.
pyramid_raw_maximum <- max(c(0, males[is.finite(males)], if (!pyramid_totals) females[is.finite(females)]))
pyramid_default_scale <- if (pyramid_raw_maximum > 0) max(pretty(c(0, pyramid_raw_maximum))) else 1
pyramid_selected_scale <- sd_chart_get("scaleMaximum", pyramid_default_scale)
if (length(pyramid_selected_scale) != 1L || !is.finite(pyramid_selected_scale)) pyramid_selected_scale <- pyramid_default_scale
pyramid_scale <- max(1, pyramid_selected_scale, pyramid_raw_maximum)
pyramid_n <- length(pyramid_rows)
sd_chart_frame(c(-pyramid_scale, pyramid_scale), c(0, max(1L, pyramid_n)),
               default_title = "Population pyramid", x_axis = FALSE, y_axis = FALSE,
               category_labels = pyramid_labels)
pyramid_positions <- pyramid_n - seq_len(pyramid_n) + 0.5
pyramid_font <- sd_chart_font("axisLabelFont", 10)
if (pyramid_n && !is.null(band))
  text(par("usr")[1L], pyramid_positions, labels = pyramid_labels, pos = 2, xpd = NA,
       family = pyramid_font$family, cex = pyramid_font$size / par("ps"), font = pyramid_font$font)
pyramid_fill <- function(index) {
  marker <- sd_chart_marker(index)
  raw_markers <- sd_chart_get("markers", list())
  raw <- if (length(raw_markers)) raw_markers[[1L + (index - 1L) %% length(raw_markers)]] else list()
  style <- if (isTRUE(sd_chart_get("useColour", TRUE))) 1L else raw$fillStyle
  if (length(style) != 1L || !style %in% 0:4) style <- 0L
  list(col = if (style == 0L) NA else marker$col,
       density = if (style %in% 2:4) 16 else NULL, angle = if (style == 3L) 135 else 45, cross = style == 4L)
}
pyramid_rectangle <- function(left, right, style) {
  rect(left, pyramid_positions - 0.5, right, pyramid_positions + 0.5,
       col = style$col, border = "black", density = style$density, angle = style$angle)
  if (style$cross)
    rect(left, pyramid_positions - 0.5, right, pyramid_positions + 0.5,
         col = style$col, border = NA, density = 16, angle = 135)
}
if (pyramid_n) {
  if (pyramid_totals) pyramid_rectangle(-pyramid_males, pyramid_females, pyramid_fill(1L)) else {
    pyramid_rectangle(-pyramid_males, rep(0, pyramid_n), pyramid_fill(1L))
    pyramid_rectangle(rep(0, pyramid_n), pyramid_females, pyramid_fill(2L))
    segments(0, 0, 0, pyramid_n)
  }
}
if (!pyramid_totals)
  mtext(c("male", "female"), side = 1, at = c(-pyramid_scale, pyramid_scale) / 2, line = 0.5,
        family = pyramid_font$family, cex = pyramid_font$size / par("ps"), font = pyramid_font$font)
mtext(paste("Scale maximum =", format(pyramid_scale, digits = 15)), side = 1, line = 2.5, adj = 0,
      family = pyramid_font$family, cex = pyramid_font$size / par("ps"), font = pyramid_font$font)
cat("Scale maximum =", pyramid_scale, "\n")
print(data.frame(label = pyramid_labels, left = pyramid_males, right = pyramid_females))
sd_chart_finish()

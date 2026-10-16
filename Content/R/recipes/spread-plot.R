# StatsDirect recipe: one spread chart using the selected data, orientation and labels.
# data: groups... = data
# settings: chart = chartSettings
# hand-edited: stack nearby observations on the current drawing device, without teaching plots.

spread_original_chart <- chart
if (!length(groups)) stop("Select at least one series for the spread plot.")
groups <- lapply(groups, function(x) {
  x <- sort(x[!is.na(x)])
  if (!length(x) || any(!is.finite(x))) stop("Spread series need finite numeric observations.")
  x
})
spread_horizontal <- isTRUE(sd_chart_get("horizontal", TRUE))
spread_labels <- sd_chart_strings(sd_chart_get("seriesTitles", names(groups)))
if (length(spread_labels) != length(groups)) spread_labels <- names(groups)
if (is.null(spread_labels)) spread_labels <- paste("Series", seq_along(groups))
spread_range <- range(unlist(groups))
if (diff(spread_range) == 0) spread_range <- spread_range + c(-1, 1)
if (!spread_horizontal && is.list(chart)) {
  old_axis <- chart[["x"]]; chart$x <- chart[["y"]]; chart$y <- old_axis
  chart$yTitle <- chart$xTitle; chart$xTitle <- ""
}
k <- length(groups)
sd_chart_frame(if (spread_horizontal) spread_range else c(0, k),
               if (spread_horizontal) c(0, k) else spread_range, "Spread plot",
               x_axis = spread_horizontal, y_axis = !spread_horizontal,
               category_labels = spread_labels)
centres <- if (spread_horizontal) k - seq_len(k) + 0.5 else seq_len(k) - 0.5
sd_chart_axis(if (spread_horizontal) 2L else 1L, at = centres, labels = spread_labels,
              tick = FALSE)
marker <- sd_chart_marker(1L)
# Native stacks use a two-marker-size tolerance on the value axis. Derive it
# from this device's actual plot width/height, so resizing retains that rule.
pin <- par("pin"); usr <- par("usr")
axis_inches <- pin[if (spread_horizontal) 1L else 2L]
axis_span <- diff(usr[if (spread_horizontal) 1:2 else 3:4])
diameter_inches <- marker$size / 144  # native canvas units: two units per typographic point
spread_tolerance <- axis_span * (2 * diameter_inches) / axis_inches
spread_stack <- function(x) {
  at <- numeric(); count <- integer(); i <- 1L
  while (i <= length(x)) {
    j <- i
    while (j < length(x) && x[j + 1L] - x[i] <= spread_tolerance) j <- j + 1L
    at <- c(at, x[i]); count <- c(count, j - i + 1L); i <- j + 1L
  }
  data.frame(at = at, count = count)
}
spread_stacks <- lapply(groups, spread_stack)
for (g in seq_along(groups)) {
  stack <- spread_stacks[[g]]
  category_inches <- pin[if (spread_horizontal) 2L else 1L] / k
  increment <- 2 * diameter_inches / category_inches
  # Native compression uses the widest moving window, including windows that
  # start inside a drawn stack, rather than just the drawn columns' counts.
  max_count <- max(findInterval(groups[[g]] + spread_tolerance, groups[[g]]) - seq_along(groups[[g]]) + 1L)
  increment <- min(increment, max(0, 1 - 2 * diameter_inches / category_inches) / max_count)
  for (i in seq_len(nrow(stack))) {
    offset <- centres[g] + increment * (seq_len(stack$count[i]) - (stack$count[i] + 1) / 2)
    if (spread_horizontal) sd_chart_points(rep(stack$at[i], stack$count[i]), offset, marker)
    else sd_chart_points(offset, rep(stack$at[i], stack$count[i]), marker)
  }
}
sd_chart_finish()
chart <- spread_original_chart

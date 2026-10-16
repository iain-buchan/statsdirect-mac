# StatsDirect recipe: selected histograms on one page, using their recorded bins.
# data: series... = data
# settings: chart = chartSettings
# hand-edited: no unrequested log transformation or help-example labels.

sd_histogram_doane <- function(x) {
  n <- length(x)
  skew <- if (n <= 3L || all(x == x[1L])) 0 else
    abs(mean((x - mean(x))^3) / mean((x - mean(x))^2)^1.5) /
      sqrt(6 * (n - 2) / ((n + 1) * (n + 3)))
  k <- max(1L, round(1 + log2(n) + log2(1 + skew)))
  if (min(x) == max(x)) c(min(x) - 1, max(x) + 1) else seq(min(x), max(x), length.out = k + 1L)
}
# StatsDirect assigns an observation on an upper edge to the lower bin, with
# a tolerance for computed edges, and saturates observations outside the limits.
sd_histogram_counts <- function(x, edges) {
  tolerance <- max(abs(diff(range(edges))) * 1e-9, max(abs(edges)) * 1e-15)
  interiors <- edges[-c(1L, length(edges))] + tolerance
  bins <- findInterval(x, interiors, left.open = TRUE) + 1L
  tabulate(bins, nbins = length(edges) - 1L)
}
sd_histogram_midpoint_labels <- function(mids, width) {
  choose <- function(error, most) {
    for (digits in 0:most)
      if (max(abs(round(mids, digits) - mids)) <= error) return(digits)
    -1L
  }
  digits <- choose(abs(width) * 1e-9, 4L)
  if (digits < 0L) digits <- choose(abs(width) / 40, 6L)
  if (digits < 0L) return(formatC(mids, digits = 3L, format = "g"))
  mids <- round(mids, digits)
  mids[abs(mids) < abs(width) * 1e-9] <- 0
  formatC(mids, digits = digits, format = "f")
}
if (!length(series)) stop("Select at least one series for the histogram.")
series <- lapply(series, function(x) {
  x <- x[!is.na(x)]
  if (!length(x) || any(!is.finite(x))) stop("Histogram series need finite numeric observations.")
  x
})
histogram_options <- sd_chart_get("histograms", list())
histogram_relative <- isTRUE(sd_chart_get("relativeFrequencies", FALSE))
histogram_overlay <- isTRUE(sd_chart_get("overlayNormalCurve", FALSE))
histograms <- vector("list", length(series))
names(histograms) <- names(series)
for (i in seq_along(series)) {
  h <- if (length(histogram_options) >= i) histogram_options[[i]] else list()
  edges <- suppressWarnings(as.numeric(unlist(h$edges)))
  if (length(edges) < 2L || any(!is.finite(edges)) || any(diff(edges) < 0))
    edges <- sd_histogram_doane(series[[i]])
  # Equal-valued observations need one visible bin, even if an older record
  # retained repeated zero-width edges.
  if (diff(range(edges)) == 0) edges <- c(edges[1L] - 1, edges[1L] + 1)
  counts <- sd_histogram_counts(series[[i]], edges)
  heights <- if (histogram_relative) counts / length(series[[i]]) else counts
  histograms[[i]] <- list(breaks = edges, counts = counts, mids = (head(edges, -1L) + tail(edges, -1L)) / 2,
                          heights = heights, n = length(series[[i]]))
}
histogram_original_chart <- chart
# Native multi-variable histograms extend the image height, retaining a full
# panel for every selected column. Size a fresh automatic R device the same
# way; an explicitly opened device remains under the user's control.
if (length(series) > 1L && dev.cur() == 1L) {
  device <- getOption("device")
  # dev.new() drops width/height when a wrapper declares only "...". Call
  # such wrappers directly so StatsDirect's output-file factory keeps both
  # the chosen filename and the requested panel dimensions.
  if (is.function(device) && "..." %in% names(formals(device)))
    device(width = 7, height = 7 * length(series))
  else dev.new(width = 7, height = 7 * length(series))
}
op <- par(no.readonly = TRUE)
if (length(series) > 1L) par(mfrow = c(length(series), 1L))
for (i in seq_along(series)) {
  h <- histograms[[i]]
  opts <- if (length(histogram_options) >= i) histogram_options[[i]] else list()
  name <- names(series)[i]
  if (is.na(name) || !nzchar(name)) name <- paste("Series", i)
  # Histogram titles belong to each panel rather than the generic chart title.
  chart <- histogram_original_chart
  if (is.list(chart)) {
    chart$title <- if (!is.null(opts$title)) opts$title else paste("Distribution of", name)
    chart$xTitle <- if (!is.null(opts$xTitle)) opts$xTitle else paste("Mid-points for", name)
    chart$yTitle <- if (!is.null(opts$yTitle)) opts$yTitle else if (histogram_relative) "Relative frequencies" else "Counts"
  }
  width <- diff(h$breaks)[1L]
  normal_curve <- histogram_overlay && length(series[[i]]) > 1L && sd(series[[i]]) > 0
  curve_multiplier <- if (histogram_relative) width else length(series[[i]]) * width
  ymax <- max(h$heights)
  if (normal_curve) ymax <- max(ymax, curve_multiplier * dnorm(mean(series[[i]]), mean(series[[i]]), sd(series[[i]])))
  xlimits <- if (isTRUE(sd_chart_get("poolVariablesForBins", FALSE)))
    range(unlist(lapply(histograms, `[[`, "breaks"))) else range(h$breaks)
  midpoint_axis <- identical(as.numeric(range(h$breaks)), as.numeric(xlimits))
  sd_chart_frame(xlimits, c(0, max(ymax, .Machine$double.eps)), paste("Distribution of", name),
                 paste("Mid-points for", name), if (histogram_relative) "Relative frequencies" else "Counts",
                 x_axis = !midpoint_axis)
  if (midpoint_axis) sd_chart_axis(1L, at = h$mids, labels = sd_histogram_midpoint_labels(h$mids, width))
  marker <- sd_chart_marker(i)
  rect(head(h$breaks, -1L), 0, tail(h$breaks, -1L), h$heights,
       col = NA, border = marker$col, lwd = marker$lwd)
  if (normal_curve) {
    xs <- seq(min(h$breaks), max(h$breaks), length.out = 401L)
    lines(xs, curve_multiplier * dnorm(xs, mean(series[[i]]), sd(series[[i]])), col = marker$col, lwd = marker$lwd)
  }
}
chart <- histogram_original_chart
sd_chart_finish()
par(op)

# Base-R chart options shared by the exported scripts. Edit chart below to change
# titles, limits, logarithmic/date axes, grid lines, colours or the legend.
# hand-edited: keep this small; statistical calculations belong in each recipe.
sd_chart_state <- new.env(parent = emptyenv())
sd_chart_get <- function(name, default = NULL) {
  if (is.list(chart) && !is.null(chart[[name]])) chart[[name]] else default
}
sd_chart_numbers <- function(x) as.numeric(unlist(x, use.names = FALSE))
sd_chart_strings <- function(x) as.character(unlist(x, use.names = FALSE))
sd_chart_lty <- function(style) {
  if (length(style) != 1L || is.na(style) || !style %in% 0:4) style <- 0L
  if (style == 4L) "311111" else style + 1L
}
# SVG supports Arial; the standard PDF device provides the portable sans family.
sd_chart_font <- function(prefix, size) list(
  family = if (names(dev.cur()) %in% c("pdf", "postscript")) "sans" else "Arial",
  size = if (prefix == "titleFont") 12 else if (prefix == "axisTitleFont") 10 else 9,
  font = 1L)
sd_chart_text <- function(x, width = 70L) vapply(as.character(x), function(label)
  paste(strwrap(label, width = width), collapse = "\n"), character(1), USE.NAMES = FALSE)
sd_chart_axis <- function(side, at = NULL, labels = TRUE, ...) {
  horizontal <- side %in% c(1L, 3L)
  settings <- sd_chart_get(if (horizontal) "x" else "y", list())
  limits <- par("usr")[if (horizontal) 1:2 else 3:4]
  logarithmic <- par(if (horizontal) "xlog" else "ylog")
  if (logarithmic) limits <- 10^limits
  if (is.null(at)) {
    interval <- settings$interval; first <- settings$firstTick
    if (length(interval) == 1L && is.finite(interval) && interval > 0 &&
        length(first) == 1L && is.finite(first)) {
      ends <- c(ceiling((limits[1] - first) / interval - 1e-10),
                floor((limits[2] - first) / interval + 1e-10))
      if (all(is.finite(ends)) && diff(ends) >= 0 && diff(ends) < 10000)
        at <- first + seq(ends[1], ends[2]) * interval
    } else if (identical(as.integer(settings$scale), 1L) && all(limits > 0)) {
      powers <- c(ceiling(log2(limits[1]) - 1e-10), floor(log2(limits[2]) + 1e-10))
      if (powers[2] >= powers[1]) at <- 2^seq(powers[1], powers[2])
    }
    if (is.null(at)) at <- axTicks(side)
  }
  if (isTRUE(settings$grid)) {
    if (horizontal) abline(v = at, col = "grey85", lty = sd_chart_lty(settings$gridStyle))
    else abline(h = at, col = "grey85", lty = sd_chart_lty(settings$gridStyle))
  }
  if (isTRUE(labels)) labels <- if (identical(as.integer(settings$scale), 3L))
    format(as.Date(at, origin = "1899-12-30")) else format(at, trim = TRUE, drop0trailing = TRUE)
  if (is.character(labels)) labels <- sd_chart_text(labels, 18L)
  label_lines <- if (is.character(labels)) max(1L, lengths(strsplit(labels, "\n", fixed = TRUE))) else 1L
  do.call(axis, modifyList(list(side = side, at = at, labels = labels, las = 1,
                               line = if (horizontal) .5 * (label_lines - 1L) else 0), list(...)))
  marker <- settings$marker
  if (length(marker) == 1L && is.finite(marker) && (!logarithmic || marker > 0)) {
    if (horizontal) abline(v = marker) else abline(h = marker)
  }
  invisible(at)
}
sd_chart_frame <- function(xlim, ylim, default_title = "", xlab = "", ylab = "", x_axis = TRUE, y_axis = TRUE,
                           category_labels = NULL, right_margin_inches = 0, legend_labels = NULL) {
  if (is.null(chart) && !isTRUE(sd_chart_state$warned)) {
    message("This saved run has no chart settings; using standard chart options.")
    sd_chart_state$warned <- TRUE
  }
  if (is.null(sd_chart_state$old)) sd_chart_state$old <- par(c("mar", "family", "cex", "cex.main", "cex.lab", "cex.axis", "font.main", "font.lab", "font.axis"))
  main <- sd_chart_text(sd_chart_get("title", default_title))
  xlab <- sd_chart_text(sd_chart_get("xTitle", xlab), 60L)
  ylab <- sd_chart_text(sd_chart_get("yTitle", ylab), 45L)
  lines <- function(x) max(1L, lengths(strsplit(x, "\n", fixed = TRUE)))
  category_lines <- if (!x_axis && length(category_labels)) lines(sd_chart_text(category_labels, 18L)) else 1L
  margins <- c(5 + .8 * (lines(xlab) + category_lines - 2),
               (if (!y_axis && length(category_labels)) 10 else 5) + .8 * (lines(ylab) - 1),
               4 + .8 * (lines(main) - 1), 2)
  if (length(legend_labels) && isTRUE(sd_chart_get("showLegend", length(legend_labels) > 1L)))
    margins[1] <- margins[1] + .65 * lines(sd_chart_text(legend_labels, 30L)) *
      ceiling(length(legend_labels) / if (length(legend_labels) > 3L) 2L else 1L) + 1
  font <- sd_chart_font("axisLabelFont", 9)
  par(family = font$family, cex = 1, cex.main = 12 / par("ps"), cex.lab = 10 / par("ps"),
      cex.axis = 9 / par("ps"), font.main = 1, font.lab = 1, font.axis = 1, mar = margins)
  if (right_margin_inches > 0) { margins <- par("mai"); margins[4] <- max(margins[4], right_margin_inches); par(mai = margins) }
  limits <- function(values, name, draw_axis) {
    settings <- sd_chart_get(name, list())
    value <- range(values, finite = TRUE)
    if (!all(is.finite(value))) stop("Select finite observations for this chart.")
    if (draw_axis && length(settings$minimum) == 1L && length(settings$maximum) == 1L &&
        is.finite(settings$minimum) && is.finite(settings$maximum) && settings$minimum < settings$maximum)
      value <- c(settings$minimum, settings$maximum)
    else if (draw_axis) {
      logarithmic <- isTRUE(settings$scale %in% c(1L, 2L)) && all(value > 0)
      transformed <- if (logarithmic) log10(value) else value
      span <- diff(transformed)
      if (span == 0) span <- max(abs(transformed), 1) * 0.1
      transformed <- transformed + c(-1, 1) * 0.04 * span
      value <- if (logarithmic) 10^transformed else transformed
    }
    value
  }
  xlim <- limits(xlim, "x", x_axis); ylim <- limits(ylim, "y", y_axis)
  xlog <- x_axis && isTRUE(sd_chart_get("x", list())$scale %in% c(1L, 2L))
  ylog <- y_axis && isTRUE(sd_chart_get("y", list())$scale %in% c(1L, 2L))
  if ((xlog && any(xlim <= 0)) || (ylog && any(ylim <= 0))) stop("A logarithmic chart axis requires positive limits.")
  plot(xlim, ylim, type = "n", axes = FALSE, main = "", xlab = "", ylab = "",
       log = paste0(if (xlog) "x" else "", if (ylog) "y" else ""), xaxs = "i", yaxs = "i")
  title(main = main)
  title(xlab = xlab, line = 3 + .5 * (category_lines + lines(xlab) - 2L))
  title(ylab = ylab, line = 3 + .5 * (lines(ylab) - 1L))
  if (x_axis) sd_chart_axis(1L)
  if (y_axis) sd_chart_axis(2L)
  if (isTRUE(sd_chart_get("boxAxes", FALSE))) box()
  invisible(list(xlim = xlim, ylim = ylim))
}
sd_chart_marker <- function(index = 1L) {
  markers <- sd_chart_get("markers", list())
  m <- if (length(markers)) markers[[1L + (index - 1L) %% length(markers)]] else list()
  shape <- m$shape; if (length(shape) != 1L || is.na(shape) || !shape %in% 1:9) shape <- 1L
  colour <- if (is.null(m$color)) "black" else m$color
  line <- if (is.null(m$lineColor)) colour else m$lineColor
  if (identical(sd_chart_get("useColour", TRUE), FALSE)) colour <- line <- "black"
  size <- m$size; if (length(size) != 1L || !is.finite(size) || size <= 0) size <- 6
  width <- m$width; if (length(width) != 1L || !is.finite(width) || width <= 0) width <- 1
  list(shape = shape, pch = if (isTRUE(m$filled)) c(16, 15, 17, 3, 4, 16, 15, 4, 18)[shape] else c(1, 0, 2, 3, 4, 1, 0, 4, 5)[shape],
       col = colour, bg = colour, lineColor = line, size = size, cex = size / 6,
       lwd = width, lty = sd_chart_lty(m$dashStyle), filled = isTRUE(m$filled))
}
sd_chart_points <- function(x, y, marker) {
  points(x, y, pch = marker$pch, col = marker$col, cex = marker$cex, lwd = marker$lwd)
}
sd_chart_legend <- function(labels, markers = NULL, fill = FALSE) {
  if (!length(labels) || !isTRUE(sd_chart_get("showLegend", length(labels) > 1L))) return(invisible(NULL))
  if (is.null(markers)) markers <- lapply(seq_along(labels), sd_chart_marker)
  colours <- vapply(markers, function(m) m$col, character(1))
  labels <- sd_chart_text(labels, 30L)
  arguments <- list(x = "bottom", legend = labels, bty = "n", cex = 9 / par("ps"), xpd = NA,
    inset = c(0, -(par("mai")[1] - .35) / par("pin")[2]), ncol = if (length(labels) > 3L) 2L else 1L)
  if (fill) arguments$fill <- colours else {
    arguments$col <- colours; arguments$pch <- vapply(markers, function(m) m$pch, numeric(1))
  }
  do.call(legend, arguments)
}
sd_chart_finish <- function() {
  if (!is.null(sd_chart_state$old)) { par(sd_chart_state$old); sd_chart_state$old <- NULL }
  invisible(NULL)
}

# Portable chart presentation, embedded in Continue in R scripts that bind chartSettings.
# hand-edited: shared drawing helpers, preserved when help recipes are regenerated.
# The recorded strings and observations remain editable R values; drawing wraps text only.
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
sd_chart_font <- function(prefix, size) {
  family <- sd_chart_get(paste0(prefix, "Family"), "Arial")
  points <- sd_chart_get(paste0(prefix, "Size"), size)
  style <- as.integer(sd_chart_get(paste0(prefix, "Style"), 0L))
  if (length(points) != 1L || !is.finite(points) || points <= 0) points <- size
  if (length(family) != 1L || is.na(family) || !nzchar(family)) family <- "Arial"
  if (length(style) != 1L || is.na(style)) style <- 0L
  if (names(dev.cur()) %in% c("pdf", "postscript") && !family %in% names(pdfFonts())) family <- "sans"
  list(family = family, size = points,
       font = 1L + as.integer(bitwAnd(style, 1L) != 0L) + 2L * as.integer(bitwAnd(style, 2L) != 0L))
}
sd_chart_wrap <- function(value, width, font) {
  before <- par("family"); on.exit(par(family = before)); par(family = font$family)
  paragraphs <- strsplit(value, "\n", fixed = TRUE)[[1L]]
  if (!length(paragraphs)) return("")
  paste(unlist(lapply(paragraphs, function(paragraph) {
    line <- ""; lines <- character()
    for (word in strsplit(trimws(paragraph), "[[:space:]]+")[[1L]]) {
      next_line <- if (nzchar(line)) paste(line, word) else word
      if (nzchar(line) && strwidth(next_line, units = "inches", cex = font$size / par("ps"), font = font$font) > width) {
        lines <- c(lines, line); line <- word
      } else line <- next_line
    }
    c(lines, line)
  }), use.names = FALSE), collapse = "\n")
}
sd_chart_axis <- function(side, at = NULL, labels = TRUE, ...) {
  axis_settings <- sd_chart_get(if (side %in% c(1L, 3L)) "x" else "y", list())
  font <- sd_chart_font("axisLabelFont", 10)
  if (is.null(at)) {
    interval <- axis_settings$interval; first <- axis_settings$firstTick
    limits <- par("usr")[if (side %in% c(1L, 3L)) 1:2 else 3:4]
    log_axis <- par(if (side %in% c(1L, 3L)) "xlog" else "ylog")
    if (log_axis) limits <- 10^limits
    if (length(interval) == 1L && is.finite(interval) && interval > 0 && length(first) == 1L && is.finite(first)) {
      indices <- c(ceiling((limits[1] - first) / interval - 1e-10), floor((limits[2] - first) / interval + 1e-10))
      if (all(is.finite(indices)) && diff(indices) >= 0 && diff(indices) < 10000)
        at <- first + seq(indices[1], indices[2]) * interval
    } else if (identical(as.integer(axis_settings$scale), 1L) && all(limits > 0)) {
      powers <- c(ceiling(log2(limits[1]) - 1e-10), floor(log2(limits[2]) + 1e-10))
      if (powers[2] >= powers[1]) at <- 2^seq(powers[1], powers[2])
    }
    if (is.null(at)) at <- axTicks(side)
  }
  if (isTRUE(axis_settings$grid)) {
    style <- axis_settings$gridStyle
    if (length(style) != 1L || is.na(style) || !style %in% 0:4) style <- 0L
    if (side %in% c(1L, 3L)) abline(v = at, col = "grey80", lty = sd_chart_lty(style)) else
      abline(h = at, col = "grey80", lty = sd_chart_lty(style))
  }
  if (isTRUE(labels)) labels <- if (identical(as.integer(axis_settings$scale), 3L))
    format(as.Date(at, origin = "1899-12-30")) else format(at, trim = TRUE)
  direction <- axis_settings$labelDirection
  if (length(direction) != 1L || is.na(direction)) direction <- 0L
  arguments <- modifyList(list(side = side, at = at, labels = labels, family = font$family,
    cex.axis = font$size / par("ps"), font.axis = font$font, las = if (direction == 0L) 1L else 3L), list(...))
  if (direction %in% c(2L, 3L, 4L) && !identical(labels, FALSE)) {
    arguments$labels <- FALSE
    do.call(axis, arguments)
    angle <- switch(as.character(direction), "2" = 270, "3" = 45, "4" = 315)
    usr <- par("usr"); margin <- par("csi") * 1.7
    if (side %in% c(1L, 3L)) {
      offset <- margin / par("pin")[2] * diff(usr[3:4])
      y <- if (side == 1L) usr[3] - offset else usr[4] + offset
      if (par("ylog")) y <- 10^y
      text(at, y, labels = labels, srt = angle, xpd = NA, family = font$family,
           cex = font$size / par("ps"), font = font$font)
    } else {
      offset <- margin / par("pin")[1] * diff(usr[1:2])
      x <- if (side == 2L) usr[1] - offset else usr[2] + offset
      if (par("xlog")) x <- 10^x
      text(x, at, labels = labels, srt = angle, xpd = NA, family = font$family,
           cex = font$size / par("ps"), font = font$font)
    }
  } else do.call(axis, arguments)
  marker <- axis_settings$marker
  if (length(marker) == 1L && is.finite(marker)) {
    if (side %in% c(1L, 3L)) { if (!par("xlog") || marker > 0) abline(v = marker) } else
      if (!par("ylog") || marker > 0) abline(h = marker)
  }
  invisible(at)
}
sd_chart_frame <- function(xlim, ylim, default_title = "", xlab = "", ylab = "", x_axis = TRUE, y_axis = TRUE,
                           category_labels = NULL, right_margin_inches = 0, legend_labels = NULL) {
  if (is.null(chart) && !isTRUE(sd_chart_state$warned)) {
    message("This saved run has no chart settings; using standard chart options.")
    sd_chart_state$warned <- TRUE
  }
  if (is.null(sd_chart_state$old)) sd_chart_state$old <- par(c("mar", "family", "cex", "cex.main", "cex.lab", "cex.axis", "font.main", "font.lab", "font.axis", "lwd"))
  title_font <- sd_chart_font("titleFont", 12); axis_font <- sd_chart_font("axisTitleFont", 10)
  label_font <- sd_chart_font("axisLabelFont", 10)
  line_width <- sd_chart_get("lineWidth", 1)
  if (length(line_width) != 1L || !is.finite(line_width) || line_width <= 0) line_width <- 1
  par(cex = 1, family = label_font$family, mar = c(5, 5, 4, 2),
      cex.main = title_font$size / par("ps"), font.main = title_font$font,
      cex.lab = axis_font$size / par("ps"), font.lab = axis_font$font,
      cex.axis = label_font$size / par("ps"), font.axis = label_font$font, lwd = line_width)
  main <- sd_chart_get("title", default_title); xlab <- sd_chart_get("xTitle", xlab); ylab <- sd_chart_get("yTitle", ylab)
  margins <- par("mai")
  if (length(right_margin_inches) == 1L && is.finite(right_margin_inches) && right_margin_inches > 0)
    margins[4] <- max(margins[4], right_margin_inches)
  labels <- sd_chart_strings(if (is.null(category_labels)) sd_chart_get("seriesTitles", character()) else category_labels)
  if (!y_axis && length(labels)) margins[2] <- max(margins[2],
    max(strwidth(labels, units = "inches", cex = label_font$size / par("ps"), font = label_font$font)) + 0.35)
  sd_chart_state$legend <- NULL
  if (length(legend_labels) && isTRUE(sd_chart_get("showLegend", length(legend_labels) > 1L))) {
    font <- sd_chart_font("legendFont", 10)
    side <- if (sd_chart_get("type", "") %in% c("ScatterXY", "LineXY")) "left" else "bottom"
    before <- par("family"); par(family = font$family)
    available <- max(0.75, par("fin")[1] - 0.3)
    label_width <- max(strwidth(legend_labels, units = "inches", cex = font$size / par("ps"), font = font$font))
    columns <- if (side == "left") 1L else max(1L, min(length(legend_labels), floor(available / (label_width + 0.6))))
    wrap_width <- if (side == "left") min(2, available * 0.35) else available / columns - 0.6
    displayed <- vapply(legend_labels, sd_chart_wrap, character(1), width = max(0.3, wrap_width), font = font)
    line_count <- max(lengths(strsplit(displayed, "\n", fixed = TRUE)))
    height <- ceiling(length(displayed) / columns) * font$size / 72 * 1.5 * line_count + 0.15
    width <- max(strwidth(displayed, units = "inches", cex = font$size / par("ps"), font = font$font)) + 0.65
    par(family = before)
    sd_chart_state$legend <- list(side = side, labels = displayed, columns = columns,
                                 height = height, width = width, line_count = line_count)
    if (side == "left") margins[2] <- margins[2] + width + 0.1 else margins[1] <- margins[1] + height + 0.1
  }
  base_margins <- margins
  for (pass in 1:3) {
    figure_size <- par("fin")
    area <- figure_size - c(sum(margins[c(2, 4)]), sum(margins[c(1, 3)]))
    centre <- margins[2] + area[1] / 2
    display_main <- sd_chart_wrap(main, max(0.5, 2 * min(centre, figure_size[1] - centre) - 0.2), title_font)
    display_x <- sd_chart_wrap(xlab, max(0.5, area[1]), axis_font)
    display_y <- sd_chart_wrap(ylab, max(0.5, area[2]), axis_font)
    lines <- function(value) max(1L, length(strsplit(value, "\n", fixed = TRUE)[[1L]]))
    margins <- base_margins
    margins[3] <- margins[3] + (lines(display_main) - 1L) * par("csi") * title_font$size / par("ps")
    margins[1] <- margins[1] + (lines(display_x) - 1L) * par("csi") * axis_font$size / par("ps")
    margins[2] <- margins[2] + (lines(display_y) - 1L) * par("csi") * axis_font$size / par("ps")
    par(mai = margins)
  }
  limits <- function(values, name, draw_axis) {
    settings <- sd_chart_get(name, list())
    value <- range(values, finite = TRUE)
    if (!all(is.finite(value))) stop("Select finite observations for this chart.")
    explicit <- draw_axis && length(settings$minimum) == 1L && length(settings$maximum) == 1L &&
        is.finite(settings$minimum) && is.finite(settings$maximum) && settings$minimum < settings$maximum
    if (explicit)
      value <- c(settings$minimum, settings$maximum)
    else if (draw_axis) {
      log_axis <- isTRUE(settings$scale %in% c(1L, 2L))
      transformed <- if (log_axis && all(value > 0)) log10(value) else value
      span <- diff(transformed)
      if (span == 0) span <- max(abs(transformed), 1) * 0.1
      transformed <- transformed + c(-1, 1) * 0.04 * span
      value <- if (log_axis && all(value > 0)) 10^transformed else transformed
    }
    value
  }
  xlim <- limits(xlim, "x", x_axis); ylim <- limits(ylim, "y", y_axis)
  is_log <- function(name) isTRUE(sd_chart_get(name, list())$scale %in% c(1L, 2L))
  xlog <- is_log("x") && x_axis; ylog <- is_log("y") && y_axis
  if ((xlog && any(xlim <= 0)) || (ylog && any(ylim <= 0))) stop("A logarithmic chart axis requires positive limits.")
  plot(xlim, ylim, type = "n", axes = FALSE, main = "", xlab = "", ylab = "",
       log = paste0(if (xlog) "x" else "", if (ylog) "y" else ""), xaxs = "i", yaxs = "i")
  title(main = display_main, family = title_font$family, cex.main = title_font$size / par("ps"), font.main = title_font$font)
  title(xlab = display_x, family = axis_font$family, cex.lab = axis_font$size / par("ps"), font.lab = axis_font$font,
        line = par("mgp")[1] + (lines(display_x) - 1L) * 0.5 * axis_font$size / par("ps"))
  title(ylab = display_y, family = axis_font$family, cex.lab = axis_font$size / par("ps"), font.lab = axis_font$font,
        line = par("mgp")[1] + (lines(display_y) - 1L) * 0.5 * axis_font$size / par("ps"))
  if (x_axis) sd_chart_axis(1L)
  if (y_axis) sd_chart_axis(2L)
  if (isTRUE(sd_chart_get("boxAxes", FALSE))) box()
  invisible(list(xlim = xlim, ylim = ylim))
}
sd_chart_marker <- function(index = 1L) {
  markers <- sd_chart_get("markers", list())
  marker <- if (length(markers)) markers[[1L + (index - 1L) %% length(markers)]] else list()
  shape <- marker$shape; if (length(shape) != 1L || !shape %in% 1:9) shape <- 1L
  filled <- isTRUE(marker$filled)
  pch <- c(if (filled) 16 else 1, if (filled) 15 else 0, if (filled) 17 else 2, 3, 4,
           if (filled) 16 else 1, if (filled) 15 else 0, if (filled) 15 else 0, if (filled) 18 else 5)[shape]
  colour <- marker$color; if (is.null(colour)) colour <- "black"
  line_colour <- marker$lineColor; if (is.null(line_colour)) line_colour <- colour
  if (identical(sd_chart_get("useColour", TRUE), FALSE)) colour <- line_colour <- "black"
  size <- marker$size; if (length(size) != 1L || !is.finite(size) || size <= 0) size <- 6
  width <- marker$width; if (length(width) != 1L || !is.finite(width) || width <= 0) width <- 1
  dash <- marker$dashStyle; if (length(dash) != 1L || !dash %in% 0:4) dash <- 0L
  list(shape = shape, pch = pch, col = colour, bg = if (filled) colour else NA, lineColor = line_colour,
       size = size, cex = size / 6, lwd = width, lty = sd_chart_lty(dash), filled = filled,
       fillStyle = if (is.null(marker$fillStyle)) 0L else marker$fillStyle)
}
sd_chart_points <- function(x, y, marker) {
  points(x, y, pch = marker$pch, col = marker$col, bg = marker$bg, cex = marker$cex, lwd = marker$lwd)
  if (!marker$shape %in% 6:8 || !length(x)) return(invisible(NULL))
  # Compound symbols use an internal stroke, rather than R's plus/cross symbols.
  # Calculate offsets in inches so circles remain circular on unequal/log axes.
  half <- par("cin")[2] * marker$cex * 0.25
  xx <- grconvertX(x, "user", "inches"); yy <- grconvertY(y, "user", "inches")
  stroke <- if (marker$filled) "white" else marker$col
  dx <- if (marker$shape == 6L) 0 else half
  segments(grconvertX(xx - dx, "inches", "user"), grconvertY(yy + half, "inches", "user"),
           grconvertX(xx + dx, "inches", "user"), grconvertY(yy - half, "inches", "user"), col = stroke, lwd = marker$lwd)
  if (marker$shape == 8L)
    segments(grconvertX(xx - half, "inches", "user"), grconvertY(yy - half, "inches", "user"),
             grconvertX(xx + half, "inches", "user"), grconvertY(yy + half, "inches", "user"), col = stroke, lwd = marker$lwd)
  invisible(NULL)
}
sd_chart_legend <- function(labels, markers = NULL, fill = FALSE) {
  before_flag <- sd_chart_state$drawing_legend
  sd_chart_state$drawing_legend <- TRUE
  sd_chart_state$legend_keys <- NULL
  on.exit(sd_chart_state$drawing_legend <- before_flag, add = TRUE)
  if (!isTRUE(sd_chart_get("showLegend", length(labels) > 1L)) || !length(labels)) return(invisible(NULL))
  font <- sd_chart_font("legendFont", 10)
  if (is.null(markers)) markers <- lapply(seq_along(labels), sd_chart_marker)
  before <- par(c("family", "xpd")); on.exit(par(before), add = TRUE)
  par(family = font$family, xpd = NA)
  layout <- sd_chart_state$legend
  if (is.null(layout)) return(invisible(NULL))
  markers <- rep_len(markers, length(layout$labels))
  figure <- par("fig"); device <- dev.size("in")
  if (layout$side == "left") {
    x <- figure[1L] * device[1L] + 0.05
    y <- mean(grconvertY(c(0, 1), "npc", "inches"))
  } else {
    x <- mean(figure[1:2]) * device[1L]
    y <- figure[3L] * device[2L] + 0.1 + layout$height
  }
  args <- list(x = grconvertX(x, "inches", "user"), y = grconvertY(y, "inches", "user"),
    legend = layout$labels, xjust = if (layout$side == "left") 0 else 0.5,
    yjust = if (layout$side == "left") 0.5 else 1, ncol = layout$columns,
    y.intersp = layout$line_count, xpd = NA, bty = "n", cex = font$size / par("ps"), text.font = font$font,
    col = vapply(markers, function(m) m$col, character(1)))
  if (fill) {
    args$fill <- rep(NA_character_, length(markers))
    args$border <- NA
  } else {
    args$pch <- rep(NA_integer_, length(markers))
    args$x.intersp <- 2
  }
  # Base graphics supplies text and layout. Draw the keys ourselves from the
  # public returned text positions so they use the same symbols and fill
  # patterns as the plot, including compound symbols and monochrome hatching.
  result <- do.call(legend, args)
  text_x <- result$text$x; text_y <- result$text$y
  if (par("xlog")) text_x <- 10^text_x
  if (par("ylog")) text_y <- 10^text_y
  text_x <- grconvertX(text_x, "user", "inches")
  text_y <- grconvertY(text_y, "user", "inches")
  character_width <- par("cin")[1L] * font$size / par("ps")
  character_height <- par("cin")[2L] * font$size / par("ps")
  sd_chart_state$legend_keys <- vector("list", length(markers))
  for (i in seq_along(markers)) {
    marker <- markers[[i]]
    if (fill) {
      left <- grconvertX(text_x[i] - 1.8 * character_width, "inches", "user")
      right <- grconvertX(text_x[i] - character_width, "inches", "user")
      bottom <- grconvertY(text_y[i] - 0.25 * character_height, "inches", "user")
      top <- grconvertY(text_y[i] + 0.25 * character_height, "inches", "user")
      style <- if (isTRUE(sd_chart_get("useColour", TRUE))) 1L else marker$fillStyle
      if (length(style) != 1L || is.na(style) || !style %in% 0:4) style <- 0L
      colour <- if (style == 0L) NA else marker$col
      rect(left, bottom, right, top, col = colour, border = marker$lineColor,
           lwd = marker$lwd, lty = marker$lty, density = if (style %in% 2:4) 16 else NULL,
           angle = if (style == 3L) 135 else 45)
      if (style == 4L)
        rect(left, bottom, right, top, col = colour, border = NA, density = 16, angle = 135)
      sd_chart_state$legend_keys[[i]] <- list(type = "fill", left = left, right = right,
        bottom = bottom, top = top, fillStyle = style)
    } else {
      x <- grconvertX(text_x[i] - character_width, "inches", "user")
      y <- grconvertY(text_y[i], "inches", "user")
      sd_chart_points(x, y, marker)
      sd_chart_state$legend_keys[[i]] <- list(type = "point", x = x, y = y, shape = marker$shape)
    }
  }
  invisible(result)
}
sd_chart_finish <- function() {
  if (!is.null(sd_chart_state$old)) { par(sd_chart_state$old); sd_chart_state$old <- NULL }
  invisible(NULL)
}

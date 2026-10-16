# StatsDirect recipe: one box and whisker chart for the selected columns and chart settings.
# data: mets... = data
# settings: box_settings = boxWhisker

# Older saved runs may not contain chart options. Use the standard options only
# for those runs; never substitute the help topic's example data or titles.
sd_box_setting <- function(name, default) {
  if (is.list(box_settings) && !is.null(box_settings[[name]]))
    box_settings[[name]] else default
}
if (!exists("box_settings", inherits = FALSE)) box_settings <- NULL
box_method <- sd_box_setting("method", 1L)
box_inner_fence <- sd_box_setting("innerFence", TRUE)
box_outer_fence <- sd_box_setting("outerFence", TRUE)
box_mark_mean_median <- sd_box_setting("markMeanAndMedian", FALSE)
box_confidence <- sd_box_setting("confidence", 0.95)
box_horizontal <- sd_box_setting("horizontal", TRUE)
box_title <- sd_box_setting("title", paste0("Box & whisker plot",
  if (length(names(mets))) paste0(": ", paste(names(mets), collapse = ", "))))
box_series_titles <- sd_box_setting("seriesTitles", names(mets))
box_box_axes <- sd_box_setting("boxAxes", FALSE)
box_limits <- c(sd_box_setting("valueMinimum", NULL), sd_box_setting("valueMaximum", NULL))
box_value_scale <- sd_box_setting("valueScale", 0L)
box_value_interval <- sd_box_setting("valueInterval", NULL)
box_value_first_tick <- sd_box_setting("valueFirstTick", NULL)
box_value_grid <- sd_box_setting("valueGrid", FALSE)
box_value_grid_style <- as.integer(sd_box_setting("valueGridStyle", 0L))
if (length(box_value_grid_style) != 1L || is.na(box_value_grid_style) ||
    !box_value_grid_style %in% 0:4) box_value_grid_style <- 0L
box_value_marker <- sd_box_setting("valueMarker", NULL)
box_line_width <- sd_box_setting("lineWidth", 1)
if (length(box_line_width) != 1L || !is.finite(box_line_width) || box_line_width <= 0)
  box_line_width <- 1
sd_box_font <- function(prefix, default_size) {
  family <- sd_box_setting(paste0(prefix, "Family"), "Arial")
  size <- sd_box_setting(paste0(prefix, "Size"), default_size)
  style <- as.integer(sd_box_setting(paste0(prefix, "Style"), 0L))
  if (length(family) != 1L || is.na(family) || !nzchar(family)) family <- "Arial"
  if (length(size) != 1L || !is.finite(size) || size <= 0) size <- default_size
  if (length(style) != 1L || is.na(style)) style <- 0L
  list(family = family, size = size,
       font = 1L + as.integer(bitwAnd(style, 1L) != 0L) + 2L * as.integer(bitwAnd(style, 2L) != 0L))
}
box_title_font <- sd_box_font("titleFont", 12)
box_axis_title_font <- sd_box_font("axisTitleFont", 10)
box_axis_label_font <- sd_box_font("axisLabelFont", 10)
if (is.null(box_settings))
  message("This saved run has no chart settings; using standard box-and-whisker options.")

if (length(box_method) != 1L || is.na(box_method) || !box_method %in% 1:6)
  stop("Unknown box-and-whisker method.")
if (box_method == 3L && (length(box_confidence) != 1L || !is.finite(box_confidence) ||
    box_confidence <= 0 || box_confidence >= 1))
  stop("The confidence level must be between zero and one.")
if (length(box_value_scale) != 1L || is.na(box_value_scale) || !box_value_scale %in% c(-1L, 0L, 1L, 2L))
  stop("Unknown box-and-whisker value-axis scale.")

# StatsDirect's conventional quartiles use the (n + 1)p ordered value,
# interpolating between neighbours: R's quantile(type = 6), not boxplot hinges.
# Mean confidence limits use a t quantile and sample SD; the SD, SE and CI
# methods all use the same normal-distribution SD fences.
sd_box_summary <- function(x, method, inner, outer, confidence) {
  x <- sort(x[!is.na(x)])
  if (!length(x) || any(!is.finite(x)))
    stop("Each box-and-whisker series must contain finite numeric observations.")
  n <- length(x)
  q <- quantile(x, c(0.25, 0.5, 0.75), type = 6, names = FALSE)
  limits <- range(x)
  centile <- method %in% c(4L, 5L)
  if (method %in% c(1L, 4L, 5L)) {
    centre <- q[2]
    other <- mean(x)
    box <- q[c(1, 3)]
    if (method == 1L) {
      fence_inner <- box + c(-1, 1) * 1.5 * diff(box)
      fence_outer <- box + c(-1, 1) * 3 * diff(box)
    } else {
      fence_inner <- quantile(x, if (method == 4L) c(0.09, 0.91) else c(0.1, 0.9),
                              type = 6, names = FALSE)
      fence_outer <- if (method == 4L)
        quantile(x, c(0.02, 0.98), type = 6, names = FALSE) else limits
    }
    fence_inner <- pmax(limits[1], pmin(limits[2], fence_inner))
    fence_outer <- pmax(limits[1], pmin(limits[2], fence_outer))
  } else {
    if (n < 2L) stop("Mean/SD, mean/SE and mean/CI charts require at least two observations per series.")
    centre <- mean(x)
    other <- q[2]
    deviation <- sd(x)
    error <- deviation / sqrt(n)
    half_width <- switch(as.character(method), "2" = deviation, "6" = error,
                         "3" = qt((1 + confidence) / 2, n - 1) * error)
    box <- centre + c(-1, 1) * half_width
    fence_inner <- centre + c(-1, 1) * qnorm(0.975) * deviation
    fence_outer <- centre + c(-1, 1) * qnorm(0.995) * deviation
  }
  if (!centile && !inner) fence_inner <- if (method == 1L) box else c(0, 0)
  if (!centile && !outer) fence_outer <- if (method == 1L) limits else c(0, 0)
  # The nearest observation inside the enabled fence ends the whisker.
  # Percentile summaries end at their outer percentile, even between observations.
  if (centile) whiskers <- fence_outer else {
    fence <- if (inner) fence_inner else if (outer) fence_outer else limits
    whiskers <- c(min(x[x >= fence[1]]), max(x[x <= fence[2]]))
  }
  beyond_inner <- !centile & inner & (x < fence_inner[1] | x > fence_inner[2])
  beyond_outer <- (centile | outer) & (x < fence_outer[1] | x > fence_outer[2])
  brackets <- !centile & !c(
    (inner && limits[1] < fence_inner[1]) || (outer && limits[1] < fence_outer[1]),
    (inner && limits[2] > fence_inner[2]) || (outer && limits[2] > fence_outer[2]))
  list(x = x, n = n, centre = centre, other = other, box = box,
       inner = fence_inner, outer = fence_outer, whiskers = whiskers,
       hollow = x[beyond_inner & !beyond_outer], filled = x[beyond_outer],
       brackets = brackets, centile = centile)
}

if (!is.list(mets) || !length(mets)) stop("Select at least one numeric data column.")
box_series_titles <- as.character(unlist(box_series_titles, use.names = FALSE))
if (length(box_series_titles) != length(mets)) box_series_titles <- names(mets)
if (is.null(box_series_titles)) box_series_titles <- paste("Series", seq_along(mets))
box_summaries <- lapply(mets, sd_box_summary, method = box_method,
                        inner = box_inner_fence, outer = box_outer_fence,
                        confidence = box_confidence)
names(box_summaries) <- box_series_titles

sd_box_axis_title <- function() {
  if (box_method %in% c(1L, 4L, 5L)) {
    centre <- if (box_mark_mean_median) "median & mean(x)" else "median"
    if (box_method == 4L)
      return(paste0("min < [ 2nd < 9th < [ LQ < ", centre, " > UQ | > 91st > 98th ] > max"))
    if (box_method == 5L)
      return(paste0("[ min < 10th < | LQ < ", centre, " > UQ | > 90th > max ]"))
    label <- paste0("min < LQ < ", centre, " > UQ > max")
    fences <- c(if (box_inner_fence) "1.5", if (box_outer_fence) "3.0")
    if (length(fences)) label <- paste0(label, ", fence", if (length(fences) > 1) "s",
                                       " (", paste(fences, collapse = " & "), " IQR)")
  } else {
    centre <- if (box_mark_mean_median) "mean & median(x)" else "mean"
    side <- if (box_method == 2L) "1 SD" else "1 SE"
    label <- if (box_method == 3L)
      paste0("min < ", centre, " +/- ", format(100 * box_confidence), "% confidence interval > max") else
      paste0("min < ", side, " < ", centre, " > ", side, " > max")
    fences <- c(if (box_inner_fence) "1.96", if (box_outer_fence) "2.58")
    if (length(fences)) label <- paste0(label, ", fence", if (length(fences) > 1) "s",
                                       " (", paste(fences, collapse = ", "), " SD)")
  }
  label
}
box_axis_title <- sd_box_setting("axisTitle", sd_box_axis_title())

# A single drawing function shares exactly the same summaries for both orientations.
sd_box_draw <- function() {
  k <- length(box_summaries)
  explicit_limits <- length(box_limits) == 2L && all(is.finite(box_limits)) && box_limits[1] < box_limits[2]
  limits <- if (explicit_limits) box_limits else
    range(unlist(lapply(box_summaries, function(s) s$x), use.names = FALSE))
  logarithmic <- box_value_scale %in% c(1L, 2L)
  if (logarithmic && (any(limits <= 0) || any(vapply(box_summaries,
      function(s) any(c(s$x, s$box) <= 0), logical(1)))))
    stop("A logarithmic box-and-whisker axis requires positive observations, box limits and axis limits.")
  # Leave selected bounds exact. Older runs without bounds need a little room
  # beyond the extremes, otherwise their end brackets and outliers are clipped.
  if (!explicit_limits) {
    transformed <- if (logarithmic) log10(limits) else limits
    span <- diff(transformed)
    if (span == 0) span <- max(abs(transformed), 1) * 0.1
    transformed <- transformed + c(-1, 1) * 0.04 * span
    limits <- if (logarithmic) 10^transformed else transformed
  }
  # R expands a zero-width range so constant columns still have a visible chart.
  # Restore only font/margin parameters: restoring layout parameters can create pages.
  old <- par(c("mar", "family", "cex", "cex.main", "cex.lab", "cex.axis", "font.main", "font.lab", "font.axis", "lwd"))
  on.exit(par(old))
  # The base PDF device has a PostScript font database, rather than the system
  # fonts used by SVG. Its standard sans-serif family is Helvetica.
  device_family <- function(family) {
    if (names(dev.cur()) %in% c("pdf", "postscript") &&
        !family %in% names(pdfFonts())) "sans" else family
  }
  par(mar = if (box_horizontal) c(5, 6, 4, 2) else c(7, 5, 4, 2),
      family = device_family(box_axis_label_font$family),
      cex = 1,
      cex.main = box_title_font$size / par("ps"),
      cex.lab = box_axis_title_font$size / par("ps"), cex.axis = box_axis_label_font$size / par("ps"),
      font.main = box_title_font$font, font.lab = box_axis_title_font$font,
      font.axis = box_axis_label_font$font, lwd = box_line_width)
  # Measure in physical units so labels fit the current device and selected
  # font, without opening a second plot or assuming a fixed image resolution.
  margins <- par("mai")
  label_width <- max(strwidth(box_series_titles, units = "inches",
                             cex = box_axis_label_font$size / par("ps"),
                             font = box_axis_label_font$font), 0)
  label_height <- max(strheight(box_series_titles, units = "inches",
                               cex = box_axis_label_font$size / par("ps"),
                               font = box_axis_label_font$font), 0)
  gap <- par("mgp")[2] * par("csi") * par("mex") + 0.15
  if (box_horizontal) margins[2] <- max(margins[2], label_width + gap) else
    margins[1] <- max(margins[1], label_height + gap)
  par(mai = margins)
  # Wrap text using this device's font metrics; keep the recorded text intact
  # in box_title/box_axis_title and preserve the chosen typeface and point size.
  wrap_title <- function(text, width, descriptor) {
    previous_family <- par("family")
    on.exit(par(family = previous_family))
    par(family = device_family(descriptor$family))
    paragraphs <- strsplit(text, "\n", fixed = TRUE)[[1L]]
    if (!length(paragraphs)) return("")
    lines <- unlist(lapply(paragraphs, function(paragraph) {
      words <- strsplit(trimws(paragraph), "[[:space:]]+")[[1L]]
      result <- character()
      current <- ""
      for (word in words) {
        candidate <- if (nzchar(current)) paste(current, word) else word
        if (nzchar(current) && strwidth(candidate, units = "inches",
            cex = descriptor$size / par("ps"), font = descriptor$font) > width) {
          result <- c(result, current)
          current <- word
        } else current <- candidate
      }
      c(result, current)
    }), use.names = FALSE)
    paste(lines, collapse = "\n")
  }
  base_margins <- margins
  # Extra text lines consume margin space, which can shorten the other axis.
  # Recheck without creating a plot page as those margins settle.
  for (pass in 1:3) {
    device_size <- dev.size("in")
    plot_width <- device_size[1] - sum(margins[c(2, 4)])
    plot_height <- device_size[2] - sum(margins[c(1, 3)])
    centre <- margins[2] + plot_width / 2
    display_title <- wrap_title(box_title,
      max(0.5, 2 * min(centre, device_size[1] - centre) - 0.2), box_title_font)
    display_axis_title <- wrap_title(box_axis_title,
      max(0.5, if (box_horizontal) plot_width else plot_height), box_axis_title_font)
    title_lines <- length(strsplit(display_title, "\n", fixed = TRUE)[[1L]])
    axis_lines <- length(strsplit(display_axis_title, "\n", fixed = TRUE)[[1L]])
    margins <- base_margins
    margins[3] <- margins[3] + max(0, title_lines - 1) * par("csi") * box_title_font$size / par("ps")
    label_side <- if (box_horizontal) 1L else 2L
    margins[label_side] <- margins[label_side] + max(0, axis_lines - 1) * par("csi") * box_axis_title_font$size / par("ps")
    par(mai = margins)
  }
  plot(if (box_horizontal) limits else c(0, k),
       if (box_horizontal) c(0, k) else limits, type = "n", axes = FALSE,
       xlab = "", ylab = "", main = "",
       log = if (logarithmic) { if (box_horizontal) "x" else "y" } else "",
       xaxs = "i", yaxs = "i")
  title(main = display_title, family = device_family(box_title_font$family),
        cex.main = box_title_font$size / par("ps"), font.main = box_title_font$font)
  title(xlab = if (box_horizontal) display_axis_title else "",
        ylab = if (box_horizontal) "" else display_axis_title,
        family = device_family(box_axis_title_font$family),
        cex.lab = box_axis_title_font$size / par("ps"), font.lab = box_axis_title_font$font,
        line = par("mgp")[1] + max(0, axis_lines - 1) * 0.5 * box_axis_title_font$size / par("ps"))
  # Linear scales carry the user's interval and first tick. Native natural-log
  # scales label powers of two; their positions are equally spaced in any log base.
  value_ticks <- NULL
  if (length(box_value_interval) == 1L && is.finite(box_value_interval) && box_value_interval > 0 &&
      length(box_value_first_tick) == 1L && is.finite(box_value_first_tick)) {
    indices <- c(ceiling((limits[1] - box_value_first_tick) / box_value_interval - 1e-10),
                 floor((limits[2] - box_value_first_tick) / box_value_interval + 1e-10))
    if (all(is.finite(indices)) && indices[2] >= indices[1] && diff(indices) <= 10000)
      value_ticks <- box_value_first_tick + seq(indices[1], indices[2]) * box_value_interval
  } else if (box_value_scale == 1L) {
    powers <- c(ceiling(log2(limits[1]) - 1e-10), floor(log2(limits[2]) + 1e-10))
    if (powers[2] >= powers[1]) value_ticks <- 2^seq(powers[1], powers[2])
  }
  value_side <- if (box_horizontal) 1 else 2
  if (is.null(value_ticks)) value_ticks <- axTicks(value_side)
  if (logarithmic) value_ticks <- value_ticks[value_ticks > 0]
  if (box_value_grid) {
    if (box_horizontal) abline(v = value_ticks, col = "grey80", lty = box_value_grid_style + 1L) else
      abline(h = value_ticks, col = "grey80", lty = box_value_grid_style + 1L)
  }
  axis(value_side, at = value_ticks, labels = format(value_ticks, trim = TRUE),
       las = 1,
       family = device_family(box_axis_label_font$family),
       cex.axis = box_axis_label_font$size / par("ps"), font.axis = box_axis_label_font$font)
  positions <- if (box_horizontal) k - seq_len(k) + 0.5 else seq_len(k) - 0.5
  axis(if (box_horizontal) 2 else 1, at = positions, labels = box_series_titles,
       las = 1, tick = FALSE,
       family = device_family(box_axis_label_font$family),
       cex.axis = box_axis_label_font$size / par("ps"), font.axis = box_axis_label_font$font)
  if (length(box_value_marker) == 1L && is.finite(box_value_marker) &&
      (!logarithmic || box_value_marker > 0)) {
    if (box_horizontal) abline(v = box_value_marker) else abline(h = box_value_marker)
  }
  if (box_box_axes) box()
  segment <- function(a, b, c, d, ...) {
    if (box_horizontal) segments(a, b, c, d, ...) else segments(b, a, d, c, ...)
  }
  mark <- function(a, b, ...) {
    if (box_horizontal) points(a, b, ...) else points(b, a, ...)
  }
  # The small inward bracket denotes a whisker that reaches the observed extreme.
  tip <- diff(par("usr")[if (box_horizontal) 1:2 else 3:4]) * 0.01
  for (i in seq_len(k)) {
    s <- box_summaries[[i]]
    at <- positions[i]
    if (box_horizontal) rect(s$box[1], at - 0.3335, s$box[2], at + 0.3335) else
      rect(at - 0.3335, s$box[1], at + 0.3335, s$box[2])
    segment(s$centre, at - 0.3335, s$centre, at + 0.3335)
    if (box_mark_mean_median) mark(s$other, at, pch = 4, cex = 1.3)
    mark(s$centre, at, pch = 18, cex = 1.3)
    segment(s$whiskers, at, s$box, at)
    segment(s$whiskers, at - 0.111, s$whiskers, at + 0.111)
    if (s$centile) segment(s$inner, at - 0.111, s$inner, at + 0.111, lty = 3)
    for (j in which(s$brackets)) {
      end <- s$whiskers[j]
      inward <- if (logarithmic) end * 10^(if (j == 1L) tip else -tip) else
        end + if (j == 1L) tip else -tip
      segment(end, at + c(-0.111, 0.111), inward,
              at + c(-0.111, 0.111))
    }
    mark(s$hollow, rep(at, length(s$hollow)), pch = 1)
    mark(s$filled, rep(at, length(s$filled)), pch = 16)
  }
}
sd_box_draw()

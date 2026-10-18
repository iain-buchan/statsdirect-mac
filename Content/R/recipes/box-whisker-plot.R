# StatsDirect recipe: one box plot of the selected data, using R's native bxp().
# data: mets... = data
# settings: box_settings = boxWhisker

# Saved analysis choices. Older reports use the standard options.
if (!exists("box_settings", inherits = FALSE)) box_settings <- list()
if (is.null(box_settings))
  message("This saved run has no chart settings; using standard box-and-whisker options.")
sd_box_setting <- function(name, default) {
  if (!is.null(box_settings[[name]])) box_settings[[name]] else default
}
# Methods: 1 quartiles; 2 mean/SD; 3 mean/CI; 4 seven-number;
#          5 Bowley; 6 mean/SE. All summaries below use standard R functions.
box_method <- sd_box_setting("method", 1L)
box_inner_fence <- sd_box_setting("innerFence", TRUE)
box_outer_fence <- sd_box_setting("outerFence", TRUE)
box_mark_mean_median <- sd_box_setting("markMeanAndMedian", FALSE)
box_confidence <- sd_box_setting("confidence", 0.95)
box_horizontal <- sd_box_setting("horizontal", TRUE)
box_title <- sd_box_setting("title", "Box and whisker plot")
box_axis_title <- sd_box_setting("axisTitle", "Value")
box_series_titles <- as.character(unlist(sd_box_setting("seriesTitles", names(mets))))
if (!length(box_series_titles)) box_series_titles <- paste("Series", seq_along(mets))
if (!is.list(mets) || !length(mets) || length(box_series_titles) != length(mets))
  stop("Select numeric columns with one label per series.")
if (!box_method %in% 1:6) stop("Unknown box-and-whisker method.")
if (box_method == 3L && (!is.finite(box_confidence) || box_confidence <= 0 || box_confidence >= 1))
  stop("The confidence level must be between zero and one.")

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
  list(x = x, n = n, centre = centre, other = other, box = box,
       inner = fence_inner, outer = fence_outer, whiskers = whiskers,
       hollow = x[beyond_inner & !beyond_outer], filled = x[beyond_outer],
       centile = centile)
}

box_summaries <- lapply(mets, sd_box_summary, method = box_method,
  inner = box_inner_fence, outer = box_outer_fence, confidence = box_confidence)
names(box_summaries) <- box_series_titles

# bxp() accepts summaries calculated with ordinary R functions. Unlike boxplot(),
# it does not replace our chosen quartiles or mean/SD, SE and confidence limits.
box_plot <- list(
  stats = vapply(box_summaries, function(s) c(s$whiskers[1], s$box[1], s$centre,
                                           s$box[2], s$whiskers[2]), numeric(5)),
  n = lengths(lapply(box_summaries, function(s) s$x)), names = box_series_titles)

sd_box_draw <- function() {
  old <- par(c("mai", "oma", "family", "cex", "cex.main", "cex.lab", "cex.axis", "font.main"))
  on.exit(par(old))
  # Use readable R typography rather than copying fonts sized for the desktop canvas.
  family <- if (names(dev.cur()) == "svg") "Arial" else "sans"
  par(family = family, cex = 1, cex.main = 12 / par("ps"),
      cex.lab = 10 / par("ps"), cex.axis = 9 / par("ps"), font.main = 2)
  wrap <- function(text, width) paste(strwrap(text, width = width), collapse = "\n")
  k <- length(box_summaries)
  displayed_names <- vapply(box_series_titles, wrap, character(1),
    width = if (box_horizontal) 24 else max(8, floor(60 / k)))
  displayed_title <- wrap(box_title, 60)
  displayed_axis <- wrap(box_axis_title, if (box_horizontal) 55 else 40)
  lines <- function(text) max(1L, lengths(strsplit(text, "\n", fixed = TRUE)))
  par(mai = c(if (box_horizontal) 0.65 + 0.14 * lines(displayed_axis) else
                0.4 + 0.15 * lines(displayed_names),
              if (box_horizontal) 1.6 else 0.55 + 0.22 * lines(displayed_axis), 0.15, 0.2),
      oma = c(0, 0, lines(displayed_title) + 1, 0))
  limits <- c(sd_box_setting("valueMinimum", NULL), sd_box_setting("valueMaximum", NULL))
  explicit_limits <- length(limits) == 2L && all(is.finite(limits)) && limits[1] < limits[2]
  if (!explicit_limits) limits <- range(unlist(lapply(box_summaries, function(s) c(s$x, s$box))))
  scale <- sd_box_setting("valueScale", 0L)
  logarithmic <- scale %in% c(1L, 2L)
  if (logarithmic && any(c(limits, box_plot$stats, unlist(mets)) <= 0, na.rm = TRUE))
    stop("A logarithmic axis requires positive observations, box limits and axis limits.")
  positions <- if (box_horizontal) rev(seq_len(k)) else seq_len(k)
  bxp(box_plot, horizontal = box_horizontal, at = positions, ylim = limits,
      log = if (logarithmic) { if (box_horizontal) "x" else "y" } else "",
      axes = FALSE, ann = FALSE, frame.plot = FALSE, outline = FALSE,
      boxfill = NA, boxwex = 0.6, medlwd = 1, whisklty = 1,
      yaxs = if (explicit_limits) "i" else "r")
  title(main = displayed_title, outer = TRUE, line = 0.5, cex.main = 12 / par("ps"))
  title(xlab = if (box_horizontal) displayed_axis else "",
        ylab = if (box_horizontal) "" else displayed_axis,
        cex.lab = 10 / par("ps"), line = if (box_horizontal) 2.5 + 0.4 * (lines(displayed_axis) - 1) else 2.5)
  side <- if (box_horizontal) 1L else 2L
  ticks <- axTicks(side)
  interval <- sd_box_setting("valueInterval", NULL)
  first <- sd_box_setting("valueFirstTick", NULL)
  if (length(interval) == 1L && is.finite(interval) && interval > 0 &&
      length(first) == 1L && is.finite(first)) {
    indices <- c(ceiling((limits[1] - first) / interval - 1e-10),
                 floor((limits[2] - first) / interval + 1e-10))
    if (diff(indices) >= 0 && diff(indices) <= 10000)
      ticks <- first + seq(indices[1], indices[2]) * interval
  } else if (scale == 1L) {
    powers <- c(ceiling(log2(limits[1])), floor(log2(limits[2])))
    if (powers[2] >= powers[1]) ticks <- 2^seq(powers[1], powers[2])
  }
  if (sd_box_setting("valueGrid", FALSE)) {
    style <- sd_box_setting("valueGridStyle", 0L)
    if (box_horizontal) abline(v = ticks, col = "grey80", lty = if (style == 4L) "311111" else style + 1L) else
      abline(h = ticks, col = "grey80", lty = if (style == 4L) "311111" else style + 1L)
  }
  axis(side, at = ticks, labels = format(ticks, trim = TRUE, drop0trailing = TRUE), las = 1, cex.axis = 9 / par("ps"))
  axis(if (box_horizontal) 2 else 1, at = positions, labels = displayed_names,
       las = 1, tick = FALSE, cex.axis = 9 / par("ps"))
  marker <- sd_box_setting("valueMarker", NULL)
  if (length(marker) == 1L && is.finite(marker) && (!logarithmic || marker > 0)) {
    if (box_horizontal) abline(v = marker) else abline(h = marker)
  }
  if (sd_box_setting("boxAxes", FALSE)) box()
  # These marks distinguish the selected fence classes and optional second centre.
  point <- function(value, at, ...) {
    if (box_horizontal) points(value, rep(at, length(value)), ...) else points(rep(at, length(value)), value, ...)
  }
  for (i in seq_len(k)) {
    s <- box_summaries[[i]]; at <- positions[i]
    point(s$hollow, at, pch = 1)
    point(s$filled, at, pch = 16)
    if (box_mark_mean_median) point(s$other, at, pch = 4)
    if (s$centile) {
      if (box_horizontal) segments(s$inner, at - 0.1, s$inner, at + 0.1, lty = 3) else
        segments(at - 0.1, s$inner, at + 0.1, s$inner, lty = 3)
    }
  }
}
sd_box_draw()

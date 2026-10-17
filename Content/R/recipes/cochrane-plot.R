# StatsDirect recipe: one selected forest (Cochrane) plot.
# hand-edited: named optional inputs and the saved linear or logarithmic chart options.
# data: effect = odds, lower = lci, upper = uci, weights = gn, pooling = pg, studies = title
# settings: chart = chartSettings

forest_n <- length(effect)
if (!forest_n || length(lower) != forest_n || length(upper) != forest_n)
  stop("Select equally long effect, lower-limit and upper-limit columns.")
if (is.null(weights)) weights <- rep(10, forest_n)
if (is.null(pooling)) pooling <- rep(0, forest_n)
if (length(weights) != forest_n || length(pooling) != forest_n) stop("The weight and pooling columns must match the effects.")
forest_labels <- sd_chart_strings(sd_chart_get("forestTitles", studies))
if (length(forest_labels) != forest_n) forest_labels <- paste("stratum", seq_len(forest_n))
swap <- is.finite(lower) & is.finite(upper) & lower > upper
temp <- lower[swap]; lower[swap] <- upper[swap]; upper[swap] <- temp
lower[is.na(lower)] <- -Inf; upper[is.na(upper)] <- Inf
forest_rows <- data.frame(effect = effect, lower = lower, upper = upper, weight = weights,
                          pooling = pooling, label = forest_labels, stringsAsFactors = FALSE)
forest_rows <- forest_rows[is.finite(forest_rows$effect), , drop = FALSE]
if (!nrow(forest_rows)) stop("The selected forest plot contains no finite effects.")
forest_rows$y <- rev(seq_len(nrow(forest_rows)))
forest_log <- isTRUE(sd_chart_get("x", list())$scale %in% c(1L, 2L))
if (forest_log && any(forest_rows$effect <= 0)) stop("A logarithmic forest plot requires positive effects.")
forest_decimals <- as.integer(sd_chart_get("effectDecimals", 2L))
if (length(forest_decimals) != 1L || is.na(forest_decimals) || forest_decimals < 0 || forest_decimals > 12) forest_decimals <- 2L
forest_format <- function(x) vapply(x, function(value) {
  if (is.infinite(value)) return(if (value < 0) "-Inf" else "Inf")
  if (value != 0 && abs(value) < 10^-forest_decimals) {
    parts <- strsplit(formatC(value, digits = max(1L, forest_decimals - 1L), format = "e"), "e", fixed = TRUE)[[1L]]
    mantissa <- sub("0+$", "", parts[1L])
    if (endsWith(mantissa, ".")) mantissa <- paste0(mantissa, "0")
    return(paste0(mantissa, "E", as.integer(parts[2L])))
  }
  formatC(value, digits = forest_decimals, format = "f")
}, character(1))
forest_right_labels <- paste0(forest_format(forest_rows$effect), " (",
  forest_format(if (forest_log) pmax(0, forest_rows$lower) else forest_rows$lower), ", ", forest_format(forest_rows$upper), ")")
forest_range <- unlist(forest_rows[c("effect", "lower", "upper")], use.names = FALSE)
forest_range <- forest_range[is.finite(forest_range) & (!forest_log | forest_range > 0)]
if (!forest_log && min(forest_range) <= 0) forest_range <- c(0, forest_range)
forest_before_family <- par("family") # Open a lazy device before choosing its supported font family.
forest_font <- sd_chart_font("axisLabelFont", 10)
par(family = forest_font$family)
forest_right_width <- max(strwidth(forest_right_labels, units = "inches", cex = forest_font$size / par("ps"), font = forest_font$font)) + .25
par(family = forest_before_family)
forest_limits <- sd_chart_frame(range(forest_range), c(.5, nrow(forest_rows) + .5), "Forest plot", "Summary statistic", "",
                                y_axis = FALSE, category_labels = forest_rows$label, right_margin_inches = forest_right_width)
sd_chart_axis(2L, at = forest_rows$y, labels = forest_rows$label, tick = FALSE)
forest_max_weight <- max(forest_rows$weight[forest_rows$pooling == 0 & is.finite(forest_rows$weight) & forest_rows$weight >= 0], 0)
for (i in seq_len(nrow(forest_rows))) {
  s <- forest_rows[i, ]; pooled <- is.finite(s$pooling) && s$pooling != 0
  marker <- sd_chart_marker(if (pooled) 2L else 1L)
  visible_x <- max(forest_limits$xlim[1L], min(forest_limits$xlim[2L], s$effect))
  left <- max(forest_limits$xlim[1L], s$lower); right <- min(forest_limits$xlim[2L], s$upper)
  if (left <= right) {
    if (!pooled) {
      fraction <- if (forest_max_weight > 0 && is.finite(s$weight) && s$weight >= 0) sqrt(s$weight / forest_max_weight) else 0
      row_height <- abs(diff(grconvertY(c(s$y - .5, s$y + .5), "user", "inches")))
      marker$cex <- (.5 + row_height * 72 * fraction * .7 / 6)
    } else marker$cex <- abs(diff(grconvertY(c(s$y - .33, s$y + .33), "user", "inches"))) * 72 / 6
    sd_chart_points(visible_x, s$y, marker)
    segments(left, s$y, right, s$y, col = marker$lineColor, lwd = marker$lwd, lty = marker$lty)
    arrow <- function(x, direction) {
      xx <- grconvertX(x, "user", "inches"); yy <- grconvertY(s$y, "user", "inches")
      segments(grconvertX(xx + direction * .06, "inches", "user"), grconvertY(yy + .04, "inches", "user"), x, s$y, col = marker$lineColor, lwd = marker$lwd)
      segments(grconvertX(xx + direction * .06, "inches", "user"), grconvertY(yy - .04, "inches", "user"), x, s$y, col = marker$lineColor, lwd = marker$lwd)
    }
    if (s$lower < forest_limits$xlim[1L]) arrow(left, 1)
    if (s$upper > forest_limits$xlim[2L]) arrow(right, -1)
    if (!pooled && isTRUE(sd_chart_get("markCentres", TRUE))) points(visible_x, s$y, pch = 16, cex = .3, col = marker$lineColor)
    if (pooled && s$pooling < 0) segments(visible_x, s$y + .33, visible_x, nrow(forest_rows), lty = 2, col = marker$lineColor)
  }
}
if (!forest_log && min(forest_rows$lower) <= 0 && is.null(sd_chart_get("x", list())$marker)) abline(v = 0)
forest_label_x <- grconvertX(grconvertX(forest_limits$xlim[2L], "user", "inches") + .1, "inches", "user")
text(forest_label_x, forest_rows$y, labels = forest_right_labels, adj = c(0, .5), xpd = NA,
     family = forest_font$family, font = forest_font$font, cex = forest_font$size / par("ps"))
cat(paste(forest_rows$label, forest_right_labels), sep = "\n")
sd_chart_finish()

# StatsDirect recipe: one control chart for the selected observations and options.
# hand-edited: replay the selected chart data and final options instead of the help illustration.
# data: process_columns... = Y, sequence_columns... = X
# settings: chart = chartSettings

if (length(process_columns) != 1L || length(sequence_columns) != 1L)
  stop("Select one process column and one sequence column.")
process <- process_columns[[1L]]
sequence <- sequence_columns[[1L]]
if (length(process) != length(sequence))
  stop("Select process and sequence columns with the same number of rows.")
control_ok <- is.finite(process) & is.finite(sequence)
control_x <- sequence[control_ok]
control_y <- process[control_ok]
if (!length(control_y)) stop("The selected columns contain no complete numeric observations.")
# Sequence values remain numeric, including worksheet OLE dates. The saved date
# axis formats its numeric ticks; converting the observations would shift them.
control_mean <- mean(control_y)
control_sd <- if (length(control_y) > 1L) sd(control_y) else NA_real_
control_original_mean <- control_mean
control_original_sd <- control_sd
control_fit_n <- as.integer(sd_chart_get("observationsToUse", length(control_y)))
if (length(control_fit_n) != 1L || is.na(control_fit_n) || control_fit_n < 1L)
  control_fit_n <- length(control_y)
control_fit_n <- min(control_fit_n, length(control_y))
control_user_moments <- isTRUE(sd_chart_get("hasUserSpecifiedMeanAndSD", FALSE))
control_custom_limits <- isTRUE(sd_chart_get("hasUserSpecifiedLimits", FALSE))
if (control_user_moments) {
  control_mean <- sd_chart_get("userSpecifiedMean", control_mean)
  control_sd <- sd_chart_get("userSpecifiedSD", control_sd)
  if (length(control_mean) != 1L || !is.finite(control_mean) ||
      length(control_sd) != 1L || !is.finite(control_sd) || control_sd < 0)
    stop("The specified process mean and SD must be finite, with a non-negative SD.")
} else if (!control_custom_limits && control_fit_n != length(control_y)) {
  control_mean <- mean(control_y[seq_len(control_fit_n)])
  control_sd <- if (control_fit_n > 1L) sd(control_y[seq_len(control_fit_n)]) else NA_real_
}
control_colour <- isTRUE(sd_chart_get("useColour", TRUE))
control_bands <- numeric()
control_band_names <- character()
control_colors <- character()
control_context <- ""
control_add_band <- function(value, name, colour) {
  control_bands <<- c(control_bands, value)
  control_band_names <<- c(control_band_names, name)
  control_colors <<- c(control_colors, if (control_colour) colour else "black")
}
if (control_custom_limits) {
  limits <- c(sd_chart_get("upperWarningLimit", NA_real_), sd_chart_get("lowerWarningLimit", NA_real_),
              sd_chart_get("upperControlLimit", NA_real_), sd_chart_get("lowerControlLimit", NA_real_))
  if (length(limits) != 4L || any(!is.finite(limits)))
    stop("All four specified warning and control limits must be finite.")
  control_bands <- limits
  control_band_names <- c("warn", "warn", "ctrl", "ctrl")
  control_colors <- if (control_colour) c("black", "black", "red", "red") else rep("black", 4L)
  control_context <- "External:"
} else {
  if (isTRUE(sd_chart_get("useMean", TRUE))) {
    control_add_band(control_mean, "mean", "black")
    if (!control_user_moments && control_fit_n != length(control_y))
      control_context <- paste("On first", control_fit_n, "points:")
    else if (control_user_moments && !identical(c(control_mean, control_sd), c(control_original_mean, control_original_sd)))
      control_context <- "External:"
  }
  if (is.finite(control_sd))
    for (k in 1:3) if (isTRUE(sd_chart_get(paste0("use", k, "SD"), TRUE))) {
      colour <- c("green", "black", "red")[k]
      control_add_band(control_mean + k * control_sd, paste0("+", k, " SD"), colour)
      control_add_band(control_mean - k * control_sd, paste0("-", k, " SD"), colour)
    }
}
control_digits <- as.integer(sd_chart_get("rightHandDecimalPlaces", 3L))
if (length(control_digits) != 1L || is.na(control_digits)) control_digits <- 3L
control_digits <- max(0L, min(15L, control_digits))
control_band_labels <- paste0(formatC(round(control_bands, control_digits), digits = control_digits,
                                     format = "f", drop0trailing = TRUE), " (", control_band_names, ")")
control_old_family <- par("family")
control_font <- sd_chart_font("legendFont", 10)
par(family = control_font$family)
control_right_margin <- if (length(control_band_labels) || nzchar(control_context))
  max(strwidth(c(control_band_labels, control_context), units = "inches",
               cex = control_font$size / par("ps"), font = control_font$font)) + 0.25 else 0
par(family = control_old_family)
control_extent <- if (control_custom_limits) control_bands else
  if (is.finite(control_sd)) control_mean + c(-3, 3) * control_sd else control_mean
sd_chart_frame(range(control_x), range(c(control_y, control_extent)),
               default_title = "Control chart", xlab = names(sequence_columns)[1L], ylab = names(process_columns)[1L],
               right_margin_inches = control_right_margin)
control_order <- order(control_x, -control_y)
control_path_x <- control_x[control_order]
control_path_y <- control_y[control_order]
control_marker <- sd_chart_marker(1L)
lines(control_path_x, control_path_y, col = control_marker$lineColor, lwd = control_marker$lwd, lty = 1)
if (length(control_bands)) {
  abline(h = control_bands, col = control_colors)
  text(par("usr")[2L], control_bands, labels = control_band_labels, pos = 4, xpd = NA,
       family = control_font$family, cex = control_font$size / par("ps"), font = control_font$font)
}
if (nzchar(control_context))
  text(par("usr")[2L], par("usr")[4L], labels = control_context, pos = 4, xpd = NA,
       family = control_font$family, cex = control_font$size / par("ps"), font = control_font$font)
cat("Mean =", format(control_mean, digits = 15), " SD =", format(control_sd, digits = 15),
    " n =", length(control_y), "\n")
cat(control_band_labels, sep = "\n")
sd_chart_finish()

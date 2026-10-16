# StatsDirect recipe: one ladder chart for the selected paired columns.
# hand-edited: replay the selected chart data and final options instead of the help illustration.
# data: paired... = data
# settings: chart = chartSettings

if (!is.list(paired) || length(paired) != 2L || length(paired[[1L]]) != length(paired[[2L]]))
  stop("Select two numeric columns with the same number of rows.")
ladder_labels <- as.character(unlist(sd_chart_get("seriesTitles", names(paired)), use.names = FALSE))
if (length(ladder_labels) != 2L) ladder_labels <- names(paired)
if (is.null(ladder_labels)) ladder_labels <- c("First", "Second")
ladder_ok <- is.finite(paired[[1L]]) & is.finite(paired[[2L]])
if (!any(ladder_ok)) stop("The selected columns contain no complete numeric pairs.")
ladder_before <- paired[[1L]][ladder_ok]
ladder_after <- paired[[2L]][ladder_ok]
sd_chart_frame(c(0, 1), range(ladder_before, ladder_after), default_title = "Ladder plot",
               xlab = "", ylab = "", x_axis = FALSE)
sd_chart_axis(1, at = c(0.25, 0.75), labels = ladder_labels)
ladder_left_marker <- sd_chart_marker(1L)
ladder_right_marker <- sd_chart_marker(2L)
# Native ladder rungs use the first marker's line width/style and are always black.
segments(0.25, ladder_before, 0.75, ladder_after, col = "black",
         lwd = ladder_left_marker$lwd, lty = ladder_left_marker$lty)
sd_chart_points(rep(0.25, length(ladder_before)), ladder_before, ladder_left_marker)
sd_chart_points(rep(0.75, length(ladder_after)), ladder_after, ladder_right_marker)

ladder_difference <- ladder_before - ladder_after
cat("Ladder plot of", ladder_labels[1L], "to", ladder_labels[2L], "\n")
cat("Pairs plotted =", length(ladder_difference), "\n")
cat("First exceeds second in", sum(ladder_difference > 0), "of", length(ladder_difference),
    "pairs, is smaller in", sum(ladder_difference < 0), "and is unchanged in",
    sum(ladder_difference == 0), "\n")
cat("Mean of differences =", formatC(mean(ladder_difference), digits = 6, format = "f",
                                     drop0trailing = TRUE), "\n")
sd_chart_finish()

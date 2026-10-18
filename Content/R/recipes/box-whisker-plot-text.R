# StatsDirect recipe: Box and whisker plot drawn as text, as the help shows it in R.
# From the help's R code (graphics/box_whisker_text.htm); the data and settings above come from the run.
# data: groups...
# settings: box_settings = boxWhisker

# Box and whisker plot (text-based): the illustration in the StatsDirect help (the
# fitness scores of two groups of boys, Conover 1999, p. 218; the test workbook's
# Nonparametric worksheet columns Town Boys and Farm Boys) in R

# StatsDirect draws the median and the quartiles as its descriptive statistics
# define them: the p(n+1)th ordered value, interpolating between neighbours. That
# is type 6 of quantile(). The optional Tukey method uses R's hinges instead.
tukey <- !is.null(box_settings) && isTRUE(box_settings$method == 7L)
use_inner <- !tukey || isTRUE(box_settings$innerFence)
use_outer <- !tukey || isTRUE(box_settings$outerFence)
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
five <- function(x, name) {
  if (tukey) {
    x <- x[!is.na(x)]
    if (!length(x) || any(!is.finite(x))) stop("Select finite numeric observations.")
  }
  q <- if (tukey) fivenum(x)[2:4] else quantile(x, c(0.25, 0.5, 0.75), type = 6, names = FALSE)
  cat(sprintf("%s (n = %d): min = %s, LQ = %s, median = %s, UQ = %s, max = %s\n",
              name, length(x), six(min(x)), six(q[1]), six(q[2]), six(q[3]),
              six(max(x))))
  # The fences lie 1.5 (inner) and 3 (outer) interquartile ranges below the lower
  # and above the upper quartile. The whiskers run to the minimum and maximum
  # unless a value lies beyond a fence: then the whisker stops at the innermost
  # fence that a value lies beyond, and the values beyond it are plotted as
  # points, "o" beyond the inner fence and "." beyond the outer fence.
  iqr <- q[3] - q[1]
  inner <- q[c(1, 3)] + c(-1.5, 1.5) * iqr
  outer <- q[c(1, 3)] + c(-3, 3) * iqr
  if (tukey) {
    inner <- if (use_inner) pmax(min(x), pmin(max(x), inner)) else q[c(1, 3)]
    outer <- if (use_outer) pmax(min(x), pmin(max(x), outer)) else range(x)
  }
  cat("  inner fences =", six(inner[1]), "to", six(inner[2]), "\n")
  cat("  outer fences =", six(outer[1]), "to", six(outer[2]), "\n")
  active <- if (use_inner) inner else if (use_outer) outer else range(x)
  low <- if (min(x) < active[1]) active[1] else min(x)
  high <- if (max(x) > active[2]) active[2] else max(x)
  out <- x[x < active[1] | x > active[2]]
  list(stats = c(low, q, high), out = out,
       pch = ifelse(use_outer & (out < outer[1] | out > outer[2]), 20, 1))
}
b <- mapply(five, groups, names(groups), SIMPLIFY = FALSE)

# The plot: the box from the lower to the upper quartile with the median marked,
# the whiskers as above. bxp() draws a box plot from given statistics; the
# program lists the first column selected at the top, so Town Boys is drawn at 2.
z <- list(stats = sapply(b, `[[`, "stats"), n = lengths(groups),
          names = names(groups))
bxp(z, at = rev(seq_along(groups)), horizontal = TRUE,
    main = if (tukey && !is.null(box_settings$title)) box_settings$title else "Box & whisker plot",
    xlab = if (tukey && !is.null(box_settings$axisTitle)) box_settings$axisTitle else
      "min < LQ < median > UQ > max, fences (1.5 & 3.0 IQR)", las = 1,
    medlty = "blank", boxwex = 0.5)
points(z$stats[3, ], rev(seq_along(groups)), pch = 8)
if (tukey && isTRUE(box_settings$markMeanAndMedian))
  points(vapply(groups, mean, numeric(1), na.rm = TRUE), rev(seq_along(groups)), pch = 4)
# Any values beyond the fences: a circle beyond the inner, a dot beyond the outer
for (i in seq_along(groups)) {
  points(b[[i]]$out, rep(length(groups) + 1 - i, length(b[[i]]$out)), pch = b[[i]]$pch)
}

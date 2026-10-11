# StatsDirect recipe: Forest (Cochrane) plot, as the help shows it in R.
# From the help's R code (graphics/forest.htm); the data and settings above come from the run.
# data: or, lower, upper, number, pool, study

if (is.null(number)) number <- rep(1, length(or))
if (is.null(pool)) pool <- rep(0, length(or))
if (is.null(study)) study <- paste("Study", seq_along(or))
# Forest (Cochrane) plot: the StatsDirect help illustration (the odds ratio of death
# after heart attack in each of the seven trials of aspirin given by Fleiss (1993),
# with its 95% confidence limits and the size of the trial, and a pooled odds ratio
# for all seven; the test workbook's Graphics worksheet columns Odds Ratio, LCI, UCI,
# Number, Pool and Study) in R
k <- length(or)

# Limits entered the wrong way round are swapped, as StatsDirect swaps them
lo <- pmin(lower, upper)
hi <- pmax(lower, upper)
lower <- lo
upper <- hi

# The labels StatsDirect writes to the right of each row: the estimate and its limits
# to 2 decimal places (3 or 4 when the smallest value is below 0.01 or 0.001)
label <- sprintf("%.2f (%.2f, %.2f)", or, lower, upper)
cat(paste(study, label), sep = "\n")

# Base R has no forest plot function, so the chart is drawn from its parts. The rows
# follow the order of the columns from the top down; the axis is logarithmic because
# the summary statistic is a ratio (StatsDirect chooses a log scale when the column's
# title contains "ratio", and a linear scale otherwise).
y <- rev(seq_len(k))
op <- par(mar = c(5, 5, 4, 9))
plot(or, y, type = "n", log = "x", xlim = range(lower, upper), ylim = c(0.5, k + 0.5),
     yaxt = "n", ylab = "", xlab = "Odds Ratio (95% confidence interval)",
     main = "Forest plot", bty = "n")
mtext(study, side = 2, at = y, las = 1, line = 0.5)
mtext(label, side = 4, at = y, las = 1, line = 0.5)

# Each study: a grey square whose side is proportional to the square root of its
# weight relative to the heaviest study (plus a small minimum), the confidence
# interval as a line through it, and a dot at the estimate
s <- pool == 0
w <- number[s] / max(number[s])
points(or[s], y[s], pch = 15, col = "grey", cex = 0.5 + 3 * sqrt(w))
segments(lower[s], y[s], upper[s], y[s])
points(or[s], y[s], pch = 16, cex = 0.5)

# The pooled estimate: a grey diamond with its confidence interval as a line through
# it and, for the overall pool (indicator below 0), a dashed line rising from the top
# of the diamond to the first row. StatsDirect draws no line of no effect unless one
# is set as a marker line in the chart options; abline(v = 1) would add it.
p <- pool != 0
points(or[p], y[p], pch = 18, col = "grey", cex = 4)
segments(lower[p], y[p], upper[p], y[p])
segments(or[pool < 0], y[pool < 0] + 0.35, or[pool < 0], k, lty = 2)
par(op)
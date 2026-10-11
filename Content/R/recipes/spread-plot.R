# StatsDirect recipe: Spread plot, as the help shows it in R.
# From the help's R code (graphics/spread.htm); the data and settings above come from the run.
# data: groups...

# Spread plot: the StatsDirect help illustration (Aziz et al. 1996, sperm deformity
# index of men whose partners conceived and of men whose partners did not; the test
# workbook's Graphics worksheet columns SDI conceived and SDI not conceived) in R

# A spread plot is a one dimensional scatter of each group's values, with values
# that fall together stacked side by side so that a concentration of data shows as
# a broad band. R's stripchart draws one; method = "stack" stacks equal values.
# The groups are reversed so that the first is at the top, as StatsDirect draws it.
op <- par(mar = c(4, 9, 3, 1))
stripchart(rev(groups), method = "stack", pch = 1, las = 1, main = "Spread plot")

# The summary of each group that the illustration states
for (g in names(groups)) {
  x <- groups[[g]]
  cat(g, ": n = ", length(x), ", range ", min(x), " to ", max(x), ", median ",
      median(x), "\n", sep = "")
}

# StatsDirect stacks values that are close, not only equal ones: it sorts each group,
# starts a column at the smallest value not yet drawn and adds to that column every
# following value within the width of one plot point of the column's first value.
# Its default marker is 12 pixels across and the scale axis of this plot is 814
# pixels long, so the width is 12/814 of the axis range, and the axis runs between
# the round numbers that enclose the data (100 to 240 here): a column holds values
# within about two units of its first.
xlim <- range(pretty(unlist(groups)))
width <- diff(xlim) * 12 / 814
columns <- function(x) {
  x <- sort(x)
  at <- numeric(0)
  count <- integer(0)
  i <- 1
  while (i <= length(x)) {
    j <- i
    while (j < length(x) && x[j + 1] - x[i] <= width) j <- j + 1
    at <- c(at, x[i])
    count <- c(count, j - i + 1)
    i <- j + 1
  }
  data.frame(at = at, count = count)
}
stacks <- lapply(groups, columns)
for (g in names(groups)) {
  s <- stacks[[g]]
  b <- which.max(s$count)
  cat(g, ": broadest band ", s$count[b], " values at ", s$at[b], "\n", sep = "")
}

# The plot as StatsDirect draws it: the scale axis across, the first group at the
# top, each column of markers centred on its group's line with the markers a fixed
# distance apart, squeezed only when the tallest column would overflow its band,
# and with the title given to the illustration
k <- length(groups)
marker <- 0.04
plot(NA, xlim = xlim, ylim = c(0, k), xaxs = "i", yaxs = "i", yaxt = "n", bty = "l",
     xlab = "", ylab = "", main = "Sperm Deformity Index and Conception")
axis(2, at = k - seq_len(k) + 0.5, labels = names(groups), las = 1, tick = FALSE)
for (g in seq_len(k)) {
  s <- stacks[[g]]
  step <- min(marker, (1 - marker) / max(s$count))
  centre <- k - g + 0.5
  for (i in seq_len(nrow(s))) {
    y <- centre + step * (seq_len(s$count[i]) - (s$count[i] + 1) / 2)
    points(rep(s$at[i], s$count[i]), y, pch = 1)
  }
}
par(op)

# The men whose partners did not conceive form a dense band between about 125 and
# 160; the values of the men whose partners conceived are spread more widely and
# lie mostly higher. The plot shows the two distributions without summarising them.
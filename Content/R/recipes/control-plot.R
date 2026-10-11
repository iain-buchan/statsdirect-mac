# StatsDirect recipe: Control chart, as the help shows it in R.
# From the help's R code (graphics/control.htm); the data and settings above come from the run.
# data: process = Y, date = X

date <- if (is.numeric(date)) as.Date(date, origin = "1899-12-30") else as.Date(date)   # a worksheet date is a count of days from 1900
# Control chart: the StatsDirect help illustration (a process indicator recorded on
# 19 dates in 1999; the test workbook's Graphics worksheet columns Process and Date)
# in R

# The bands are the mean and 1, 2 and 3 standard deviations either side of it, with
# the mean and sd calculated from all of the process data (StatsDirect's default
# option); sd() divides by n - 1, as StatsDirect does.
m <- mean(process)
s <- sd(process)
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
cat("Mean =", six(m), "  SD =", six(s), "  n =", length(process), "\n")

# The labels StatsDirect writes at the right hand end of each band, to its default
# 3 decimal places
k <- c(0, 1, -1, 2, -2, 3, -3)
band <- m + k * s
label <- paste0(formatC(band, digits = 3, format = "f", drop0trailing = TRUE), " (",
                c("mean", "+1 SD", "-1 SD", "+2 SD", "-2 SD", "+3 SD", "-3 SD"), ")")
cat(label, sep = "\n")

# The chart: the process values joined in date order, with the mean (black), 1 SD
# (green), 2 SD (black) and 3 SD (red) bands labelled beyond the right end of the
# axis. StatsDirect labels the date axis at calendar intervals to suit the span of
# the data, here the quarters that fall within it.
op <- par(mar = c(5, 4, 4, 7))
plot(date, process, type = "l", col = "steelblue", xaxt = "n", xlab = "Date",
     ylab = "Process", main = "Control chart", ylim = range(process, band))
axis.Date(1, at = seq(as.Date("1999-04-01"), by = "quarter", length.out = 3),
          format = "%d/%m/%Y")
abline(h = band, col = c("black", "green", "green", "black", "black", "red", "red"))
text(par("usr")[2], band, label, pos = 4, xpd = NA, cex = 0.8)
par(op)
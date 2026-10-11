# StatsDirect recipe: Bar or column plot of values with their labels, as the help shows it in R.
# From the help's R code (graphics/bar.htm); the data and settings above come from the run.
# data: group = labels, series... = values

values <- do.call(rbind, series)
# Bar plot: the StatsDirect help illustration (the ABO blood group distribution of
# three ethnic groups; the test workbook's Graphics worksheet columns Blood Group,
# White British, Native American and Aborigine) in R

# One row for each worksheet column of values, one column for each bar label:
# barplot() draws a matrix as one group of bars per column, labelled by the column
# names, side by side when beside = TRUE and otherwise stacked.
colnames(values) <- group
shade <- c("steelblue", "firebrick", "olivedrab", "slateblue")
op <- par(mar = c(7, 4, 3, 1))
bottom_legend <- function(labels, fill) {
  legend("bottom", legend = labels, fill = fill, horiz = TRUE, bty = "n",
         inset = c(0, -0.2), xpd = TRUE)
}

# Clustered (StatsDirect's default type of plot): a bar for each column of values at
# each label, the columns' titles in a legend below the chart. StatsDirect titles
# the chart "Bar chart" until you type a title in the chart options.
barplot(values, beside = TRUE, col = rep_len(shade, nrow(values)), main = "Bar chart")
bottom_legend(rownames(values), rep_len(shade, nrow(values)))

# Stacked: StatsDirect turns the table round, one stack for each column of values
# with a segment for each label, so the height of a stack is its column's total
barplot(t(values), col = shade, main = "Bar chart")
bottom_legend(group, shade)

# 100% stacked, the illustration: each stack is scaled to the total of its column
# of values (missing values left out), so its segments are percentages of the total
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pct <- 100 * values / rowSums(values, na.rm = TRUE)
barplot(t(pct), col = shade, ylim = c(0, 100), ylab = "Percent",
        main = "ABO Blood Grouping by Ethnicity")
bottom_legend(group, shade)
for (i in rownames(pct)) {
  cat(i, ": ", paste0(group, " ", six(pct[i, ]), "%", collapse = ", "), "\n", sep = "")
}

# Bar or Column (Frequency) counts the categories of a column of raw data, here the
# Other worksheet's column Sex; for these labels table() sorts the categories as
# StatsDirect does (StatsDirect sorts numeric labels by value and text labels with
# capitals first; R sorts by the locale's collation). A
# plot of one column of values names its Y axis after that column.
sex <- c("M", "M", "M", "F", "M", "M", "M", "M", "F", "F", "F", "M")
counts <- table(sex)
barplot(counts, col = shade[1], ylab = "Sex", main = "Bar chart")
cat("Sex counts: ", paste(names(counts), counts, collapse = ", "), "\n", sep = "")
par(op)
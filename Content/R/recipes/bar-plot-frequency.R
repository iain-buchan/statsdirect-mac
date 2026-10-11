# StatsDirect recipe: Bar plot of the frequencies of categorical values, after the help's bar plot in R.
# From the help's R code (graphics/bar.htm); the data above come from the run.
# data: values... = rawValues
# hand-edited: the frequencies are counted from the columns of values, where the help's bar plot takes counts

# Each column holds categorical values; the bars are the counts of each category, side by side
# for the columns, as barplot() draws a matrix with beside = TRUE
levels <- sort(unique(unlist(values)))
counts <- sapply(values, function(v) table(factor(v, levels = levels)))
print(counts)
op <- par(mar = c(7, 4, 3, 1))
barplot(t(counts), beside = TRUE, names.arg = levels, legend.text = names(values),
        args.legend = list(x = "top", bty = "n", horiz = TRUE), main = "Bar plot of frequencies")
par(op)

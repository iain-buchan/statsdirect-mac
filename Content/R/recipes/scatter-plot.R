# StatsDirect recipe: Scatter, as the help shows it in R.
# From the help's R code (graphics/scatter.htm); the data and settings above come from the run.
# data: pimax, age

# Scatter plot: the StatsDirect help illustration (PImax, the maximal static
# inspiratory pressure, against age in 25 patients with cystic fibrosis, Altman 1991;
# the test workbook's Graphics worksheet columns "PImax (cm H2O)" and "Subject's Age
# (years)") in R

# StatsDirect draws one open circle for each row of the two columns, scales both axes
# to the data, titles the axes with the column titles and the chart "Scatter plot".
# A row with a missing value in either column is left out, as plot() leaves out a
# pair that holds an NA. R's default marker (pch = 1) is the same open circle.
plot(age, pimax, xlab = "Subject's Age (years)", ylab = "PImax (cm H2O)",
     main = "Scatter plot")

# What the plot shows, in words
cat("Scatter plot of PImax (cm H2O) against Subject's Age (years):", length(age),
    "points\n")
cat("Age from", min(age), "to", max(age), "years; PImax from", min(pimax), "to",
    max(pimax), "cm H2O\n")

# StatsDirect's option to join the markers with lines (the Line plot) first sorts the
# points by X, so the segments run left to right whatever the row order; in R sort
# the rows the same way before asking for lines with type = "b":
# o <- order(age, -pimax)
# plot(age[o], pimax[o], type = "b", xlab = "Subject's Age (years)",
#      ylab = "PImax (cm H2O)", main = "Line plot")
# A further series goes on the same axes with points(), given a different marker
# (pch) and a legend, as StatsDirect does when more than one series is plotted.
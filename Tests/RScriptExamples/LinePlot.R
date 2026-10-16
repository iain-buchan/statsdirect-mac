# Independent numerical reference for the selected LinePlot worked example.
# Every plotted value is checked; this file does not call the application recipe.
emit <- function(x) cat(formatC(as.double(x), digits = 8, format = "f"), "\n")
pimax <- c(80, 85, 110, 95, 95, 100, 45, 95, 130, 75, 80, 70, 80, 100, 120, 110, 125, 75, 100, 40, 75, 110, 150, 75, 95)
age <- c(7, 7, 8, 8, 8, 9, 11, 12, 12, 13, 13, 14, 14, 15, 16, 17, 17, 17, 17, 19, 19, 20, 23, 23, 23)
rows <- order(age, -pimax)
emit(1)
emit(c(length(rows), age[rows], pimax[rows]))

# Independent numerical reference for the selected BarPlot worked example.
# Every plotted value is checked; this file does not call the application recipe.
emit <- function(x) cat(formatC(as.double(x), digits = 8, format = "f"), "\n")
values <- rbind(c(0.41, 0.11, 0.05, 0.43), c(0.1, 0.0, 0.0, 0.9), c(0.1, 0.1, 0.0, 0.8))
emit(c(dim(values), as.vector(values)))

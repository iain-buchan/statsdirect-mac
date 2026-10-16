# Independent numerical reference for the selected ErrorPlot worked example.
# Every plotted value is checked; this file does not call the application recipe.
emit <- function(x) cat(formatC(as.double(x), digits = 8, format = "f"), "\n")
weeks <- c(0, 4, 8, 12, 16, 24, 32, 36, 38, 50)
means <- c(0.246, 0.24, 0.19, 0.173, 0.189, 0.196, 0.216, 0.232, 0.269, 0.275)
sds <- c(0.059,0.044,0.070,0.047,0.048,0.040,0.053,0.056,0.056,0.057)
emit(1)
emit(c(length(weeks), weeks, means, means - sds, means + sds, weeks))

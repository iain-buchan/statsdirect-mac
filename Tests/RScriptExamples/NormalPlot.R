# Independent numerical reference for the selected NormalPlot worked example.
# Every plotted value is checked; this file does not call the application recipe.
emit <- function(x) cat(formatC(as.double(x), digits = 8, format = "f"), "\n")
observed <- c(80, 85, 110, 95, 95, 100, 45, 95, 130, 75, 80, 70, 80, 100, 120, 110, 125, 75, 100, 40, 75, 110, 150, 75, 95)
ranks <- rank(observed, ties.method = "average")
blom <- qnorm((ranks - 3/8) / (length(observed) + 1/4))
scores <- mean(observed) + blom * sqrt(sum((observed - mean(observed))^2) / length(observed))
emit(c(length(observed), ranks, scores, observed))

# Independent numerical reference for the selected PyramidPlot worked example.
# Every plotted value is checked; this file does not call the application recipe.
emit <- function(x) cat(formatC(as.double(x), digits = 8, format = "f"), "\n")
males <- c(1821.6, 2008.3, 2125.9, 2073.4, 2111.5, 2250.8, 2337.6, 2319, 2213.9, 2021.6, 2180.5, 2271.3, 2107.4, 1743, 1479.7, 1354.3, 817.6, 460.4, 210.7)
females <- c(1732.5, 1910, 2026, 1968.4, 2048.2, 2295.1, 2471.6, 2484.3, 2344.2, 2096.5, 2261.7, 2368.3, 2203.8, 1846.3, 1628.3, 1554.6, 1026.4, 666.4, 415.2)
rows <- seq_along(males)
emit(c(length(rows), rows, males, females, 3000))

# Independent numerical reference for the selected LadderPlot worked example.
# Every plotted value is checked; this file does not call the application recipe.
emit <- function(x) cat(formatC(as.double(x), digits = 8, format = "f"), "\n")
before <- c(312, 242, 340, 388, 296, 254, 391, 402, 290)
after <- c(300, 201, 232, 312, 220, 256, 328, 330, 231)
keep <- complete.cases(before, after)
emit(c(sum(keep), before[keep], after[keep], before[keep] - after[keep]))

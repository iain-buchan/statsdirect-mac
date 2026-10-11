# StatsDirect recipe: Unpaired z test of two samples by the normal approximation, after the help's single sample z test in R.
# From the help's R code (parametric_methods/z_normal.htm); the settings above come from the run.
# data: samples... = data
# settings: confidence = gamma
# hand-edited: the two sample form of the help's single sample z test

# The two columns are the two samples. The z statistic compares their means by the normal
# approximation, with the standard error of the difference from each sample's own variance.
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) if (p < 0.0001) "P < 0.0001" else paste("P =", formatC(p, digits = 4, format = "f"))
pct <- paste0(100 * confidence, "%")
x <- samples[[1]][!is.na(samples[[1]])]
y <- samples[[2]][!is.na(samples[[2]])]
cat(names(samples)[1], ": n =", length(x), " mean =", six(mean(x)), " sd =", six(sd(x)), "\n")
cat(names(samples)[2], ": n =", length(y), " mean =", six(mean(y)), " sd =", six(sd(y)), "\n")
d <- mean(x) - mean(y)
se <- sqrt(var(x) / length(x) + var(y) / length(y))
z <- d / se
cat("Difference between means =", six(d), "  standard error =", six(se), "\n")
cat("z =", six(z), "  Two sided", pv(2 * pnorm(-abs(z))), "\n")
cat(pct, "confidence interval for the difference =", six(d - qnorm((1 + confidence) / 2) * se),
    "to", six(d + qnorm((1 + confidence) / 2) * se), "\n")

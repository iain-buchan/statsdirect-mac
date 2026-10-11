# StatsDirect recipe: Linearity of grouped regression (replicates at each level of the predictor), as the help shows it in R.
# From the help's R code (regression_and_correlation/grouped_linearity_replicates.htm); the data and settings above come from the run.
# data: dose = predictor, bd... = outcomes

bd <- lapply(bd, function(v) v[!is.na(v)])   # the groups, without the blanks that pad the shorter columns
# Linearity with replicates of Y: the StatsDirect help example (Armitage and Berry
# 1994, bone density of rats at three log doses of vitamin D; the test workbook's
# columns BD 1_Std, BD 2_Std and BD 3_Std hold the replicates at each dose) in R
x <- rep(dose, lengths(bd))
y <- unlist(bd)

# The test of linearity compares the straight line with the model of a separate
# mean for each dose: R's anova of the two fits gives the deviation from linearity
# (its "Residuals" line is the within dose residual) and the regression line is
# the straight line's own analysis of variance
linear <- lm(y ~ x)
means <- lm(y ~ factor(x))
print(anova(linear, means))
print(anova(linear))

# The report's table to 6 places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
ssreg <- anova(linear)$"Sum Sq"[1]
ssdev <- anova(linear, means)$"Sum of Sq"[2]
sswithin <- anova(means)$"Sum Sq"[2]
dfwithin <- anova(means)$Df[2]
mswithin <- sswithin / dfwithin
cat("Due to regression", six(ssreg), 1, six(ssreg), six(ssreg / mswithin),
    pv(pf(ssreg / mswithin, 1, dfwithin, lower.tail = FALSE)), "\n")
cat("Deviation of x means", six(ssdev), 1, six(ssdev), six(ssdev / mswithin),
    pv(pf(ssdev / mswithin, 1, dfwithin, lower.tail = FALSE)), "\n")
cat("Within x residual", six(sswithin), dfwithin, six(mswithin), "\n")
cat("Total", six(ssreg + ssdev + sswithin), length(y) - 1, "\n")
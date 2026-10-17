# StatsDirect recipe: ANOVA for the original simple regression.
# data: y = y, x = x
# hand-edited: actual parent analysis selected by recorded provenance.

keep <- is.finite(x) & is.finite(y)
x <- x[keep]; y <- y[keep]
fit <- lm(y ~ x)
table <- anova(fit)
regression_anova <- c(reg_sum = table[1L, "Sum Sq"], res_sum = table[2L, "Sum Sq"],
  tot_sum = sum((y - mean(y))^2), reg_df = 1, res_df = df.residual(fit), tot_df = length(y) - 1,
  f = table[1L, "F value"], p = table[1L, "Pr(>F)"], r = summary(fit)$r.squared, mse = summary(fit)$sigma)
print(table)
print(regression_anova)
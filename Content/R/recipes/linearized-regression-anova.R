# StatsDirect recipe: ANOVA on the selected linearized scale.
# data: y = y, x = x
# settings: model = model
# hand-edited: use only the selected transformation.

model <- as.integer(model)
if (length(model) != 1L || is.na(model) || !model %in% 0:2) stop("The saved result has no valid linearized model choice.")
keep <- is.finite(x) & is.finite(y)
x <- x[keep]; y <- y[keep]
if (model %in% 0:1 && any(y <= 0)) stop("The selected model requires positive Y values.")
if (model == 1L && any(x <= 0)) stop("The power model requires positive X values.")
if (model == 2L && (any(x == 0) || any(y == 0))) stop("The hyperbolic model requires nonzero X and Y values.")
y <- if (model == 2L) 1 / y else log(y)
x <- if (model == 0L) x else if (model == 1L) log(x) else 1 / x
keep <- is.finite(x) & is.finite(y)
x <- x[keep]; y <- y[keep]
fit <- lm(y ~ x)
table <- anova(fit)
regression_anova <- c(reg_sum = table[1L, "Sum Sq"], res_sum = table[2L, "Sum Sq"],
  tot_sum = sum((y - mean(y))^2), reg_df = 1, res_df = df.residual(fit), tot_df = length(y) - 1,
  f = table[1L, "F value"], p = table[1L, "Pr(>F)"], r = summary(fit)$r.squared, mse = summary(fit)$sigma)
print(table)
print(regression_anova)
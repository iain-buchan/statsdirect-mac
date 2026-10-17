# StatsDirect recipe: the selected linearized regression model.
# data: kwh = y, size = x
# settings: model = model
# hand-edited: fit only the selected model from its original complete pairs.

model <- as.integer(model)
if (length(model) != 1L || is.na(model) || !model %in% 0:2) stop("The saved linearized regression has no valid model choice.")
keep <- is.finite(kwh) & is.finite(size)
kwh <- kwh[keep]; size <- size[keep]
if (length(kwh) < 3L) stop("At least three complete pairs are needed.")
if (model %in% 0:1 && any(kwh <= 0)) stop("The selected model requires positive Y values.")
if (model == 1L && any(size <= 0)) stop("The power model requires positive X values.")
if (model == 2L && (any(size == 0) || any(kwh == 0))) stop("The hyperbolic model requires nonzero X and Y values.")
transformed_y <- if (model == 2L) 1 / kwh else log(kwh)
transformed_x <- if (model == 0L) size else if (model == 1L) log(size) else 1 / size
fit <- lm(transformed_y ~ transformed_x)
model_name <- c("Exponential", "Geometric / power", "Hyperbolic")[model + 1L]
a <- if (model == 2L) unname(coef(fit)[2L]) else exp(unname(coef(fit)[1L]))
b <- if (model == 2L) unname(coef(fit)[1L]) else unname(coef(fit)[2L])
linearized_result <- c(a = a, b = b, r = cor(transformed_x, transformed_y), se = summary(fit)$sigma)
cat("Selected model:", model_name, "\n")
print(summary(fit))
print(linearized_result)
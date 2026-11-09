# StatsDirect recipe: Logistic regression of grouped counts, as the help shows it in R.
# From the help's R code (regression_and_correlation/logistic.htm); the data and settings above come from the run.
# data: total = total, responders = response, predictors... = predictors, weight = weight
# settings: confidence = gamma, intercept = intercept
# hand-edited: omit incomplete model rows before grouping and all calculations

keep <- complete.cases(responders, total, predictors, weight)
responders <- responders[keep]
predictors <- lapply(predictors, function(x) x[keep])
if (!is.null(total)) total <- total[keep]
if (!is.null(weight)) weight <- weight[keep]

# Individual rows represent one trial; both layouts merge equal covariate
# patterns with the same prior weight, as the native analysis does.
if (is.null(total)) total <- rep(1, length(responders))
# Exact numeric matches keep distinct doubles distinct and retain the first
# occurrence of each predictor/weight pattern (aggregate() formats numeric keys).
sd_group <- do.call(paste, unname(lapply(c(predictors, list(if (is.null(weight)) rep(1, length(responders)) else weight)),
                                       function(v) match(v, unique(v)))))
sd_first <- !duplicated(sd_group)
responders <- as.vector(rowsum(responders, sd_group, reorder = FALSE))
total <- as.vector(rowsum(total, sd_group, reorder = FALSE))
predictors <- lapply(predictors, function(v) v[sd_first])
if (!is.null(weight)) weight <- weight[sd_first]
# Logistic regression: the StatsDirect help example (Altman 1991, hypertension and
# smoking, obesity and snoring in 433 total) in R

# R's standard model for grouped binomial data: responders and non-responders in
# each row. Its residual deviance is the deviance goodness of fit, and the drop
# from the null deviance is the likelihood ratio chi-square for the covariates
# Put model inputs under unique names so a predictor named "weight", "total"
# or "responders" cannot replace a response or a weight in the model frame.
sd_data <- as.data.frame(predictors, optional = TRUE)
sd_own <- tail(make.unique(c(names(sd_data), "responders", "nonresponders", "prior_weight")), 3)
sd_data[sd_own] <- list(responders, total - responders, if (is.null(weight)) rep(1, length(responders)) else weight)
sd_terms <- encodeString(names(predictors), quote = "`")
sd_terms[names(predictors) == "."] <- "I(`.`)" # an actual column, not the formula shorthand
model <- reformulate(sd_terms,
                     response = call("cbind", as.name(sd_own[1]), as.name(sd_own[2])), intercept = intercept)
fit <- eval(bquote(glm(.(model), data = sd_data, family = binomial,
                      weights = .(as.name(sd_own[3])), control = glm.control(maxit = 100))))
# A warm start updates covariance at the fitted values without changing glm's
# rank tolerance (which also depends on its convergence epsilon).
if (fit$converged && !fit$boundary) {
  refit_start <- coef(fit)
  refit_start[is.na(refit_start)] <- 0
  fit <- update(fit, start = refit_start)
}
print(summary(fit))
print(exp(cbind(OR = coef(fit), confint.default(fit, level = confidence))))

# The report's lines to 6 places
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
pv <- function(p) {
  if (is.na(p)) "P = *" else if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
dev <- fit$deviance
lr <- if (intercept) max(0, fit$null.deviance - dev) else NA_real_
cat("Deviance goodness of fit chi-square =", six(dev), " df =", fit$df.residual, " ",
    pv(if (fit$df.residual > 0) pchisq(dev, fit$df.residual, lower.tail = FALSE) else NA_real_), "\n")
df_lr <- fit$df.null - fit$df.residual
cat("Deviance (likelihood ratio) chi-square =", six(lr), " df =", df_lr, " ",
    pv(if (df_lr > 0) pchisq(lr, df_lr, lower.tail = FALSE) else NA_real_), "\n")
s <- summary(fit)$coefficients
position <- match(rownames(s), names(coef(fit)))
lab <- (if (intercept) c("(Intercept)", names(predictors)) else names(predictors))[position]
ci <- confint.default(fit, level = confidence)[rownames(s), , drop = FALSE] # only estimable coefficients
for (i in if (intercept) seq_len(nrow(s))[-1] else seq_len(nrow(s))) {
  cat(lab[i], "odds ratio =", six(exp(s[i, 1])), " (", six(exp(ci[i, 1])), "to",
      six(exp(ci[i, 2])), ")  z =", six(s[i, 3]), " ", pv(s[i, 4]), "\n")
}
slopes <- if (intercept) s[-1, 1] else s[, 1]
cat("logit =", if (intercept) six(s[1, 1]) else "", paste0(ifelse(slopes >= 0, "+", ""), six(slopes), " ", if (intercept) lab[-1] else lab, collapse = " "), "\n")

# The model analysis. The report's log likelihood is the sum over the total of
# log p or log(1 - p) (without the binomial coefficients that R's logLik adds), the
# information criteria are on the deviance scale (deviance + 2k, deviance + k log n
# for the n rows of data), and the two pseudo R-squares are 1 minus the ratio of
# the deviances and 1 minus the ratio of the log likelihoods (McFadden's)
k <- length(coef(fit))
n <- length(total)
p <- fitted(fit)
w <- if (is.null(weight)) 1 else weight   # the prior weights, as the report weights the rows
ll <- sum(w * (responders * log(p) + (total - responders) * log(1 - p)))
p0 <- sum(w * responders) / sum(w * total)
ll0 <- sum(w * (responders * log(p0) + (total - responders) * log(1 - p0)))
cat("Log likelihood with all covariates =", formatC(ll, digits = 4, format = "f"), "\n")
cat("Deviance with all covariates =", six(dev), " df =", fit$df.residual,
    " rank =", fit$rank, "\n")
cat("Akaike information criterion =", six(dev + 2 * k), "\n")
cat("Schwarz information criterion =", six(dev + k * log(n)), "\n")
null_deviance <- if (intercept) fit$null.deviance else NA_real_
r2 <- if (intercept && null_deviance > 0) 1 - dev / null_deviance else NA_real_
r2i <- if (intercept && ll0 != 0) 1 - ll / ll0 else NA_real_
cat("Deviance with no covariates =", six(null_deviance), "\n")
cat("Pseudo (deviance based) R-square =", six(r2), "\n")
cat("Pseudo (McFadden, likelihood ratio index) R-square =", six(r2i), "\n")
pearson <- sum(residuals(fit, type = "pearson")^2)
cat("Pearson chi-square goodness of fit =", six(pearson), " df =", fit$df.residual, " ",
    pv(if (fit$df.residual > 0) pchisq(pearson, fit$df.residual, lower.tail = FALSE) else NA_real_), "\n")
# Hosmer-Lemeshow uses whole covariate patterns. Combine the same predictors
# across different prior weights before assigning frequency groups. Zero weights
# contribute nothing; occupied groups determine the df, with at most ten groups.
wv <- if (is.null(weight)) rep(1, length(total)) else weight
frequency <- total * wv
sd_hl_group <- do.call(paste, unname(lapply(predictors, function(v) match(v, unique(v)))))
sd_hl_first <- !duplicated(sd_hl_group)
sd_hl <- data.frame(total = as.vector(rowsum(frequency, sd_hl_group, reorder = FALSE)),
                    observed = as.vector(rowsum(responders * wv, sd_hl_group, reorder = FALSE)),
                    expected = as.vector(rowsum(p * frequency, sd_hl_group, reorder = FALSE)))
sd_hl_predictors <- lapply(predictors, function(v) v[sd_hl_first])
positive <- sd_hl$total > 0
sd_hl <- sd_hl[positive, , drop = FALSE]
sd_hl_predictors <- lapply(sd_hl_predictors, function(v) v[positive])
sd_hl$p <- sd_hl$expected / sd_hl$total
sd_hl <- sd_hl[do.call(order, unname(c(list(sd_hl$p), sd_hl_predictors))), , drop = FALSE]
ntot <- sum(sd_hl$total)
ndiv <- ntot / 10
ncut <- floor(ndiv)
ncum <- 0
g <- 1L
group <- integer(nrow(sd_hl))
for (i in seq_len(nrow(sd_hl))) {
  if (ncum > 0 && ncum >= ncut && g < 10L) {
    g <- g + 1L
    ncut <- floor(max(ncum + ndiv, g * ndiv))
  }
  group[i] <- g
  ncum <- ncum + sd_hl$total[i]
}
sd_hl_totals <- rowsum(sd_hl[c("total", "observed", "expected")], group, reorder = FALSE)
tot <- sd_hl_totals[, "total"]
obs <- sd_hl_totals[, "observed"]
mpi <- sd_hl_totals[, "expected"]
hl <- if (fit$df.residual > 0) sum((obs - mpi)^2 / (mpi * (1 - mpi / tot))) else NA_real_
hldf <- if (fit$df.residual > 0) nrow(sd_hl_totals) - 2L else 0L
cat("Hosmer-Lemeshow test =", six(hl), " df =", hldf, " ",
    pv(if (hldf > 0 && fit$df.residual > 0) pchisq(hl, hldf, lower.tail = FALSE) else NA_real_), "\n")
cat("Coefficients and standard errors:\n")
for (i in seq_len(nrow(s))) cat(lab[i], six(s[i, 1]), six(s[i, 2]), "\n")

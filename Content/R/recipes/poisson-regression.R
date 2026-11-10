# StatsDirect recipe: Poisson regression of counts with an exposure, as the help shows it in R.
# From the help's R code (regression_and_correlation/poisson.htm); the data and settings above come from the run.
# data: response = response, exposure = exposure, predictors... = predictors, weight = weight
# settings: confidence = gamma, intercept = intercept, precision = accuracy, cov = cov
# hand-edited: every model and summary uses the same complete rows

keep <- complete.cases(response, predictors, exposure, weight)
if (!is.null(weight) && any(weight < 0, na.rm = TRUE)) stop("Weights must not be negative.")
if (!is.null(exposure)) keep <- keep & exposure > 0
if (!is.null(weight)) keep <- keep & weight > 0
response <- response[keep]
predictors <- lapply(predictors, function(x) x[keep])
if (!is.null(exposure)) exposure <- exposure[keep]
if (!is.null(weight)) weight <- weight[keep]

# Poisson regression: the StatsDirect help example (Armitage, Berry and Matthews
# 2001, response in veterans and non-veterans by age group, with the subject-exposure
# of exposure) in R

# R's standard model: a Poisson regression of the counts with the log of the
# exposure as an offset; the age group factor gives the same dummy variables as
# the report, with the youngest group as the baseline
pct <- paste0(100 * confidence, "%")
# Unique model inputs prevent a predictor heading from shadowing the outcome,
# prior weights or offset in glm's model-frame evaluation.
sd_data <- as.data.frame(predictors, optional = TRUE)
sd_own <- tail(make.unique(c(names(sd_data), "response", "log_exposure", "prior_weight")), 3)
sd_data[sd_own] <- list(response, if (is.null(exposure)) rep(0, length(response)) else log(exposure),
                        if (is.null(weight)) rep(1, length(response)) else weight)
sd_terms <- encodeString(names(predictors), quote = "`")
sd_terms[names(predictors) == "."] <- "I(`.`)"
precision <- suppressWarnings(as.numeric(sub("[dD]", "e", precision)))
if (length(precision) != 1L || !is.finite(precision) || precision <= 0) precision <- 1e-7
precision <- min(precision, 0.01)
model <- reformulate(sd_terms, response = as.name(sd_own[1]), intercept = intercept)
fit <- eval(bquote(glm(.(model), offset = .(as.name(sd_own[2])), data = sd_data, family = poisson,
                      weights = .(as.name(sd_own[3])), control = glm.control(maxit = 100))))
# Establish QR rank at R's default tolerance before refining the full-rank fit.
# A tighter epsilon also tightens rank detection and can resurrect an alias.
if (fit$converged && !fit$boundary) {
  refit_start <- coef(fit)
  refit_start[is.na(refit_start)] <- 0
  refit_epsilon <- if (fit$rank == length(refit_start)) precision else 1e-8
  refined <- update(fit, start = refit_start, control = glm.control(epsilon = refit_epsilon, maxit = 100))
  if (refined$converged && !refined$boundary && refined$rank == fit$rank) fit <- refined
}
print(summary(fit))

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
# Without an intercept the report counts the df from the intercept-only model, as
# it does with one (R's null model is then the zero model, with one df more)
df_lr <- fit$df.null - fit$df.residual - as.integer(!intercept)
cat("Deviance (likelihood ratio) chi-square =", six(lr), " df =", df_lr, " ",
    pv(if (df_lr > 0) pchisq(lr, df_lr, lower.tail = FALSE) else NA_real_), "\n")
s <- summary(fit)$coefficients
position <- match(rownames(s), names(coef(fit)))
lab <- (if (intercept) c("Intercept", names(predictors)) else names(predictors))[position]
every <- if (intercept) c("Intercept", names(predictors)) else names(predictors)
dropped <- "* error: drop this variable *"
slopes <- if (intercept) seq_len(nrow(s))[-1] else seq_len(nrow(s))
for (j in seq_along(every)) {
  i <- match(j, position)
  if (is.na(i)) cat(every[j], dropped, "\n") else
    cat(lab[i], " b", j - as.integer(intercept), " = ", six(s[i, 1]), "  z = ", six(s[i, 3]), "  ",
        pv(s[i, 4]), "\n", sep = "")
}

signed <- paste0(ifelse(s[slopes, 1] >= 0, "+", ""), six(s[slopes, 1]), " ", lab[slopes])
cat("log(response)", if (is.null(exposure)) "" else "[offset log(exposure)]", "=", if (intercept) six(s[1, 1]) else "", paste(signed, collapse = " "), "\n")

# Incidence rate ratios: exp of the coefficients, with Wald limits (the intercept's
# row is the baseline rate per subject-year). A predictor that R dropped as aliased
# (its coefficient is NA) has no ratio: its row carries the report's marker
ci <- confint.default(fit, level = confidence)[rownames(s), , drop = FALSE]
for (j in seq_along(every)) {
  i <- match(j, position)
  if (is.na(i)) cat(every[j], dropped, "\n") else
    cat(lab[i], six(s[i, 1]), six(exp(s[i, 1])), six(exp(ci[i, 1])), "to",
        six(exp(ci[i, 2])), "\n")
}

# For a selected dichotomous covariate, the 1 group uses the sum of its
# coefficient and each other coefficient, with their covariance. The 0
# group uses the whole-study ratios. An old selection against a changed
# list must be refused before it can select a different group.
vc <- vcov(fit)[rownames(s), rownames(s), drop = FALSE]
choices <- which(vapply(predictors, function(v) all(v %in% c(0, 1)), logical(1))) + as.integer(intercept)
choices <- choices[choices %in% position]
if (length(predictors) < 2) choices <- integer()
if (!is.null(cov)) {
  selected <- unlist(cov)
  if (length(selected) != length(choices) || !is.logical(selected) || anyNA(selected) || sum(selected) != 1L)
    stop("The selected sub-population is no longer available. Choose a covariate from the current list.")
  first <- match(choices[selected], position)
} else {
  first <- match(choices[1], position)
}
if (!is.na(first)) for (j in setdiff(seq_along(every), c(if (intercept) 1L, position[first]))) {
  i <- match(j, position)
  if (is.na(i)) {
    cat(paste0(lab[first], " = 1:"), every[j], dropped, "\n")
    next
  }
  est <- s[i, 1] + s[first, 1]
  se_sum <- sqrt(vc[i, i] + vc[first, first] + 2 * vc[i, first])
  half <- qnorm((1 + confidence) / 2) * se_sum
  cat(paste0(lab[first], " = 1:"), lab[i], six(s[i, 1]), six(exp(est)), six(exp(est - half)), "to",
      six(exp(est + half)), "\n")
}
if (!is.null(cov) && !is.na(first)) for (j in setdiff(seq_along(every), c(if (intercept) 1L, position[first]))) {
  i <- match(j, position)
  if (is.na(i)) cat(paste0(lab[first], " = 0:"), every[j], dropped, "\n") else
    cat(paste0(lab[first], " = 0:"), lab[i], six(s[i, 1]), six(exp(s[i, 1])), six(exp(ci[i, 1])), "to",
        six(exp(ci[i, 2])), "\n")
}

# The model analysis: the log likelihood (as R's logLik gives it), the information
# criteria on the deviance scale, the two pseudo R-squares (1 minus the ratio of
# the deviances; 1 minus the ratio of the log likelihoods, McFadden's, with the
# offset alone as the null model), Pearson's chi-square and the over-dispersion
# scale, which is Pearson's chi-square over its degrees of freedom
ll <- as.numeric(logLik(fit))
ll0 <- as.numeric(logLik(glm(response ~ 1, offset = if (is.null(exposure)) NULL else log(exposure), family = poisson, weights = weight)))
k <- fit$rank
n <- length(response)
cat("Log likelihood with all covariates =", six(ll), "\n")
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
cat("Pearson goodness of fit =", six(pearson), " df =", fit$df.residual, " ",
    pv(if (fit$df.residual > 0) pchisq(pearson, fit$df.residual, lower.tail = FALSE) else NA_real_), "\n")
scale <- if (fit$df.residual > 0 && pearson > 0) pearson / fit$df.residual else NA_real_
cat("Over-dispersion scale parameter =", six(scale), "\n")
cat("Scaled G2 =", six(lr / scale), " df =", df_lr, " ",
    pv(if (df_lr > 0) pchisq(lr / scale, df_lr, lower.tail = FALSE) else NA_real_), "\n")
cat("Scaled Pearson goodness of fit =", six(pearson / scale), " df =", fit$df.residual,
    " ", pv(pchisq(pearson / scale, fit$df.residual, lower.tail = FALSE)), "\n")
cat("Scaled Deviance goodness of fit =", six(dev / scale), " df =", fit$df.residual,
    " ", pv(pchisq(dev / scale, fit$df.residual, lower.tail = FALSE)), "\n")
cat("Coefficients, standard errors, then the scaled standard errors and Wald z:\n")
for (i in seq_len(nrow(s))) {
  cat(lab[i], six(s[i, 1]), six(s[i, 2]), six(s[i, 2] * sqrt(scale)),
      six(s[i, 1] / (s[i, 2] * sqrt(scale))),
      pv(2 * pnorm(-abs(s[i, 1] / (s[i, 2] * sqrt(scale))))), "\n")
}

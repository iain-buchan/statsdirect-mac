# StatsDirect recipe: Cox proportional hazards regression, as the help shows it in R.
# From the help's R code (survival_analysis/cox_regression.htm); the data and settings above come from the run.
# data: time = times, censor = events, predictors... = predictors, stratum = strata
# settings: confidence = gamma
# hand-edited: a confidence level of 0% or 100% is taken as 95%, as the report takes it

# Cox (proportional hazards) regression: the StatsDirect help example (Armitage and
# Berry 1994, survival in days of lymphoma patients by stage of disease; the test
# workbook's Survival worksheet columns Stage group, Time and Censor) in R
if (!requireNamespace("survival", quietly = TRUE)) install.packages("survival", repos = "https://cloud.r-project.org")
library(survival)

# R's standard model. The report handles tied event times by Breslow's
# approximation, so ties = "breslow" is given (R's default is Efron's method, which
# gives b = 0.961322 here). The report's z and P are the Wald test of each
# coefficient, its deviance chi-square is R's likelihood ratio test, and its hazard
# ratio and selected confidence limits are exp(coef) and Wald limits.
if (!exists("confidence") || is.null(confidence) || !is.finite(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95
sd_data <- as.data.frame(predictors, optional = TRUE)
sd_own <- tail(make.unique(c(names(sd_data), "time", "censor", "sd_stratum")), 3)
sd_data[sd_own] <- list(time, censor, if (is.null(stratum)) rep(1, length(time)) else stratum)
sd_terms <- encodeString(names(predictors), quote = "`")
sd_terms[names(predictors) == "."] <- "I(`.`)"
model <- reformulate(c(sd_terms,
                       if (!is.null(stratum)) paste0("strata(", encodeString(sd_own[3], quote = "`"), ")")),
                     response = call("Surv", as.name(sd_own[1]), as.name(sd_own[2])))
fit <- eval(bquote(coxph(.(model), data = sd_data, ties = "breslow")))
print(summary(fit, conf.int = confidence))

# The report's lines to 6 places
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
ll <- fit$loglik                     # log likelihood without, then with, the covariates
dev <- 2 * (ll[2] - ll[1])
df <- length(coef(fit))
cat(fit$n, "subjects with", fit$nevent, "events\n")
cat("Deviance (likelihood ratio) chi-square =", six(dev), " df =", df, " ",
    pv(pchisq(dev, df, lower.tail = FALSE)), "\n")
s <- summary(fit)$coefficients
for (i in seq_len(nrow(s))) cat(paste(rownames(s)[i], paste0("b", i, " =")), six(s[i, "coef"]), " z =", six(s[i, "z"]), " ", pv(s[i, "Pr(>|z|)"]), "\n")

# Hazard ratios: exp of the coefficient, with Wald limits on the log scale
for (i in seq_len(nrow(s))) {
  half <- qnorm((1 + confidence) / 2) * s[i, "se(coef)"]
  cat(paste(rownames(s)[i], "hazard ratio ="), six(exp(s[i, "coef"])), paste0(" ", 100 * confidence, "% CI ="), six(exp(s[i, "coef"] - half)), "to", six(exp(s[i, "coef"] + half)), "\n")
  cat(paste(rownames(s)[i], "coefficient ="), six(s[i, "coef"]), " standard error =", six(s[i, "se(coef)"]), "\n")
}

# Model analysis: the log likelihoods and their deviance chi-square
cat("Log likelihood with no covariates =", six(ll[1]), "\n")
cat("Log likelihood with all model covariates =", six(ll[2]), "\n")
cat("Deviance (likelihood ratio) chi-square =", six(dev), " df =", df, " ",
    pv(pchisq(dev, df, lower.tail = FALSE)), "\n")

# The report's "baseline survival and hazard" option gives, at each event time,
# the survival probability for a subject with every predictor at zero (or at its
# mean when it is continuous and centred) by the product-limit method of
# Kalbfleisch and Prentice, and the cumulative hazard by the Breslow estimator.
# In R these are survfit's stype = 1 and ctype = 1 at that covariate value. R's
# direct estimate agrees with the report's to 6 places here, though the two can
# differ at a time when everyone still at risk dies at the same time.
if (is.null(stratum)) {   # the baseline of a stratified model is a curve for each stratum, which the report does not give
base <- survfit(fit, newdata = as.data.frame(lapply(predictors, function(v) 0), optional = TRUE), stype = 1, ctype = 1)
at_event <- base$n.event > 0
cat("First baseline rows: time, survival probability, cumulative hazard\n")
print(head(data.frame(time = base$time[at_event], survival = six(base$surv[at_event]),
                 hazard = six(base$cumhaz[at_event])), 5), row.names = FALSE)
}

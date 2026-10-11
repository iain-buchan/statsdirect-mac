# StatsDirect recipe: Conditional logistic regression of matched sets, as the help shows it in R.
# From the help's R code (regression_and_correlation/conditional_logistic.htm); the data and settings above come from the run.
# data: stratum = stratum, case = case-control, predictors... = predictors
# settings: confidence = gamma

lowbwt <- data.frame(PAIRID = stratum, LBWT = case, as.data.frame(predictors, optional = TRUE))
# Conditional logistic regression: the StatsDirect help example (Hosmer and Lemeshow
# 1989, low birth weight in 56 matched pairs) in R. The data are the test workbook's
# Regression worksheet columns PAIRID, LBWT, RACE, LWT, SMOKE, PTD, HT and UI.

# R's conditional logistic regression is in the survival package, which comes with
# R: the strata are the matched pairs. The last place of the widest odds ratio
# limits depends on where the iterations stop, in R as in StatsDirect
if (!requireNamespace("survival", quietly = TRUE)) install.packages("survival", repos = "https://cloud.r-project.org")
library(survival)
fit <- clogit(reformulate(c(names(predictors), "strata(PAIRID)"), "LBWT"), data = lowbwt)
print(summary(fit))

# The report's lines to 6 places. The deviance is -2 times the log likelihood, the
# likelihood ratio chi-square compares it with the model of no predictors (whose
# log likelihood is -56 log 2 for 56 pairs), and McFadden's pseudo R-square is 1
# minus the ratio of the two log likelihoods
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
ll <- fit$loglik[2]
ll0 <- fit$loglik[1]
cat("Deviance (-2 log likelihood) =", six(-2 * ll), "\n")
cat("Deviance (likelihood ratio) chi-square =", six(2 * (ll - ll0)), " ",
    pv(pchisq(2 * (ll - ll0), 6, lower.tail = FALSE)), "\n")
cat("Pseudo (McFadden) R-square =", six(1 - ll / ll0), "\n")
s <- summary(fit)$coefficients
lab <- c("RACE (b)", "SMOKE", "HT", "UI", "PTD", "LWT")
for (i in 1:6) {
  cat(lab[i], six(s[i, "coef"]), six(s[i, "se(coef)"]), " z =", six(s[i, "z"]), " ",
      pv(s[i, "Pr(>|z|)"]), "\n")
}
ci <- summary(fit)$conf.int
for (i in 1:6) {
  cat(lab[i], six(ci[i, "exp(coef)"]), six(ci[i, "lower .95"]), "to",
      six(ci[i, "upper .95"]), "\n")
}
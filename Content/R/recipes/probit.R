# StatsDirect recipe: Probit dose-response analysis from the selected data.
# data: age = dose, girls = subjects, menses = responders
# settings: confidence = conf, log_doses = calc-log10-doses, nc = nc, nrc = nrc, centile = qld
# settings: model = doseResponseModel, prediction_dose = newx, prediction_response = newy
# settings: replay_operation = statsdirectOperation

# hand-edited: replay the selected dose-response model and confidence level.

if (is.null(model)) model <- "probit"   # older parent records retain their operation's model
model <- tolower(as.character(model))
if (length(model) != 1L || !model %in% c("probit", "logit"))
  stop("Select either the probit or logit dose-response model.")
if (is.null(confidence)) confidence <- 0.95
if (length(confidence) != 1L || !is.finite(confidence) || confidence <= 0 || confidence >= 1)
  stop("The confidence level must be between zero and one.")
if (is.null(centile) || !is.finite(centile) || centile <= 0 || centile >= 100) centile <- 90
if (!is.numeric(age) || !is.numeric(girls) || !is.numeric(menses) ||
    length(age) != length(girls) || length(age) != length(menses))
  stop("Select matching numeric dose, subject-count and responder-count columns.")
complete <- is.finite(age) & is.finite(girls) & is.finite(menses)
age <- age[complete]; girls <- girls[complete]; menses <- menses[complete]
# A zero-dose row supplies the control counts in preference to the separate dialog.
control <- which(age == 0)
if (length(control)) {
  control <- control[1L]
  nc <- girls[control]; nrc <- menses[control]
  age <- age[-control]; girls <- girls[-control]; menses <- menses[-control]
}
if (!is.null(nc) && !is.null(nrc) && nc > 0 && nrc > 0)
  stop("Continue in R does not yet support a fitted natural response rate from controls; an unadjusted model would differ from this saved run.")
if (length(age) <= 2L || any(age < 0) || any(girls <= 0) || any(menses < 0 | menses > girls))
  stop("Dose-response analysis needs at least three valid dose levels and responder counts between zero and the subject counts.")
dose_response_rows <- data.frame(dose = age, subjects = girls, responses = menses)
ordered <- order(age)
age <- age[ordered]; girls <- girls[ordered]; menses <- menses[ordered]
if (isTRUE(log_doses)) {
  if (any(age <= 0)) stop("Logarithmic dose-response analysis requires positive doses.")
  age <- log10(age)
}
back <- if (isTRUE(log_doses)) function(v) 10^v else identity

# R supplies the binomial fit and its final Fisher information. Probit uses the
# normal quantile; StatsDirect's Finney logit scale is half the ordinary log odds.
fit <- glm(cbind(menses, girls - menses) ~ age, family = binomial(link = model))
fit <- glm(cbind(menses, girls - menses) ~ age, family = binomial(link = model), start = coef(fit))
native_scale <- if (model == "logit") 2 else 1
a <- unname(coef(fit)[1]) / native_scale
b <- unname(coef(fit)[2]) / native_scale
v <- vcov(fit) / native_scale^2
quantile <- if (model == "probit") qnorm else function(p) qlogis(p) / 2
response_for <- if (model == "probit") pnorm else function(eta) plogis(2 * eta)
dose_for <- function(p) (quantile(p) - a) / b
chi <- sum(residuals(fit, type = "pearson")^2)
df <- fit$df.residual
heterogeneity_p <- pchisq(chi, df, lower.tail = FALSE)
heterogeneity <- is.finite(heterogeneity_p) && heterogeneity_p < 0.05
if (heterogeneity)
  stop("Continue in R cannot yet faithfully reproduce the native heterogeneity-adjusted dose intervals; an ordinary binomial interval would differ from this saved run.")

# Fieller inversion of the fitted line, using the selected confidence level.
fieller <- function(p, conf = confidence) {
  m <- dose_for(p)
  covariance <- v
  critical <- qnorm((1 + conf) / 2)
  g <- critical^2 * covariance[2, 2] / b^2
  if (!is.finite(g) || g >= 1)
    stop("The fitted slope does not give a bounded confidence interval for this dose.")
  vm <- covariance[1, 1] + 2 * m * covariance[1, 2] + m^2 * covariance[2, 2]
  radicand <- vm - g * (covariance[1, 1] - covariance[1, 2]^2 / covariance[2, 2])
  if (!is.finite(radicand) || radicand < 0)
    stop("The fitted model does not give a finite confidence interval for this dose.")
  half <- critical / abs(b) * sqrt(radicand)
  centre <- m + g * (m + covariance[1, 2] / covariance[2, 2]) / (1 - g)
  c(centre - half / (1 - g), centre + half / (1 - g))
}
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
print(summary(fit))
cat("constant =", six(a), "\n")
cat("slope =", six(b), "\n")
cat("Median * Dose =", six(back(dose_for(0.5))), "\n")
interval_label <- if (heterogeneity) "Heterogeneity" else "No Heterogeneity"
cat(paste0("Confidence interval (", interval_label, ") ="), six(back(fieller(0.5, confidence)[1])), "to",
    six(back(fieller(0.5, confidence)[2])), "\n")
cat("* Dose for centile", centile, "=", six(back(dose_for(centile / 100))), "\n")
cat(paste0("Confidence interval (", interval_label, ") ="), six(back(fieller(centile / 100, confidence)[1])), "to",
    six(back(fieller(centile / 100, confidence)[2])), "\n")
cat("Chi2 (heterogeneity of deviations from model) =", six(chi),
    paste0("(", df, " df)"), pv(heterogeneity_p), "\n")
t_slope <- b / sqrt(v[2, 2])
cat("t for slope =", six(t_slope), paste0("(", df, " df)"),
    pv(2 * pt(-abs(t_slope), df)), "\n")
if (!is.null(prediction_dose)) {
  transformed_dose <- if (isTRUE(log_doses)) log10(max(prediction_dose, 1e-30)) else prediction_dose
  predicted_response <- response_for(a + b * transformed_dose)
  cat("Predicted proportional response =", six(predicted_response), "\n")
}
if (!is.null(prediction_response)) {
  predicted_dose <- back(dose_for(prediction_response))
  cat("Predicted dose =", six(predicted_dose), "\n")
}
if (identical(replay_operation, "ProbitMore")) {
  table_doses <- if (isTRUE(log_doses)) log10(dose_response_rows$dose) else dose_response_rows$dose
  expected_counts <- dose_response_rows$subjects * response_for(a + b * table_doses)
  dose_response_table <- data.frame(index = seq_len(nrow(dose_response_rows)),
    subjects = dose_response_rows$subjects, responses = dose_response_rows$responses,
    expected = expected_counts, deviation = dose_response_rows$responses - expected_counts)
  print(dose_response_table, row.names = FALSE)
}
if (identical(replay_operation, "ProbitPlot")) {
  curve_transformed_doses <- seq(min(age), max(age), length.out = 401L)
  dose_response_curve <- data.frame(dose = back(curve_transformed_doses),
    response = response_for(a + b * curve_transformed_doses))
  draw_dose_response <- function() {
    before <- par("family"); on.exit(par(family = before)); par(family = "sans")
    plot(back(age), menses / girls, xlim = range(dose_response_curve$dose), ylim = c(0, 1),
         log = if (isTRUE(log_doses)) "x" else "", pch = 16L,
         xlab = "Dose", ylab = "Proportional response",
         main = paste(if (model == "probit") "Probit" else "Logit", "dose-response curve"))
    lines(dose_response_curve$dose, dose_response_curve$response)
  }
  draw_dose_response()
}

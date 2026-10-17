# StatsDirect recipe: Probit dose-response analysis from the selected data.
# data: age = dose, girls = subjects, menses = responders
# settings: confidence = conf, log_doses = calc-log10-doses, nc = nc, nrc = nrc, centile = qld
# settings: model = doseResponseModel, prediction_dose = newx, prediction_response = newy
# settings: replay_operation = statsdirectOperation

# hand-edited: independent likelihood, natural response, dispersion and dose intervals.
if (is.null(model)) model <- "probit"
model <- tolower(as.character(model))
if (length(model) != 1L || !model %in% c("probit", "logit")) stop("Select either the probit or logit dose-response model.")
if (is.null(confidence)) confidence <- .95
if (length(confidence) != 1L || !is.finite(confidence) || confidence <= 0 || confidence >= 1)
  stop("The confidence level must be between zero and one.")
if (is.null(centile) || !is.finite(centile) || centile <= 0 || centile >= 100) centile <- 90
if (!is.numeric(age) || !is.numeric(girls) || !is.numeric(menses) || length(age) != length(girls) || length(age) != length(menses))
  stop("Select matching numeric dose, subject-count and responder-count columns.")
complete <- is.finite(age) & is.finite(girls) & is.finite(menses)
age <- age[complete]; girls <- girls[complete]; menses <- menses[complete]
# The first complete zero-dose row supplies the independent controls in preference to the dialog.
control <- which(age == 0)
if (length(control)) {
  control <- control[1L]; nc <- girls[control]; nrc <- menses[control]
  age <- age[-control]; girls <- girls[-control]; menses <- menses[-control]
}
if (is.null(nc)) nc <- 0
if (is.null(nrc)) nrc <- 0
if (length(nc) != 1L || length(nrc) != 1L || !is.finite(nc) || !is.finite(nrc) || nc < 0 || nrc < 0 || nrc > nc)
  stop("The control counts must be finite, nonnegative and have no more responses than subjects.")
if (length(age) <= 2L || any(age < 0) || any(girls <= 0) || any(menses < 0 | menses > girls))
  stop("Dose-response analysis needs at least three valid dose levels and responder counts between zero and the subject counts.")
# More retains complete treated rows in their original selection order. Fitting and plotting use ascending dose.
dose_response_rows <- data.frame(dose = age, subjects = girls, responses = menses)
ordered <- order(age); age <- age[ordered]; girls <- girls[ordered]; menses <- menses[ordered]
if (isTRUE(log_doses)) {
  if (any(age <= 0)) stop("Logarithmic dose-response analysis requires positive doses.")
  age <- log10(age)
}
back <- if (isTRUE(log_doses)) function(v) 10^v else identity
link <- sd_dose_response_link(model)
estimated <- sd_dose_response_fit(age, girls, menses, model, nc, nrc)
# Finney's logit uses half the ordinary R log odds. The a/b summaries use that
# native scale; the fit object's coefficients retain R's scale for predict/coef.
fit <- estimated$fit; a <- estimated$a; b <- estimated$b
natural_response <- estimated$natural_response
covariance_full <- estimated$covariance
v <- covariance_full[1:2, 1:2, drop = FALSE]
quantile <- link$quantile
response_for <- link$probability
observed_response_for <- function(eta) natural_response + (1 - natural_response) * response_for(eta)
dose_for <- function(p) (quantile(p) - a) / b
expected_probability <- observed_response_for(a + b * age)
chi_doses <- sum(sd_dose_response_pearson(menses, girls, expected_probability))
chi_controls <- if (natural_response > 0 && nc > 0) sd_dose_response_pearson(nrc, nc, natural_response) else 0
chi <- chi_doses + chi_controls
# At F=0 a controlled group still informs the estimated background probability.
zero_weight <- if (natural_response > 0) expected_probability %in% c(0, 1) else link$density(a + b * age) == 0 | response_for(a + b * age) %in% c(0, 1)
df <- length(age) - 2L - sum(zero_weight)
if (df <= 0) stop("The model needs more informative dose levels to estimate its residual variation.")
heterogeneity_p <- pchisq(chi, df, lower.tail = FALSE)
heterogeneity <- is.finite(heterogeneity_p) && heterogeneity_p < .05
heterogeneity_factor <- chi / df
selected_dispersion <- if (heterogeneity) heterogeneity_factor else 1
selected_covariance <- v * selected_dispersion
critical <- if (heterogeneity) qt((1 + confidence) / 2, df) else qnorm((1 + confidence) / 2)
natural_se <- sqrt(covariance_full[3L, 3L])
natural_se_heterogeneity <- if (natural_se == 0) 0 else natural_se * sqrt(heterogeneity_factor)
se_slope <- sqrt(v[2L, 2L] * selected_dispersion)
t_slope <- b / se_slope
interval_for <- function(p, conf = confidence) {
  critical <- if (heterogeneity) qt((1 + conf) / 2, df) else qnorm((1 + conf) / 2)
  sd_dose_response_fieller(a, b, selected_covariance, quantile(p), critical)
}
fieller <- function(p, conf = confidence) interval_for(p, conf)$limits
dose_response_intervals <- list(median = interval_for(.5), centile = interval_for(centile / 100))
heterogeneity_interval_status <- vapply(dose_response_intervals, function(interval) interval$status, character(1))
# Independent working-value diagnostics explain the same fitted Fisher information.
fitted_eta <- a + b * age; latent <- response_for(fitted_eta); density <- link$density(fitted_eta)
working_weights <- girls * (1 - natural_response)^2 * density^2 / (expected_probability * (1 - expected_probability))
working_response <- fitted_eta + ((menses / girls - natural_response) / (1 - natural_response) - latent) / density
valid_working <- is.finite(working_weights) & working_weights > 0 & is.finite(working_response)
weighted_x <- weighted.mean(age[valid_working], working_weights[valid_working])
weighted_y <- weighted.mean(working_response[valid_working], working_weights[valid_working])
dose_response_diagnostics <- list(
  sxx = sum(working_weights[valid_working] * (age[valid_working] - weighted_x)^2),
  sxy = sum(working_weights[valid_working] * (age[valid_working] - weighted_x) * (working_response[valid_working] - weighted_y)),
  syy = sum(working_weights[valid_working] * (working_response[valid_working] - weighted_y)^2),
  var_b = se_slope^2, seb = se_slope, natural_response = natural_response,
  natural_se = if (heterogeneity) natural_se_heterogeneity else natural_se)
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) if (p < .0001) "P < 0.0001" else paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
print(summary(fit))
cat("constant =", six(a), "\n")
cat("slope =", six(b), "\n")
if (natural_response > 0) cat("Estimated natural response =", six(natural_response), "; SE =", six(dose_response_diagnostics$natural_se), "\n")
cat("Median * Dose =", six(back(dose_for(.5))), "\n")
interval_label <- if (heterogeneity) "Heterogeneity" else "No Heterogeneity"
report_interval <- function(interval) {
  if (interval$status == "bounded")
    cat(paste0("Confidence interval (", interval_label, ") ="), six(back(interval$limits[1L])), "to", six(back(interval$limits[2L])), "\n") else {
    cat(paste0("Confidence set (", interval_label, ") is ", interval$status, ":\n"))
    if (nrow(interval$intervals)) print(matrix(back(interval$intervals), ncol = 2L, dimnames = list(NULL, c("lower", "upper"))))
  }
}
report_interval(dose_response_intervals$median)
cat("* Dose for centile", centile, "=", six(back(dose_for(centile / 100))), "\n")
report_interval(dose_response_intervals$centile)
cat("Chi2 (heterogeneity of deviations from model) =", six(chi), paste0("(", df, " df)"), pv(heterogeneity_p), "\n")
cat("t for slope =", six(t_slope), paste0("(", df, " df)"), pv(2 * pt(-abs(t_slope), df)), "\n")
if (!is.null(prediction_dose)) {
  if (!is.finite(prediction_dose) || prediction_dose < 0) stop("Enter a finite nonnegative dose for interpolation.")
  transformed_dose <- if (isTRUE(log_doses)) log10(max(prediction_dose, 1e-30)) else prediction_dose
  predicted_response <- response_for(a + b * transformed_dose)
  predicted_observed_response <- observed_response_for(a + b * transformed_dose)
  cat("Predicted proportional response above natural response =", six(predicted_response), "\n")
  if (natural_response > 0) cat("Including natural response, predicted proportional response =", six(predicted_observed_response), "\n")
}
if (!is.null(prediction_response)) {
  if (!is.finite(prediction_response) || prediction_response <= 0 || prediction_response >= 1) stop("Enter a response proportion strictly between zero and one.")
  predicted_dose <- back(dose_for(prediction_response))
  cat("Predicted dose =", six(predicted_dose), "\n")
  if (natural_response > 0) cat("The inverse response proportion excludes natural response.\n")
}
if (identical(replay_operation, "ProbitMore")) {
  table_doses <- if (isTRUE(log_doses)) log10(dose_response_rows$dose) else dose_response_rows$dose
  expected_counts <- dose_response_rows$subjects * observed_response_for(a + b * table_doses)
  dose_response_table <- data.frame(index = seq_len(nrow(dose_response_rows)), subjects = dose_response_rows$subjects,
    responses = dose_response_rows$responses, expected = expected_counts, deviation = dose_response_rows$responses - expected_counts)
  cat("Weighted Sxx =", six(dose_response_diagnostics$sxx), "; Sxy =", six(dose_response_diagnostics$sxy), "; Syy =", six(dose_response_diagnostics$syy), "\n")
  cat("Variance of slope =", six(dose_response_diagnostics$var_b), "; standard error =", six(dose_response_diagnostics$seb), "\n")
  if (nc > 0) cat("Natural response =", six(natural_response), "; standard error =", six(dose_response_diagnostics$natural_se), "\n")
  print(dose_response_table, row.names = FALSE)
}
if (identical(replay_operation, "ProbitPlot")) {
  curve_transformed_doses <- seq(min(age), max(age), length.out = 401L)
  eta <- a + b * curve_transformed_doses
  curve_se <- if (is.infinite(selected_dispersion)) rep(Inf, length(eta)) else sqrt(pmax(0, selected_covariance[1L, 1L] + 2 * curve_transformed_doses * selected_covariance[1L, 2L] + curve_transformed_doses^2 * selected_covariance[2L, 2L]))
  # response is the observed probability; adjusted_response and its lower/upper
  # bands use the background-adjusted scale of the native chart.
  dose_response_curve <- data.frame(dose = back(curve_transformed_doses), response = observed_response_for(eta),
    adjusted_response = response_for(eta), lower = response_for(eta - critical * curve_se), upper = response_for(eta + critical * curve_se))
  dose_response_adjusted_response <- (menses / girls - natural_response) / (1 - natural_response)
  dose_response_plot_points <- data.frame(dose = back(age), response = dose_response_adjusted_response)
  draw_dose_response <- function() {
    before <- par("family"); on.exit(par(family = before)); par(family = "sans")
    plot(dose_response_plot_points$dose, dose_response_plot_points$response,
      xlim = range(dose_response_curve$dose), ylim = c(0, 1), log = if (isTRUE(log_doses)) "x" else "", pch = 16L,
      xlab = "Dose", ylab = if (natural_response > 0) "Proportional response above natural response" else "Proportional response",
      main = paste(if (model == "probit") "Probit" else "Logit", "dose-response curve", paste0("(", 100 * confidence, "% CI)")))
    lines(dose_response_curve$dose, dose_response_curve$adjusted_response, col = "#008000")
    lines(dose_response_curve$dose, dose_response_curve$lower, col = "#FF00FF", lty = 2)
    lines(dose_response_curve$dose, dose_response_curve$upper, col = "#FF00FF", lty = 2)
  }
  draw_dose_response()
}

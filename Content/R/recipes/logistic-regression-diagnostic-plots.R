# StatsDirect recipe: the diagnostic plots of a logistic regression, drawn after the regression above.
# hand-edited: the plots StatsDirect draws for this follow-on; the fit and its data are the regression's

# The case-wise diagnostics of each covariate pattern (Hosmer and Lemeshow 1989),
# as StatsDirect plots them: against the event probability and against the
# leverage (the diagonal of the logistic hat matrix), the deletion displacement
# (delta beta), its standardized form, the deletion deviance and the deletion
# chi-square. R's Pearson and deviance residuals and hat values are the
# report's, prior weights included.
if (fit$df.residual <= 0) stop("Plots are not relevant for a saturated model.")
event_probability <- fitted(fit)
leverage <- hatvalues(fit)
pearson_residual <- residuals(fit, type = "pearson")
deviance_residual <- residuals(fit, type = "deviance")
delta_beta <- pearson_residual^2 * leverage / (1 - leverage)
delta_beta_std <- pearson_residual^2 * leverage / (1 - leverage)^2
delta_deviance <- deviance_residual^2 + delta_beta
delta_chi_square <- pearson_residual^2 / (1 - leverage)
diagnostic_plot <- function(x, y, xlab, ylab, main = paste(ylab, "vs.", xlab), cex = 1)
  plot(x, y, xlab = xlab, ylab = ylab, main = main, cex = cex)
probability_label <- "Event Probability (pi)"
leverage_label <- "Leverage (Hi)"
diagnostic_plot(event_probability, delta_beta, probability_label, "Delta Beta")
diagnostic_plot(event_probability, delta_beta_std, probability_label, "Delta Beta Std")
diagnostic_plot(event_probability, delta_deviance, probability_label, "Delta Deviance")
# the deletion chi-square against the event probability, each marker sized by its delta beta
diagnostic_plot(event_probability, delta_chi_square, probability_label, "Delta Chi-square",
                main = paste("Delta Chi-square (delta beta as marker size) vs.", probability_label),
                cex = 0.6 + 2 * delta_beta / max(delta_beta, na.rm = TRUE))
diagnostic_plot(leverage, delta_beta, leverage_label, "Delta Beta")
diagnostic_plot(leverage, delta_beta_std, leverage_label, "Delta Beta Std")
diagnostic_plot(leverage, delta_deviance, leverage_label, "Delta Deviance")
diagnostic_plot(leverage, delta_chi_square, leverage_label, "Delta Chi-square")

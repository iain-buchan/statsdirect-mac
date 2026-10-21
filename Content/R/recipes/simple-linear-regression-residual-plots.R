# StatsDirect recipe: the residual plots of a simple linear regression, drawn after the regression above.
# hand-edited: the plots StatsDirect draws for this follow-on; the fit and its data are the regression's

# The residual plots: the residuals against the fitted values and against the
# predictor, and against van der Waerden normal scores (the normal deviate of
# rank / (n + 1)), as StatsDirect draws them, labelled with the run's column titles
if (!exists("increase_title")) increase_title <- "increase"
if (!exists("weight_title")) weight_title <- "weight"
e <- residuals(fit)
plot(fitted(fit), e, xlab = paste("Fitted", increase_title), ylab = "Residual (Y - y fit)",
     main = "Residuals vs. fitted Y")
abline(h = 0, lty = 2)
plot(model.frame(fit)$weight, e, xlab = paste("Predictor:", weight_title), ylab = "Residual (Y - y fit)",
     main = paste("Residuals vs.", weight_title))
abline(h = 0, lty = 2)
scores <- qnorm(rank(e) / (length(e) + 1))
plot(e, scores, xlab = "Residual (Y - y fit)", ylab = "van der Waerden normal score",
     main = "Normal plot for residuals")

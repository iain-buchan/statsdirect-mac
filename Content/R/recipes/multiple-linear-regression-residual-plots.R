# StatsDirect recipe: the residual plots of a multiple linear regression, drawn after the regression above.
# hand-edited: the plots StatsDirect draws for this follow-on; the fit and its data are the regression's

# The residual plots: the residuals against the fitted values, against each
# predictor, and against van der Waerden normal scores (the normal deviate of
# rank / (n + 1)), as StatsDirect draws them
e <- residuals(fit)
plot(fitted(fit), e, xlab = "Fitted Y (y fit)", ylab = "Residual (Y - y fit)",
     main = "Residuals vs. fitted Y")
abline(h = 0, lty = 2)
frame <- model.frame(fit)
for (name in names(frame)[-1]) {
  if (name == "(weights)") next   # the weights of a weighted fit are not a predictor
  plot(frame[[name]], e, xlab = paste("Predictor:", name), ylab = "Residual (Y - y fit)",
       main = paste("Residuals vs.", name))
  abline(h = 0, lty = 2)
}
scores <- qnorm(rank(e) / (length(e) + 1))
plot(e, scores, xlab = "Residual (Y - y fit)", ylab = "van der Waerden normal score",
     main = "Normal plot for residuals")

# StatsDirect recipe: the regression line with its standard error and confidence bands, drawn after the regression above.
# settings: level = reggamma
# hand-edited: the plot StatsDirect draws for this follow-on; the fit and its data are the regression's, the level is the follow-on's

# The regression line with the standard error of the estimate and the confidence
# band for the mean at each x, as StatsDirect draws it, labelled with the run's
# column titles
if (!exists("increase_title")) increase_title <- "increase"
if (!exists("weight_title")) weight_title <- "weight"
if (is.null(level)) level <- confidence
at <- seq(min(weight, na.rm = TRUE), max(weight, na.rm = TRUE), length.out = 100)
estimate <- predict(fit, newdata = data.frame(weight = at), se.fit = TRUE, interval = "confidence", level = level)
plot(weight, increase, xlab = weight_title, ylab = increase_title,
     main = paste0("SE and ", 100 * level, "% CI for regression estimate"))
lines(at, estimate$fit[, "fit"])
lines(at, estimate$fit[, "fit"] + estimate$se.fit, lty = 3)
lines(at, estimate$fit[, "fit"] - estimate$se.fit, lty = 3)
lines(at, estimate$fit[, "lwr"], lty = 2)
lines(at, estimate$fit[, "upr"], lty = 2)
legend("topright", legend = c("regression estimate", "SE", paste0(100 * level, "% CI")), lty = c(1, 3, 2), bty = "n")

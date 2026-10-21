# StatsDirect recipe: the regression line with its prediction interval, drawn after the regression above.
# hand-edited: the plot StatsDirect draws for this follow-on; the fit and its data are the regression's

# The regression line with the prediction interval for a single new observation
# at each x, as StatsDirect draws it, labelled with the run's column titles
if (!exists("increase_title")) increase_title <- "increase"
if (!exists("weight_title")) weight_title <- "weight"
at <- seq(min(weight, na.rm = TRUE), max(weight, na.rm = TRUE), length.out = 100)
predicted <- predict(fit, newdata = data.frame(weight = at), interval = "prediction", level = confidence)
plot(weight, increase, xlab = weight_title, ylab = increase_title, main = paste(pct, "prediction interval"))
lines(at, predicted[, "fit"])
lines(at, predicted[, "lwr"], lty = 2)
lines(at, predicted[, "upr"], lty = 2)

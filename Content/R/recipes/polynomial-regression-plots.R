# StatsDirect recipe: the fitted polynomial through the data, alone, with its confidence bands and with its prediction bands, drawn after the regression above.
# settings: level = gamma
# hand-edited: the plots StatsDirect draws for this follow-on; the fit and its data are the regression's, the level is the follow-on's

# The fitted curve through the data, then with the confidence interval of the
# estimate at each x, then with the prediction interval, as StatsDirect draws
# them, labelled with the run's column titles
if (!exists("size_title")) size_title <- "size"
if (!exists("kwh_title")) kwh_title <- "kwh"
if (is.null(level)) level <- 0.95
at <- seq(min(size), max(size), length.out = 200)
for (bands in c("none", "confidence", "prediction")) {
  estimate <- predict(fit, newdata = data.frame(size = at), interval = bands, level = level)
  plot(size, kwh, xlab = size_title, ylab = kwh_title, ylim = range(c(kwh, estimate), finite = TRUE),
       main = switch(bands, none = "", confidence = paste0(100 * level, "% CI for the regression estimate"),
                     prediction = paste0(100 * level, "% Prediction Interval")))
  if (bands == "none") lines(at, estimate) else {
    lines(at, estimate[, "fit"])
    lines(at, estimate[, "lwr"], lty = 2)
    lines(at, estimate[, "upr"], lty = 2)
  }
}

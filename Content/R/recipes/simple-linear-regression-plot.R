# StatsDirect recipe: the plot of a simple linear regression, drawn after the regression above.
# hand-edited: the plot StatsDirect draws for this follow-on; the fit and its data are the regression's

# The regression line through the data, as StatsDirect draws it, labelled with
# the run's column titles
if (!exists("increase_title")) increase_title <- "increase"
if (!exists("weight_title")) weight_title <- "weight"
plot(weight, increase, xlab = weight_title, ylab = increase_title, main = "Linear regression")
abline(fit)

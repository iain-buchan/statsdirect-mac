# StatsDirect recipe: the selected linearized model drawn through the data, after the estimates above.
# hand-edited: the plot StatsDirect draws for this follow-on; the fit and its data are the estimates'

# The fitted curve of the selected model through the data on their own scales,
# as StatsDirect draws it: y = a exp(b x) (exponential), y = a x^b (geometric /
# power) or y = x / (a + b x) (hyperbolic), labelled with the run's column titles
if (!exists("size_title")) size_title <- "size"
if (!exists("kwh_title")) kwh_title <- "kwh"
at <- seq(min(size), max(size), length.out = 200)
curve_y <- if (model == 0L) a * exp(b * at) else if (model == 1L) a * at^b else at / (a + b * at)
plot(size, kwh, xlab = size_title, ylab = kwh_title, ylim = range(c(kwh, curve_y), finite = TRUE))
lines(at, curve_y)

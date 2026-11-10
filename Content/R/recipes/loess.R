# StatsDirect recipe: LOESS curve fitting, as the help shows it in R.
# From the help's R code (nonparametric_methods/loess.htm); the data and settings above come from the run.
# data: Hgb = outcome, eGFR... = predictors
# settings: span = span, degree = degree, model = model, title = title, xlab = xlab, ylab = ylab, confidence = ci, plot_fits = plotFits, plot_band = plotFitsAndCi
# hand-edited: plot fitted values against the complete model rows used by loess

rname <- function(s) { s <- tolower(s); s <- gsub("[^a-z0-9._]", ".", s); if (!grepl("^[a-z]", s)) s <- paste0(".", s); if (grepl("^\\.[0-9]", s)) s <- paste0(".", s); s }   # names as the program makes them for R
d <- data.frame(Hgb, as.data.frame(eGFR, optional = TRUE), check.names = FALSE)
# Predictors of the same title are told apart as the record keeps them (X, X_2), and
# names that are still the same made unique, as the program names them for R
record_titles <- function(titles) { kept <- character(0); for (t in titles) { u <- t; n <- 2L; while (u %in% kept) { u <- paste0(t, "_", n); n <- n + 1L }; kept <- c(kept, u) }; kept }
names(d) <- c(rname(names(d)[1]), make.unique(vapply(record_titles(names(d)[-1]), rname, "")))
names(d)[1] <- trimws(sub("~.*$", "", model))   # the outcome as the run's formula names it
# LOESS curve fitting: the StatsDirect help example (haemoglobin against kidney
# function in 804 people with type 2 diabetes) in R
# The data are the Hgb and eGFR columns of the Nonparametric worksheet of the
# StatsDirect test workbook.

# StatsDirect fits this model by calling R itself, with the same function: a
# local polynomial of degree 2 over a span of 0.75 (both are R's defaults).
m <- eval(bquote(loess(.(as.formula(model)), data = d, span = .(span), degree = .(as.numeric(degree)))))
print(m)
cat("Number of Observations:", m$n, "\n")
cat(sprintf("Equivalent Number of Parameters: %.6f\n", m$enp))
cat(sprintf("Residual Standard Error: %.6f\n", m$s))

# The plot: the fitted curve with the selected confidence band
if (is.null(confidence)) confidence <- 0.95  # older saved results
if (is.null(plot_fits)) plot_fits <- TRUE
if (is.null(plot_band)) plot_band <- TRUE
p <- predict(m, se = TRUE)
if (ncol(m$x) == 1) {
x <- as.numeric(m$x[, 1])
i <- order(x)
critical <- qt((1 + confidence) / 2, p$df)
plot(d[[2]], d[[1]], main = title, xlab = xlab, ylab = ylab)
if (plot_fits || plot_band) lines(x[i], p$fit[i], lwd = 2)
if (plot_band) {
  lines(x[i], p$fit[i] - critical * p$se.fit[i], lty = 2)
  lines(x[i], p$fit[i] + critical * p$se.fit[i], lty = 2)
}
}

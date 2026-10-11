# StatsDirect recipe: LOESS curve fitting, as the help shows it in R.
# From the help's R code (nonparametric_methods/loess.htm); the data and settings above come from the run.
# data: Hgb = outcome, eGFR = predictors
# settings: span = span, degree = degree

d <- data.frame(Hgb, eGFR)
# LOESS curve fitting: the StatsDirect help example (haemoglobin against kidney
# function in 804 people with type 2 diabetes) in R
# The data are the Hgb and eGFR columns of the Nonparametric worksheet of the
# StatsDirect test workbook.

# StatsDirect fits this model by calling R itself, with the same function: a
# local polynomial of degree 2 over a span of 0.75 (both are R's defaults).
m <- eval(bquote(loess(Hgb ~ eGFR, data = d, span = .(span), degree = .(as.numeric(degree)))))
print(m)
cat("Number of Observations:", m$n, "\n")
cat(sprintf("Equivalent Number of Parameters: %.6f\n", m$enp))
cat(sprintf("Residual Standard Error: %.6f\n", m$s))

# The plot: the fitted curve with a 95% confidence band
p <- predict(m, se = TRUE)
i <- order(d$eGFR)
t95 <- qt(0.975, p$df)
plot(d$eGFR, d$Hgb, main = "Anaemia vs. Kidney Function in Diabetics",
     xlab = "Estimated Glomerular Filtration Rate (ml/min/1.73m2)",
     ylab = "Haemoglobin Concentration (g/L)")
lines(d$eGFR[i], p$fit[i], lwd = 2)
lines(d$eGFR[i], p$fit[i] - t95 * p$se.fit[i], lty = 2)
lines(d$eGFR[i], p$fit[i] + t95 * p$se.fit[i], lty = 2)
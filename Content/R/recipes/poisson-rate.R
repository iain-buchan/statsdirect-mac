# StatsDirect recipe: Poisson rate with its exact confidence interval, as the help shows it in R.
# From the help's R code (rates/poisson_rate_ci.htm); the data and settings above come from the run.
# settings: events = revents, time_at_risk = tar, confidence = cco
# hand-edited: the confidence level and the data come from the run, as the header says

# Poisson rate confidence interval: the StatsDirect help example (14 events in 400
# person-years of observation, an incidence rate) in R

# poisson.test gives the exact limits for the rate (a whole number of events), the
# same as the chi-square quantile formulae above: its estimate is events / time
pct <- paste0(100 * confidence, "%")
print(poisson.test(events, time_at_risk, conf.level = confidence))

# The report's lines to 6 places. The limits are also the Poisson means whose
# cumulative probabilities reach the tails: qgamma(alpha / 2, events) and
# qgamma(1 - alpha / 2, events + 1), divided by the time at risk. With no events the
# lower limit is 0.
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
alpha <- 1 - confidence
rate <- events / time_at_risk
lower <- if (events == 0) 0 else qgamma(alpha / 2, events) / time_at_risk
upper <- qgamma(1 - alpha / 2, events + 1) / time_at_risk
cat("Events observed =", events, "\n")
cat("Time spent at risk of event =", time_at_risk, "\n")
cat("Poisson (e.g. incidence) rate estimate =", six(rate), "\n")
cat("Exact", pct, "confidence interval =", six(lower), "to", six(upper), "\n")
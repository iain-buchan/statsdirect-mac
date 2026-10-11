# StatsDirect recipe: Indirect standardization and the standardized mortality ratio, as the help shows them in R.
# From the help's R code (rates/smr.htm); the data and settings above come from the run.
# data: rate, doctors, age
# settings: per = nunit, observed = dead, confidence = cco

per <- as.numeric(per)
if (is.null(age)) age <- paste("Group", seq_along(rate))
# Indirect standardization and SMR: the StatsDirect help example (Bland 2000, deaths
# from liver cirrhosis among male doctors against the age-specific rates for all men;
# the test workbook's Rates worksheet columns Reference Mortality, Index Group Sizes
# and Age Groups) in R
pct <- paste0(100 * confidence, "%")
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else if (p > 0.9999) "P > 0.9999" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}

# Expected deaths: each stratum's reference rate times its person-time, here one
# year of follow-up of each doctor, so the group sizes
expected <- rate / per * doctors
e <- sum(expected)
print(data.frame(reference_rate = six(rate / per), person_time = doctors,
                 expected_deaths = six(expected), stratum = age), row.names = FALSE)
cat("Total =", six(e), "\n")

# R's standard test: the observed count as a Poisson count over e units of "time",
# so its estimate is observed / e, the SMR, and its confidence interval is the exact
# one from the chi-square (gamma) quantiles computed below. Its P value is two
# sided, for the null hypothesis that the rate is 1, that is that the SMR is 1
print(poisson.test(observed, T = e, r = 1, conf.level = confidence))

# The report's lines to 6 places, with the SMR and its limits also as integers
alpha <- 1 - confidence
smr <- observed / e
lower <- if (observed == 0) 0 else qchisq(alpha / 2, 2 * observed) / (2 * e)
upper <- qchisq(1 - alpha / 2, 2 * (observed + 1)) / (2 * e)
cat("Standardized Mortality Ratio (SMR) =", six(smr), "\n")
# (an exact .5 here: the program rounds it up, R's round() takes the even integer)
cat("SMR (*100 as integer) =", round(100 * smr), "\n")
cat("Exact", pct, "confidence interval =", six(lower), "to", six(upper),
    paste0("(", round(100 * lower), " to ", round(100 * upper), ")"), "\n")

# The one sided probabilities: the Poisson tails, with e as the mean, at and beyond
# the observed count in each direction (the upper tail is 1 minus the probability of
# fewer than the count observed)
p_more <- ppois(observed - 1, e, lower.tail = FALSE)
p_fewer <- ppois(observed, e)
cat("Probability of observing", observed, "or more deaths by chance", pv(p_more), "\n")
cat("Probability of observing", observed, "or fewer deaths by chance", pv(p_fewer),
    "\n")
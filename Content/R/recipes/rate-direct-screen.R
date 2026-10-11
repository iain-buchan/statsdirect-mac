# StatsDirect recipe: Direct standardization of rates typed on screen, as the help shows it in R.
# From the help's R code (rates/direct_standardization.htm); the data and settings above come from the run.
# data: deaths = data, person_time = data, reference = data
# settings: per = nunit, conf = cco

per <- as.numeric(per)
age <- paste("Group", LETTERS[seq_along(deaths)])   # the rows typed in have no labels
# Direct standardization: the StatsDirect help example (Curtin and Klein 1995, stroke
# deaths in males of a hypothetical US state, standardized to the 1940 US Standard
# Million; the test workbook's Rates worksheet columns Age Bands, Index Events, Index
# Group Sizes and Reference Sizes) in R
# person-time in person-years (the table above gives thousands)

six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)

# Base R has no direct standardization function, so the rate is computed as the
# formulae above give it: the stratum rates weighted by the reference population
rate <- deaths / person_time
weight <- reference / sum(reference)
cat("Rates are expressed per", format(per, scientific = FALSE),
    "units of person time:\n")
cat("Index events  Index PT  Index rate  Reference size  Weight\n")
for (i in seq_along(age)) {
  cat(deaths[i], person_time[i], six(rate[i] * per), reference[i], six(weight[i]),
      "\n")
}

# The exact confidence interval for each stratum's Poisson count over its person-time
# is what poisson.test() gives (its conf.int)
# (poisson.test() takes whole-number counts; qgamma(0.025, y) and qgamma(0.975, y + 1)
# over the person-time give the same limits for fractional counts)
cat("Index rate  Exact 95% confidence interval\n")
for (i in seq_along(age)) {
  ci <- poisson.test(deaths[i], person_time[i], conf.level = conf)$conf.int * per
  cat(six(rate[i] * per), six(ci[1]), "to", six(ci[2]), age[i], "\n")
}

# The directly standardized rate and, applied to the study's person-time, the number of
# events it would have had at the standardized rate
total <- sum(deaths)
dsr <- sum(weight * rate)
cat("Total events =", total, "\n")
cat("Adjusted events =", six(dsr * sum(person_time)), "\n")
cat("Crude rate =", six(total / sum(person_time) * per), "\n")
cat("Adjusted rate R =", six(dsr * per), "\n")

# The variance of the rate as a weighted sum of binomial proportions (any rates) and
# as a weighted sum of Poisson rates (Chiang 1961, small rates), each with a normal
# interval; a stratum whose rate is 0 or 1 adds nothing to the binomial variance
z <- qnorm(1 - (1 - conf) / 2)
v_binomial <- sum(weight^2 * rate * (1 - rate) / person_time)
v_poisson <- sum(weight^2 * rate / person_time)
cat("Any rates (binomial model)\n")
cat("Approximate standard error of R =", six(sqrt(v_binomial) * per), "\n")
cat("Approximate 95% confidence interval =", six((dsr - z * sqrt(v_binomial)) * per),
    "to", six((dsr + z * sqrt(v_binomial)) * per), "\n")
cat("Small rates (Poisson model)\n")
cat("Approximate standard error of R =", six(sqrt(v_poisson) * per), "\n")
cat("Approximate 95% confidence interval =", six((dsr - z * sqrt(v_poisson)) * per),
    "to", six((dsr + z * sqrt(v_poisson)) * per), "\n")

# Dobson et al. (1991): the exact limits for the total count of events, shifted and
# scaled to the standardized rate
total_ci <- poisson.test(total, conf.level = conf)$conf.int
dobson <- dsr + (total_ci - total) * sqrt(v_poisson / total)
cat("Improved approximate (Dobson) 95% confidence interval =",
    six(dobson[1] * per), "to", six(dobson[2] * per), "\n")
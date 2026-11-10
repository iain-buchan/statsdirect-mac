# StatsDirect recipe: Chi-square goodness of fit test, as the help shows it in R.
# From the help's R code (nonparametric_methods/chisq_goodness_fit.htm); the data and settings above come from the run.
# data: observed = observed, expected = expected, names = names
# hand-edited: expected counts, percentages or proportions are rescaled to the observed total, as the report rescales them; categories with a missing count are left out, as the report leaves them out

if (!is.null(names)) names(observed) <- names
# the report leaves out a category whose observed or expected value is missing
keep <- !is.na(observed) & !is.na(expected)
observed <- observed[keep]
expected <- expected[keep]
# Chi-square goodness of fit: the StatsDirect help example (blood groups of 187
# consecutive patients against the distribution expected in the population) in R

# R's standard test. With p given it compares the counts with those proportions;
# rescale.p = TRUE lets p be percentages or expected counts instead, which the
# report scales to the observed total in the same way.
test <- chisq.test(observed, p = expected, rescale.p = TRUE)
print(test)

# Observed and expected frequencies, and the result as StatsDirect reports it
cat("N =", sum(observed), "\n")
print(cbind("Observed frequency" = observed, "Expected frequency" = test$expected))
cat(sprintf("Chi-square = %.6f  df = %d\nP = %.4f\n", test$statistic,
            test$parameter, test$p.value))

# Like StatsDirect, R warns when the expected frequencies are small: the
# chi-square approximation is then unreliable.
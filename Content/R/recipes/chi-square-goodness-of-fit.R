# StatsDirect recipe: Chi-square goodness of fit test, as the help shows it in R.
# From the help's R code (nonparametric_methods/chisq_goodness_fit.htm); the data and settings above come from the run.
# data: observed = observed, expected = expected, names = names

if (!is.null(names)) names(observed) <- names
# Chi-square goodness of fit: the StatsDirect help example (blood groups of 187
# consecutive patients against the distribution expected in the population) in R

# R's standard test. With p given it compares the counts with those proportions;
# rescale.p = TRUE lets p be percentages or expected counts instead.
test <- chisq.test(observed, p = expected)
print(test)

# Observed and expected frequencies, and the result as StatsDirect reports it
cat("N =", sum(observed), "\n")
print(cbind("Observed frequency" = observed, "Expected frequency" = test$expected))
cat(sprintf("Chi-square = %.6f  df = %d\nP = %.4f\n", test$statistic,
            test$parameter, test$p.value))

# Like StatsDirect, R warns when the expected frequencies are small: the
# chi-square approximation is then unreliable.
# StatsDirect recipe: Sample size for an independent cohort study, as the help shows it in R.
# From the help's R code (sample_size/independent_cohort.htm); the data and settings above come from the run.
# settings: p0 = p0, kind = prop-or-or, p1 = p1, rr_in = r, m = m, power = p, alpha = a

# the relative risk to detect: given, or from the two probabilities of the event
rr <- if (kind == "or") rr_in else p1 / p0
# Sample size for an independent cohort study: the StatsDirect help example (invented
# figures: 10% of unexposed subjects develop the disease and a relative risk of 2 is to
# be detected, one control per exposed subject, 80% power, 5% two sided alpha) in R
p1 <- p0 * rr                             # probability of the event in exposed subjects

# power.prop.test with its defaults (two sided, strict = FALSE) uses the same normal
# approximation as the report's uncorrected sample size (the variance pooled under the
# null hypothesis, separate variances under the alternative) but for two groups of
# equal size, so it applies when m = 1; it solves for n numerically and prints the
# unrounded n per group
print(power.prop.test(p1 = p0, p2 = p1, power = power, sig.level = alpha))

# The report's figures, from the formula in the topic, for any number m of controls
# per experimental subject: n is rounded up to a whole number, and the number of
# controls is m times that, rounded down
z_alpha <- qnorm(1 - alpha / 2)
z_beta <- qnorm(power)
pbar <- (p1 + m * p0) / (m + 1)
n <- (z_alpha * sqrt((1 + 1 / m) * pbar * (1 - pbar)) +
      z_beta * sqrt(p0 * (1 - p0) / m + p1 * (1 - p1)))^2 / (p0 - p1)^2
cat("Probability of event in control group =", p0, "\n")
cat("Probability of event in experimental group =", p1, "\n")
cat("Controls per case subject =", m, "\n")
cat("Alpha =", alpha, "\n")
cat("Power =", power, "\n")
cat("For uncorrected chi-square test:\n")
cat("N =", ceiling(n), "case subjects and", floor(m * ceiling(n)), "controls\n")

# The continuity-corrected size for the corrected chi-square and Fisher's exact tests
# (Casagrande et al. 1978; Fleiss 1981), calculated from the unrounded n
nc <- n / 4 * (1 + sqrt(1 + 2 * (m + 1) / (n * m * abs(p0 - p1))))^2
cat("For corrected chi-square and Fisher's exact tests:\n")
cat("N =", ceiling(nc), "case subjects and", floor(m * ceiling(nc)), "controls\n")
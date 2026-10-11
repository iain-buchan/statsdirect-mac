# StatsDirect recipe: Binomial distribution: the probabilities of exactly, at least and at most r successes in n trials, as the help shows them in R.
# From the help's R code (distributions/binomial.htm); the settings above come from the run.
# settings: p = value, n = df, r = df2
# hand-edited: the calculator's boxes are bound to the run; the help illustrates fixed values

# dbinom(r, n, p) is the probability of exactly r successes in n trials, pbinom(r, n, p)
# the probability of r or fewer; with lower.tail = FALSE, pbinom gives the probability
# of more than r successes, so r or more is pbinom(r - 1, n, p, lower.tail = FALSE).
dbinom(r, n, p)                             # exactly r successes
pbinom(r, n, p)                             # r or fewer
pbinom(r - 1, n, p, lower.tail = FALSE)     # r or more

# The calculator's report line, its probabilities to 15 decimal places
fifteen <- function(x) formatC(x, digits = 15, format = "f", drop0trailing = TRUE)
cat("P(binomial p ", p, ", ", n, " trials) = ", fifteen(dbinom(r, n, p)), " [", r,
    " successes], ", fifteen(pbinom(r - 1, n, p, lower.tail = FALSE)), " [>=", r,
    " successes], ", fifteen(pbinom(r, n, p)), " [<=", r, " successes]\n", sep = "")

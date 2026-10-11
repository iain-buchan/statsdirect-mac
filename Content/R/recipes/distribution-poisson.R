# StatsDirect recipe: Poisson distribution: the probabilities of exactly, at least and at most n events for a mean, or the mean of a probability, as the help shows them in R.
# From the help's R code (distributions/poisson.htm); the settings above come from the run.
# settings: n = df, mu = df2, lower = lower, upper = upper, two_sided = two_sided, asked = asked
# hand-edited: the calculator's boxes are bound to the run; the help illustrates fixed values

# StatsDirect shows the probabilities of exactly n, of n or more and of n or fewer events to
# 15 decimal places, and a mean to 15 significant figures; these helpers print R's values the
# same way.
p15 <- function(x) formatC(x, digits = 15, format = "f", drop0trailing = TRUE)
s15 <- function(x) trimws(formatC(x, digits = 15, format = "fg", drop0trailing = TRUE))

if (exists("asked") && asked == "invert-upper") {
  # The inverse (the calculator's Invert on the "n or more" box, and its Lower CL button): the
  # mean at which n or more events has the probability typed in. In R it comes from the gamma
  # distribution: n or more events with mean m has the same probability as the n-th event of a
  # unit-rate process occurring by time m, so P(n or more) = pgamma(m, n) and the mean is
  # qgamma(p, n)
  m <- qgamma(upper, n)
  cat("Mean at which", n, "or more events has probability", p15(upper), "=", s15(m), "\n")
  cat("  check:", p15(ppois(n - 1, m, lower.tail = FALSE)), "\n")
} else if (exists("asked") && asked == "invert-two-sided") {
  # The inverse on the "n or fewer" box (the Upper CL button): P(n or fewer) = 1 - pgamma(m, n + 1),
  # so the mean is qgamma(1 - p, n + 1)
  m <- qgamma(1 - two_sided, n + 1)
  cat("Mean at which", n, "or fewer events has probability", p15(two_sided), "=", s15(m), "\n")
  cat("  check:", p15(ppois(n, m)), "\n")
} else {
  # The probabilities for a count of n events when the mean is mu. dpois(n, mean) is the
  # probability of exactly n events and ppois(n, mean) that of n or fewer; with
  # lower.tail = FALSE ppois gives the probability of MORE than n events, so the probability of
  # n or more events is ppois(n - 1, mean, lower.tail = FALSE)
  cat("Probability of", n, "events =", p15(dpois(n, mu)), "\n")
  cat("Probability of", n, "or more events =", p15(ppois(n - 1, mu, lower.tail = FALSE)), "\n")
  cat("Probability of", n, "or fewer events =", p15(ppois(n, mu)), "\n")
}

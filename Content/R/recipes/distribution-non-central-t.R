# StatsDirect recipe: Non-central t distribution: the tail probabilities of t on its degrees of freedom and non-centrality, or the t of a tail probability, as the help shows them in R.
# From the help's R code (distributions/non_central_t.htm); the settings above come from the run.
# settings: t = value, df = df, delta = df2, lower = lower, upper = upper, two_sided = two_sided, asked = asked
# hand-edited: the calculator's boxes are bound to the run; the help illustrates fixed values

# StatsDirect shows these to up to 15 decimal places. R's pt evaluates the non-central t
# distribution by the series of Lenth (1989) and qt inverts it (see the help for pt); they
# agree with StatsDirect's values to 12 decimal places, so 12 are printed.
twelve <- function(x) formatC(x, digits = 12, format = "f", drop0trailing = TRUE)

if (exists("asked") && asked != "calculate") {
  # The inverse (the calculator's Invert): the t below which the distribution has the lower
  # tail probability 1 - p, qt(1 - p, df, ncp = delta). The report labels the line with the
  # upper tail p, whichever P box the probability was typed in.
  p <- switch(asked, "invert-lower" = 1 - lower, "invert-two-sided" = two_sided / 2, upper)
  cat("non-central t(P ", twelve(p), ", df ", df, ", delta ", delta, ") = ",
      twelve(qt(1 - p, df, ncp = delta)), "\n", sep = "")
} else {
  # Tail probabilities of t on df degrees of freedom with non-centrality delta: pt(q, df, ncp)
  # is the lower tail (P for t <= t); lower.tail = FALSE gives the upper
  cat("P(non-central t < ", t, ", df ", df, ", delta ", delta, ") = ",
      twelve(pt(t, df, ncp = delta, lower.tail = FALSE)), " upper, ",
      twelve(pt(t, df, ncp = delta)), " lower\n", sep = "")
}

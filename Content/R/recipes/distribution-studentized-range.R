# StatsDirect recipe: Studentized range (Q) distribution: the tail probabilities of Q for a number of samples and residual degrees of freedom, or the Q of an upper tail, as the help shows them in R.
# From the help's R code (distributions/studentized_range.htm); the settings above come from the run.
# settings: q = value, df = df, k = df2, lower = lower, upper = upper, asked = asked
# hand-edited: the calculator's boxes are bound to the run; the help illustrates fixed values

# The calculator shows its results to 7 decimal places, so these do too
seven <- function(x) formatC(x, digits = 7, format = "f", drop0trailing = TRUE)

if (exists("asked") && asked != "calculate") {
  # The inverse (the calculator's Invert): the Q with the area p in its upper tail, a critical
  # value. qtukey() is documented as accurate to the 4th decimal place, so its value is
  # refined to the 7 places shown by solving ptukey() = 1 - p
  p <- if (asked == "invert-lower") 1 - lower else upper
  crit <- qtukey(1 - p, nmeans = k, df = df)
  crit <- uniroot(function(x) ptukey(x, nmeans = k, df = df) - (1 - p),
                  c(crit - 0.05, crit + 0.05), tol = 1e-10)$root
  cat("Q(upper P ", seven(p), ", df ", df, ", samples ", k, ") = ", seven(crit), "\n", sep = "")
} else {
  # Tail probabilities of Q for k samples (means) with df residual degrees of freedom:
  # ptukey() gives the lower tail unless told otherwise
  cat("P(Q ", q, ", df ", df, ", samples ", k, ") = ",
      seven(ptukey(q, nmeans = k, df = df, lower.tail = FALSE)), " upper, ",
      seven(ptukey(q, nmeans = k, df = df)), " lower\n", sep = "")
}

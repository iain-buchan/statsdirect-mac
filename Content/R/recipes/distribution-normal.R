# StatsDirect recipe: Normal distribution: the tail areas of a deviate, or the deviate of a tail area, as the help shows them in R.
# From the help's R code (distributions/normal.htm); the settings above come from the run.
# settings: z = value, lower = lower, upper = upper, two_sided = two_sided, asked = asked
# hand-edited: the calculator's boxes are bound to the run; the help illustrates fixed values

# StatsDirect shows each figure to 15 significant figures and at most 15 decimal places
s15 <- function(x) formatC(signif(x, 15), digits = 15, format = "f", drop0trailing = TRUE)

if (exists("asked") && asked != "calculate") {
  # The deviate for a tail area (the calculator's Invert): qnorm(p) is the deviate whose lower
  # tail area is p, so qnorm(p, lower.tail = FALSE) is the deviate whose upper tail area is p.
  # StatsDirect names the inverse by its upper tail P, whichever of its P boxes the P was typed in.
  p <- switch(asked, "invert-lower" = 1 - lower, "invert-two-sided" = two_sided / 2, upper)
  cat("z(upper P ", s15(p), ") = ", s15(qnorm(p, lower.tail = FALSE)), "\n", sep = "")
} else {
  # Tail areas of the normal deviate z: pnorm(z) is the lower tail P(Z <= z), and with
  # lower.tail = FALSE it is the upper tail P(Z > z). The two sided P is twice the smaller tail.
  lower <- pnorm(z)
  upper <- pnorm(z, lower.tail = FALSE)
  cat("P(z ", z, ") = ", s15(upper), " upper, ", s15(lower), " lower, ",
      s15(2 * min(lower, upper)), " two sided\n", sep = "")
}

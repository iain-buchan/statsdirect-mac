# StatsDirect recipe: Student's t distribution: the tail areas of t on its degrees of freedom, or the t of a tail area, as the help shows them in R.
# From the help's R code (distributions/t.htm); the settings above come from the run.
# settings: t = value, df = df, lower = lower, upper = upper, two_sided = two_sided, asked = asked
# hand-edited: the calculator's boxes are bound to the run; the help illustrates fixed values

# StatsDirect's calculator shows tail areas to 15 decimal places and t to 15 significant
# figures; these helpers print R's values the same way.
p15 <- function(p) formatC(p, digits = 15, format = "f", drop0trailing = TRUE)
t15 <- function(x) formatC(x, digits = 15, format = "g", drop0trailing = TRUE)

if (exists("asked") && asked != "calculate") {
  # t from a tail area (the calculator's Invert): qt() gives the t below which a given area
  # lies, so the t with the area p above it is qt(p, df, lower.tail = FALSE), the same as
  # qt(1 - p, df). StatsDirect names the inverse by its upper tail P, whichever P box was used.
  p <- switch(asked, "invert-lower" = 1 - lower, "invert-two-sided" = two_sided / 2, upper)
  cat("t(upper P ", p15(p), ", df ", df, ") = ", t15(qt(p, df, lower.tail = FALSE)), "\n", sep = "")
} else {
  # Tail areas from t: pt() gives the lower tail P(T <= t) by default, and the upper
  # tail P(T > t) with lower.tail = FALSE. The two sided P is twice the smaller tail.
  upper <- pt(t, df, lower.tail = FALSE)
  lower <- pt(t, df)
  cat("P(t ", t, ", df ", df, ") = ", p15(upper), " upper, ", p15(lower), " lower, ",
      p15(2 * min(upper, lower)), " two sided\n", sep = "")
}

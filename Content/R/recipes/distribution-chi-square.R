# StatsDirect recipe: Chi-square distribution: the upper tail probability of a chi-square statistic, or the statistic of an upper tail, as the help shows them in R.
# From the help's R code (distributions/chisq.htm); the settings above come from the run.
# settings: chi = value, df = df, upper = upper, asked = asked
# hand-edited: the calculator's boxes are bound to the run; the help illustrates fixed values

# StatsDirect shows the probability to 15 decimal places and a chi-square value to 15
# significant figures
fifteen <- function(x) formatC(x, digits = 15, format = "f", drop0trailing = TRUE)
x15 <- function(x) formatC(x, digits = 15, format = "g", drop0trailing = TRUE)

if (exists("asked") && asked != "calculate") {
  # The chi-square value that cuts off a given upper tail (the critical value for a P):
  # qchisq with lower.tail = FALSE
  cat("chi-sq(upper P ", fifteen(upper), ", df ", df, ") = ", x15(qchisq(upper, df, lower.tail = FALSE)), "\n", sep = "")
} else {
  # The upper tail probability of a chi-square statistic, the P value of a chi-square test:
  # pchisq with lower.tail = FALSE (pchisq(x, df) gives the lower tail; subtracting that from 1
  # would lose accuracy far into the upper tail)
  cat("P(chi-sq ", chi, ", df ", df, ") = ", fifteen(pchisq(chi, df, lower.tail = FALSE)), " upper tail\n", sep = "")
}

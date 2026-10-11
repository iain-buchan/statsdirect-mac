# StatsDirect recipe: F (variance ratio) distribution: the upper tail probability of F on its degrees of freedom, or the F of an upper tail, as the help shows them in R.
# From the help's R code (distributions/f.htm); the settings above come from the run.
# settings: f = value, dfn = df, dfd = df2, upper = upper, asked = asked
# hand-edited: the calculator's boxes are bound to the run; the help illustrates fixed values

# The calculator shows tail areas to 15 decimal places and F to 15 significant figures;
# p15() and x15() print R's values the same way. For ordinary degrees of freedom the
# program's integration and R's agree to about 14 figures, so the last digit can differ.
p15 <- function(p) formatC(p, digits = 15, format = "f", drop0trailing = TRUE)
x15 <- function(x) formatC(x, digits = 15, format = "g", drop0trailing = TRUE)

if (exists("asked") && asked != "calculate") {
  # The inverse: the F with the given area in its upper tail (a critical value), qf with
  # lower.tail = FALSE
  cat("F(upper P ", p15(upper), ", dfn ", dfn, ", dfd ", dfd, ") = ",
      x15(qf(upper, df1 = dfn, df2 = dfd, lower.tail = FALSE)), "\n", sep = "")
} else {
  # The upper tail P of F on dfn and dfd degrees of freedom: pf() gives the lower tail unless
  # told otherwise
  cat("P(F ", f, ", dfn ", dfn, ", dfd ", dfd, ") = ",
      p15(pf(f, df1 = dfn, df2 = dfd, lower.tail = FALSE)), " upper\n", sep = "")
}

# StatsDirect recipe: Latin square analysis of variance, as the help shows it in R.
# From the help's R code (analysis_of_variance/latin_square.htm); the data and settings above come from the run.
# data: blister = observations, rabbit = column, position = row, order = treatment

rabbit <- factor(rabbit)
position <- factor(position)
order <- factor(order)
# Latin square analysis of variance: the StatsDirect help example (Armitage and
# Berry 1994, blistering of rabbits' skin at six sites in six rabbits, with the
# order of inoculation as the Latin factor) in R

# R's standard analysis: the three factors are orthogonal in a Latin square, so
# each sum of squares is the same whatever the order of the terms
fit <- aov(blister ~ position + rabbit + order)
print(summary(fit))

# The report's lines to 6 places
a <- anova(fit)
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else paste("P =", formatC(p, digits = 4, format = "f"))
}
cat("Rows", six(a$"Sum Sq"[1]), a$Df[1], six(a$"Mean Sq"[1]), "\n")
cat("Columns", six(a$"Sum Sq"[2]), a$Df[2], six(a$"Mean Sq"[2]), "\n")
cat("Treatments", six(a$"Sum Sq"[3]), a$Df[3], six(a$"Mean Sq"[3]), "\n")
cat("Residual", six(a$"Sum Sq"[4]), a$Df[4], six(a$"Mean Sq"[4]), "\n")
cat("Total", six(sum(a$"Sum Sq")), sum(a$Df), "\n")
cat("F (rows) =", six(a$"F value"[1]), " ", pv(a$"Pr(>F)"[1]), "\n")
cat("F (columns) =", six(a$"F value"[2]), " ", pv(a$"Pr(>F)"[2]), "\n")
cat("F (treatments) =", six(a$"F value"[3]), " ", pv(a$"Pr(>F)"[3]), "\n")
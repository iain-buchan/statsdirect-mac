# StatsDirect recipe: Two way hierarchical (nested) analysis of variance, as the help shows it in R.
# From the help's R code (analysis_of_variance/nested.htm); the data and settings above come from the run.
# nested: data2d = data2d

# data2d: the groups, each a list of its subgroups, each the observations
y <- unlist(data2d)
group <- factor(rep(seq_along(data2d), times = sapply(data2d, function(g) sum(lengths(g)))))
subgroup <- factor(unlist(lapply(data2d, function(g) rep(seq_along(g), lengths(g)))))
# Fully nested (hierarchical) analysis of variance: the StatsDirect help example
# (Snedecor and Cochran 1989, calcium in the leaves of turnip greens: four
# plants, three leaves from each plant, two samples from each leaf) in R

# R's standard analysis: leaves are nested within plants, written group/subgroup.
# The F ratios that summary() prints all use the residual mean square
fit <- aov(y ~ group/subgroup)
print(summary(fit))

# The report's table to 6 places, and its three F ratios: StatsDirect also
# tests the groups (plants) against the subgroups within groups (leaves within
# plants), the appropriate test when the leaves are a random sample
a <- anova(fit)
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else paste("P =", formatC(p, digits = 4, format = "f"))
}
ms <- a$"Mean Sq"
df <- a$Df
cat("Between Groups", six(a$"Sum Sq"[1]), df[1], six(ms[1]), "\n")
cat("Between Subgroups within Groups", six(a$"Sum Sq"[2]), df[2], six(ms[2]), "\n")
cat("Residual", six(a$"Sum Sq"[3]), df[3], six(ms[3]), "\n")
cat("Total", six(sum(a$"Sum Sq")), sum(df), "\n")
f1 <- ms[1] / ms[3]
f2 <- ms[1] / ms[2]
f3 <- ms[2] / ms[3]
p1 <- pf(f1, df[1], df[3], lower.tail = FALSE)
p2 <- pf(f2, df[1], df[2], lower.tail = FALSE)
p3 <- pf(f3, df[2], df[3], lower.tail = FALSE)
cat("F (VR between groups) =", six(f1), " ", pv(p1), "\n")
cat("F (using group/subgroup msqr) =", six(f2), " ", pv(p2), "\n")
cat("F (VR between subgroups within groups) =", six(f3), " ", pv(p3), "\n")
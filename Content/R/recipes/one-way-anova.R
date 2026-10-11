# StatsDirect recipe: One way analysis of variance, as the help shows it in R.
# From the help's R code (analysis_of_variance/one_way.htm); the data and settings above come from the run.
# data: groups...
# hand-edited: the data come from the run, as the header says

# One way analysis of variance: the StatsDirect help example (Armitage and Berry
# 1994, worms recovered from four groups of rats) in R
groups <- lapply(groups, function(v) v[!is.na(v)])   # missing values are left out
worms <- unlist(groups)
group <- factor(rep(names(groups), lengths(groups)), levels = names(groups))

# R's standard analysis gives the same table: its "group" line is Between
# Groups and its "Residuals" line is Within Groups
fit <- aov(worms ~ group)
print(summary(fit))

# The report's lines to 6 places
a <- anova(fit)
six <- function(x) {
  formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
}
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
cat("Between Groups", six(a$"Sum Sq"[1]), a$Df[1], six(a$"Mean Sq"[1]), "\n")
cat("Within Groups", six(a$"Sum Sq"[2]), a$Df[2], six(a$"Mean Sq"[2]), "\n")
cat("Corrected Total", six(sum(a$"Sum Sq")), sum(a$Df), "\n")
cat("F (variance ratio) =", six(a$"F value"[1]), " ", pv(a$"Pr(>F)"[1]), "\n")


# StatsDirect recipe: Two way analysis of variance with repeated observations, as the help shows it in R.
# From the help's R code (analysis_of_variance/two_way_replicate.htm); the data and settings above come from the run.
# nested: data2d = data2d

# data2d: the blocks (rows), each a list of the treatments (columns), each the repeated observations
y <- unlist(data2d)
subject <- factor(rep(seq_along(data2d), times = sapply(data2d, function(block) sum(lengths(block)))))
treatment <- factor(unlist(lapply(data2d, function(block) rep(seq_along(block), lengths(block)))))
# Two way randomized block analysis of variance with repeated observations: the
# StatsDirect help example (Armitage and Berry 1994, clotting times of plasma
# from three subjects treated in three ways, each measurement repeated three
# times) in R. Each replicate is a table of treatment columns by subject rows.

# R's standard analysis: subject * treatment fits both main effects and their
# interaction, and each F ratio uses the residual mean square
fit <- aov(y ~ subject * treatment)
print(summary(fit))

# The report's lines to 6 places
a <- anova(fit)
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
row <- function(label, i) {
  cat(label, six(a$"Sum Sq"[i]), a$Df[i], six(a$"Mean Sq"[i]), "\n")
}
row("Blocks (rows)", 1)
row("Treatments (columns)", 2)
row("Interaction", 3)
row("Residual (error)", 4)
cat("Corrected total", six(sum(a$"Sum Sq")), sum(a$Df), "\n")
cat("F (VR blocks) =", six(a$"F value"[1]), " ", pv(a$"Pr(>F)"[1]), "\n")
cat("F (VR treatments) =", six(a$"F value"[2]), " ", pv(a$"Pr(>F)"[2]), "\n")
cat("F (VR interaction) =", six(a$"F value"[3]), " ", pv(a$"Pr(>F)"[3]), "\n")
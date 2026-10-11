# StatsDirect recipe: Two way analysis of variance of a randomized block layout, as the help shows it in R.
# From the help's R code (analysis_of_variance/two_way.htm); the data and settings above come from the run.
# matrix: blocks

# the blocks are the rows of the frame and the treatments its columns
clotting <- as.vector(t(blocks))
subject <- factor(rep(seq_len(nrow(blocks)), each = ncol(blocks)))
treatment <- factor(rep(colnames(blocks), times = nrow(blocks)), levels = colnames(blocks))
# Two way randomized block analysis of variance: the StatsDirect help example
# (Armitage and Berry 1994, clotting times of plasma from eight subjects treated
# in four ways) in R

# R's standard analysis, with the blocks first so that each factor's sum of
# squares is the one StatsDirect prints (the design is balanced, so the order
# makes no difference here)
fit <- aov(clotting ~ subject + treatment)
print(summary(fit))

# The report's lines to 6 places
a <- anova(fit)
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else paste("P =", formatC(p, digits = 4, format = "f"))
}
cat("Between blocks (rows)", six(a$"Sum Sq"[1]), a$Df[1], six(a$"Mean Sq"[1]), "\n")
cat("Between treatments (columns)", six(a$"Sum Sq"[2]), a$Df[2], six(a$"Mean Sq"[2]),
    "\n")
cat("Residual (error)", six(a$"Sum Sq"[3]), a$Df[3], six(a$"Mean Sq"[3]), "\n")
cat("Corrected total", six(sum(a$"Sum Sq")), sum(a$Df), "\n")
cat("F (VR between blocks) =", six(a$"F value"[1]), " ", pv(a$"Pr(>F)"[1]), "\n")
cat("F (VR between treatments) =", six(a$"F value"[2]), " ", pv(a$"Pr(>F)"[2]), "\n")
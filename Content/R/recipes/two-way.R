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

# The corrected total is not a separate row in R's ANOVA table.
cat("Corrected total sum of squares =", sum(anova(fit)$"Sum Sq"),
    "  DF =", sum(anova(fit)$Df), "\n")

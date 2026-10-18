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

# The corrected total is not a separate row in R's ANOVA table.
cat("Corrected total sum of squares =", sum(anova(fit)$"Sum Sq"),
    "  DF =", sum(anova(fit)$Df), "\n")

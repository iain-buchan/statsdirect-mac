# Two way randomized block analysis of variance with repeated observations: the
# StatsDirect help example (Armitage and Berry 1994, clotting times of plasma
# from three subjects treated in three ways, each measurement repeated three
# times) in R. Each replicate is a table of treatment columns by subject rows.
rep1 <- c(9.8, 9.2, 8.4,   9.9, 9.1, 8.6,   11.3, 10.3, 9.8)
rep2 <- c(10.1, 8.6, 7.9,  9.5, 9.1, 8.0,   10.7, 10.7, 10.1)
rep3 <- c(9.8, 9.2, 8.0,   10.0, 9.4, 8.0,  10.7, 10.2, 10.1)
clotting <- c(rep1, rep2, rep3)
subject <- factor(rep(1:3, times = 9))                        # the blocks (rows)
treatment <- factor(rep(rep(c("A", "B", "C"), each = 3), times = 3))

# R's standard analysis: subject * treatment fits both main effects and their
# interaction, and each F ratio uses the residual mean square
fit <- aov(clotting ~ subject * treatment)
print(summary(fit))

# Corrected total, additional to the standard ANOVA table.
cat("Corrected total sum of squares =", sum(anova(fit)$"Sum Sq"),
    "  DF =", sum(anova(fit)$Df), "\n")

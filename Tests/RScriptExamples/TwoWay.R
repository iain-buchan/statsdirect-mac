# Two way randomized block analysis of variance: the StatsDirect help example
# (Armitage and Berry 1994, clotting times of plasma from eight subjects treated
# in four ways) in R
clotting <- c(8.4, 9.4, 9.8, 12.2,
              12.8, 15.2, 12.9, 14.4,
              9.6, 9.1, 11.2, 9.8,
              9.8, 8.8, 9.9, 12.0,
              8.4, 8.2, 8.5, 8.5,
              8.6, 9.9, 9.8, 10.9,
              8.9, 9.0, 9.2, 10.4,
              7.9, 8.1, 8.2, 10.0)                # by subject, then treatment
subject <- factor(rep(1:8, each = 4))             # the blocks (rows)
treatment <- factor(rep(paste("Treatment", 1:4), times = 8))

# R's standard analysis, with the blocks first so that each factor's sum of
# squares is the one StatsDirect prints (the design is balanced, so the order
# makes no difference here)
fit <- aov(clotting ~ subject + treatment)
print(summary(fit))

# Corrected total, additional to the standard ANOVA table.
cat("Corrected total sum of squares =", sum(anova(fit)$"Sum Sq"),
    "  DF =", sum(anova(fit)$Df), "\n")

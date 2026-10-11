# StatsDirect recipe: Crossover trial analysis, as the help shows it in R.
# From the help's R code (analysis_of_variance/crossover.htm); the data and settings above come from the run.
# data: drug1 = group1drug, placebo1 = group1placebo, baseline1 = group1baseline, drug2 = group2drug, placebo2 = group2placebo, baseline2 = group2baseline
# settings: confidence = gamma

if (!is.null(baseline1)) { drug1 <- drug1 - baseline1; placebo1 <- placebo1 - baseline1 }   # a baseline, when given, is taken from both periods, as the report does
if (!is.null(baseline2)) { drug2 <- drug2 - baseline2; placebo2 <- placebo2 - baseline2 }
# Crossover trial: the StatsDirect help example (Armitage and Berry 1994, dry
# nights out of 14 in two groups of bedwetters, drug then placebo or placebo
# then drug) in R

# Each group's mean in each period and its mean difference, period 1 less
# period 2
pct <- paste0(100 * confidence, "%")
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else paste("P =", formatC(p, digits = 4, format = "f"))
}
d1 <- drug1 - placebo1                    # group 1 had the drug in period 1
d2 <- placebo2 - drug2                    # group 2 had the placebo first
cat("Group 1", six(mean(drug1)), six(mean(placebo1)), six(mean(d1)), "\n")
cat("Group 2", six(mean(placebo2)), six(mean(drug2)), six(mean(d2)), "\n")

# StatsDirect's four tests are t tests (Armitage and Berry 1994), which R's
# standard t.test gives. Relative effectiveness: drug against placebo, paired
# within subjects and pooled over both groups
est <- function(label, value, r) {
  cat(label, "=", six(value), "  SE =", six(r$stderr), "\n")
}
tline <- function(r) {
  cat("t =", six(r$statistic), "  DF =", r$parameter, " ", pv(r$p.value), "\n")
}
r <- t.test(c(drug1, drug2), c(placebo1, placebo2), paired = TRUE, conf.level = confidence)
est("combined diff", r$estimate, r)
tline(r)

# Treatment effect: the two groups' period differences compared with an unpaired
# test assuming equal variances. Their difference is twice the treatment effect,
# so the effect and its confidence interval are half of what t.test gives.
r <- t.test(d1, d2, var.equal = TRUE, conf.level = confidence)
est("diff 1 - diff 2", r$estimate[1] - r$estimate[2], r)
cat("effect magnitude =", six((r$estimate[1] - r$estimate[2]) / 2), pct, "CI =",
    six(r$conf.int[1] / 2), "to", six(r$conf.int[2] / 2), "\n")
tline(r)

# Period effect: the same differences with group 2's sign reversed, so that the
# test compares the sum of the two mean differences with zero
r <- t.test(d1, -d2, var.equal = TRUE, conf.level = confidence)
est("diff 1 + diff 2", r$estimate[1] - r$estimate[2], r)
tline(r)

# Treatment-period interaction: each subject's total over the two periods,
# compared between the groups
r <- t.test(drug1 + placebo1, drug2 + placebo2, var.equal = TRUE, conf.level = confidence)
est("sum 1 - sum 2", r$estimate[1] - r$estimate[2], r)
tline(r)
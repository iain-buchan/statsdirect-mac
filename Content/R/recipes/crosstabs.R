# StatsDirect recipe: Crosstabs of two classifiers with the chi-square and exact tests, as the help shows them in R.
# From the help's R code (basic_descriptive_statistics/crosstabs.htm); the data and settings above come from the run.
# data: sex = c1, reaction = c2
# settings: confidence = cco

score <- function(v) {   # the row and column scores: the codes as numbers when they are numbers, else the levels in order
  n <- suppressWarnings(as.numeric(as.character(v)))
  if (anyNA(n[!is.na(v)])) as.numeric(factor(v)) else n
}
# Crosstabs: the StatsDirect help example (sex and grade of skin reaction to an
# antigen in 10 patients) in R, with the contingency table analysis that follows

# R's standard cross tabulation, with the percentages of each row and column
pct <- paste0(100 * confidence, "%")
tab <- table(Sex = sex, Reaction = reaction)
sex <- score(sex)
reaction <- score(reaction)
print(tab)
print(round(100 * prop.table(tab, 1), 2))       # % of row
print(round(100 * prop.table(tab, 2), 2))       # % of col
n <- sum(tab)
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}

# Nominal independence: Pearson's chi-square without Yates' correction (R warns
# about the small expected counts, as the report does), the likelihood ratio
# G-square, and the Fisher-Freeman-Halton exact test, which fisher.test gives
# for a table larger than 2 by 2
chi <- suppressWarnings(chisq.test(tab, correct = FALSE))
cat("Chi-square =", six(chi$statistic), " DF =", chi$parameter, " ", pv(chi$p.value),
    "\n")
g2 <- 2 * sum(tab * log(tab / chi$expected), na.rm = TRUE)   # 0 log 0 counts as 0
cat("G-square =", six(g2), " DF =", chi$parameter, " ",
    pv(pchisq(g2, chi$parameter, lower.tail = FALSE)), "\n")
cat("Fisher-Freeman-Halton exact", pv(fisher.test(tab)$p.value), "\n")
cat("Expected counts below 5:", sum(chi$expected < 5), "of", length(tab), "\n")

# ANOVA: a chi-square comparing the mean row score (the sex code) between the
# columns, (n - 1) times the between-column sum of squares over the total sum of
# squares, with the number of columns less 1 as its degrees of freedom
between <- sum(tapply(sex, reaction, function(v) length(v) * (mean(v) - mean(sex))^2))
chi_eq <- (n - 1) * between / sum((sex - mean(sex))^2)
df_eq <- ncol(tab) - 1
cat("Chi-square for equality of mean column scores =", six(chi_eq), " DF =", df_eq, " ",
    pv(pchisq(chi_eq, df_eq, lower.tail = FALSE)), "\n")

# Linear trend: the correlation between the row and column scores, and
# Mantel-Haenszel's chi-square (n - 1) r^2 with one degree of freedom
r <- cor(sex, reaction)
m2 <- (n - 1) * r^2
cat("Sample correlation (r) =", six(r), "\n")
cat("Chi-square for linear trend (M2) =", six(m2), " DF = 1 ",
    pv(pchisq(m2, 1, lower.tail = FALSE)), "\n")

# Nominal association: phi, Pearson's contingency coefficient and Cramer's V
x2 <- as.numeric(chi$statistic)
cat("Phi =", six(sqrt(x2 / n)), "\n")
cat("Pearson's contingency =", six(sqrt(x2 / (x2 + n))), "\n")
cat("Cramer's V =", six(sqrt(x2 / (n * (min(dim(tab)) - 1)))), "\n")

# Ordinal association: Goodman and Kruskal's gamma and Kendall's tau-b from the
# concordant and discordant pairs, each with two standard errors (Agresti 2002,
# Brown and Benedetti 1977): one for a test that the measure is 0, one under
# independence
o <- unclass(tab)
R <- nrow(o)
C <- ncol(o)
conc <- disc <- o * 0
for (i in 1:R) for (j in 1:C) {
  conc[i, j] <- sum(o[(1:R) > i, (1:C) > j]) + sum(o[(1:R) < i, (1:C) < j])
  disc[i, j] <- sum(o[(1:R) > i, (1:C) < j]) + sum(o[(1:R) < i, (1:C) > j])
}
cc <- sum(o * conc)                       # concordant pairs, counted twice
dc <- sum(o * disc)                       # discordant pairs, counted twice
gamma <- (cc - dc) / (cc + dc)
se_gamma <- 4 / (cc + dc)^2 * sqrt(sum(o * (dc * conc - cc * disc)^2))
v_ind <- sum(o * (conc - disc)^2) - (cc - dc)^2 / n
se_gamma_ind <- 2 / (cc + dc) * sqrt(v_ind)
rows <- rowSums(o)
cols <- colSums(o)
dr <- n^2 - sum(rows^2)
dcl <- n^2 - sum(cols^2)
taub <- (cc - dc) / sqrt(dr * dcl)
vij <- outer(rows, cols, function(a, b) a * dcl + b * dr)
vt <- sum(o * (2 * sqrt(dr * dcl) * (conc - disc) + taub * vij)^2) -
      n^3 * taub^2 * (dr + dcl)^2
se_taub <- sqrt(vt) / (dr * dcl)
se_taub_ind <- 2 * sqrt(v_ind / (dr * dcl))
z <- qnorm((1 + confidence) / 2)
show <- function(label, est, se) {
  cat(label, " SE =", six(se), " ", pv(2 * pnorm(-abs(est / se))),
      " 95% CI =", six(est - z * se), "to", six(est + z * se), "\n")
}
cat("Goodman-Kruskal gamma =", six(gamma), "\n")
show("Approximate test of gamma = 0:", gamma, se_gamma)
show("Approximate test of independence:", gamma, se_gamma_ind)
cat("Kendall tau-b =", six(taub), "\n")
show("Approximate test of tau-b = 0:", taub, se_taub)
show("Approximate test of independence:", taub, se_taub_ind)
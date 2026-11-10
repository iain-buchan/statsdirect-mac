# StatsDirect recipe: 2 by 2 chi-square test with and without the continuity correction, as the help shows it in R.
# From the help's R code (chi_square_tests/22.htm); the data and settings above come from the run.
# table: counts
# settings: confidence = cco, study = study_type, fisher = doFisher
# hand-edited: the confidence level and the data come from the run, as the header says

if (is.null(confidence) || !is.finite(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95

# 2 by 2 chi-square test: the StatsDirect help example (Armitage and Berry 1994, deaths
# among 257 patients given treatment A and 244 given treatment B) in R
pct <- paste0(100 * confidence, "%")
print(addmargins(counts))
n <- sum(counts)

# R's standard test: chisq.test applies Yates' continuity correction to a 2 by 2
# table by default and leaves it out when correct = FALSE. The expected values are
# the row total times the column total divided by n.
uncorrected <- chisq.test(counts, correct = FALSE)
yates <- chisq.test(counts, correct = TRUE)
print(uncorrected)
print(yates)

six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
x2 <- unname(uncorrected$statistic)
cat("Expected values:", six(t(uncorrected$expected)), "\n")
cat("Uncorrected Chi-square =", six(x2), " ", pv(uncorrected$p.value), "\n")
cat("Yates-corrected Chi-square =", six(unname(yates$statistic)), " ",
    pv(yates$p.value), "\n")

# Measures of association: Pearson's coefficient of contingency, and Cramer's V
# carrying the sign of ad - bc (negative here: fewer deaths with A than expected)
a <- counts[1, 1]
b <- counts[1, 2]
c <- counts[2, 1]
d <- counts[2, 2]
margins <- prod(rowSums(counts), colSums(counts))
cat("Pearson's contingency =", six(sqrt(x2 / (x2 + n))), "\n")
cat("Cramer's V (signed) =", six((a * d - b * c) / sqrt(margins)), "\n")

# Odds ratio analysis (a case-control study): the sample odds ratio ad/bc with
# Woolf's (logit) interval from the standard error of its logarithm
if (study == "casecontrol") {   # the odds ratio of a case-control study
or <- a * d / (b * c)
z <- qnorm((1 + confidence) / 2)
se <- sqrt(1 / a + 1 / b + 1 / c + 1 / d)
cat("Odds Ratio =", six(or), "\n")
cat("Approximate", pct, "confidence interval =", six(exp(log(or) - z * se)), "to",
    six(exp(log(or) + z * se)), "\n")
}
if (study == "cohort") {   # the relative risk of a cohort study, with the score limits of Koopman
n1 <- a + c
n2 <- b + d
p1 <- a / n1
p0 <- b / n2
rr <- p1 / p0
koopman <- function(x1, n1, x0, n0, level) {   # the score limits of the ratio of two proportions
  chi2 <- function(theta) {
    A <- (n0 + n1) * theta
    B <- -((x0 + n1) * theta + x1 + n0)
    q0 <- (-B - sqrt(B^2 - 4 * A * (x0 + x1))) / (2 * A)
    q1 <- theta * q0
    (x1 - n1 * q1)^2 / (n1 * q1 * (1 - q1)) * (1 + n1 * (theta - q1) / (n0 * (1 - q1)))
  }
  est <- (x1 / n1) / (x0 / n0)
  f <- function(lt) chi2(exp(lt)) - qchisq(level, 1)
  c(exp(uniroot(f, c(log(est) - 20, log(est)), tol = 1e-12)$root), exp(uniroot(f, c(log(est), log(est) + 20), tol = 1e-12)$root))
}
kl <- koopman(a, n1, b, n2, confidence)
cat("Relative risk =", six(rr), "\n")
cat("Approximate (Koopman)", pct, "confidence interval =", six(kl[1]), "to", six(kl[2]), "\n")

# As in the prospective risk report, invert the continuity-corrected sample-size
# formula for power. Use the uncorrected normal power if no root is bracketed.
alpha <- 1 - confidence
m <- n2 / n1
z <- qnorm(1 - alpha / 2)
pbar <- (p1 + m * p0) / (m + 1)
null_sd <- sqrt((1 + 1 / m) * pbar * (1 - pbar))
alt_sd <- sqrt(p0 * (1 - p0) / m + p1 * (1 - p1))
shift <- sqrt(n1) * (p0 - p1)
power <- pnorm((-z * null_sd - shift) / alt_sd) +
  pnorm((z * null_sd - shift) / alt_sd, lower.tail = FALSE)
if (p0 != p1 && is.finite(power) && power > alpha) {
  size_error <- function(power) {
    np <- ((z * null_sd + qnorm(power) * alt_sd) / (p0 - p1))^2
    (sqrt(np) + sqrt(np + 2 * (m + 1) / (m * abs(p0 - p1))))^2 / 4 - n1
  }
  bracket <- c(alpha, min(power, 1 - 1e-12))
  if (prod(vapply(bracket, size_error, numeric(1))) < 0)
    power <- uniroot(size_error, bracket, tol = 1e-10)$root
}
cat(sprintf("Approximate power (for %g%% significance) = %.2f%%\n", 100 * alpha, 100 * power))

# Miettinen and Nurminen score limits: estimate both risks under the constraint
# that they differ by delta, using the variance correction N / (N - 1).
risk_difference <- p1 - p0
miettinen_score <- function(delta) {
  loglik <- function(q0) {
    q1 <- q0 + delta
    dbinom(a, n1, q1, log = TRUE) + dbinom(b, n2, q0, log = TRUE)
  }
  q0 <- optimize(loglik, c(max(0, -delta), min(1, 1 - delta)), maximum = TRUE,
                 tol = 1e-12)$maximum
  q1 <- q0 + delta
  (risk_difference - delta)^2 /
    ((q1 * (1 - q1) / n1 + q0 * (1 - q0) / n2) * n / (n - 1)) - qchisq(confidence, 1)
}
risk_limits <- c(uniroot(miettinen_score, c(-1 + 1e-9, risk_difference), tol = 1e-12)$root,
                 uniroot(miettinen_score, c(risk_difference, 1 - 1e-9), tol = 1e-12)$root)
cat("Risk difference =", six(risk_difference), "\n")
cat("Approximate (Miettinen)", pct, "confidence interval =", six(risk_limits[1]), "to",
    six(risk_limits[2]), "\n")
}

# fisher.test: its P value is the two sided P by summation of the tables no more
# probable than the one observed, and alternative = "less" gives the one sided P for
# the lower tail (41 or fewer deaths with A). Its interval is the exact conditional
# one, agreeing with the report to four decimal places, and its estimate is the
# conditional maximum likelihood odds ratio rather than the sample odds ratio above.
if (isTRUE(fisher)) {   # the exact test, when the run asked for it
print(fisher.test(counts, conf.level = confidence))
cat("Exact Fisher one sided ", pv(fisher.test(counts, alternative = "less")$p.value),
    ", two sided ", pv(fisher.test(counts)$p.value), "\n", sep = "")
}

# The exact limits to six places, and the mid-P versions: with the margins fixed,
# a has the hypergeometric distribution weighted by psi^a at odds ratio psi. A limit
# is the psi at which one tail is 2.5%, counting the probability of the observed a
# in full (Fisher) or by half (mid-P). The one sided P is the smaller tail at psi = 1
# and the two sided mid-P is twice it.
if (study == "casecontrol") {   # the exact limits of the odds ratio
k <- max(0, a + b - (b + d)):min(a + b, a + c)     # the possible values of a
pr <- function(psi) {
  lw <- dhyper(k, a + c, b + d, a + b, log = TRUE) + k * log(psi)   # on the log scale
  w <- exp(lw - max(lw))
  w / sum(w)
}
lower <- function(psi, w) sum(pr(psi)[k < a]) + w * pr(psi)[k == a]
upper <- function(psi, w) sum(pr(psi)[k > a]) + w * pr(psi)[k == a]
limit <- function(tail, w) {
  uniroot(function(psi) tail(psi, w) - (1 - confidence) / 2, c(0.001, 1000), tol = 1e-10)$root
}
cat("Fisher exact", pct, "confidence interval =", six(limit(upper, 1)), "to",
    six(limit(lower, 1)), "\n")
cat("mid-P exact", pct, "confidence interval =", six(limit(upper, 0.5)), "to",
    six(limit(lower, 0.5)), "\n")
mid <- min(lower(1, 0.5), upper(1, 0.5))
cat("Exact mid-P one sided ", pv(mid), ", two sided ", pv(min(1, 2 * mid)), "\n",
    sep = "")
}

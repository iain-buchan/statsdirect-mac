# StatsDirect recipe: Cuzick trend test across ordered groups, as the help shows it in R.
# From the help's R code (nonparametric_methods/cuzick.htm); the data and settings above come from the run.
# data: mets... = data, score = scores

# Cuzick's trend test: the StatsDirect help example (Cuzick 1985) in R
mets <- lapply(mets, function(v) v[!is.na(v)])    # missing values are left out

# R has no standard function for this test. It is a Wilcoxon-type test for trend
# across ordered groups: T is the sum over all observations of group score
# times rank, compared with its expectation under no trend.
y <- unlist(mets)
z <- rep(score, lengths(mets))            # each observation's group score
N <- length(y)
r <- rank(y)                              # tied values share a mid-rank
Tstat <- sum(z * r)
Ez <- mean(z)
ET <- (N + 1) / 2 * sum(z)
varz <- mean(z^2) - Ez^2
varT <- N^2 * (N + 1) / 12 * varz
ties <- table(y)
varTties <- varT * (1 - sum(ties^3 - ties) / (N^3 - N))
cat("Groups =", length(mets), "  Observations =", N, "\n")
cat(sprintf("Ez = %.6f   Var(z) = %.5f\n", Ez, varz))
cat(sprintf("T = %g   ET = %g   Var(T) = %.6f\n", Tstat, ET, varT))
for (v in c(varT, varTties)) {
  zstat <- (Tstat - ET) / sqrt(v)
  cat(sprintf("%sz = %.6f   One sided P = %.4f   Two sided P = %.4f\n",
              if (v == varT) "" else sprintf("Corrected for ties: VarT = %.6f   ", v),
              zstat, pnorm(-abs(zstat)), 2 * pnorm(-abs(zstat))))
}
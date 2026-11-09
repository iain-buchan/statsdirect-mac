# StatsDirect recipe: Tests of normality, as the help shows them in R.
# From the help's R code (parametric_methods/normality.htm); the data and settings above come from the run.
# data: yield
# repeat: data

# Normality tests: the StatsDirect help example (30 penicillin yields) in R
yield <- yield[!is.na(yield)]
n <- length(yield)
sw <- NULL
Wf <- psf <- skew <- kurt <- pk <- NA_real_

# R's standard test gives the Shapiro-Wilk W and its P (Royston 1995), as
# StatsDirect reports them.
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
if (n < 2 || !is.finite(sd(yield)) || sd(yield) == 0) {
  cat("Sample size", n, " Mean", six(mean(yield)), " Standard deviation", six(sd(yield)), "\n")
  cat("Normality cannot be tested: too few values, no variation, or values too large for R's variance.\n")
} else {
sw <- if (n >= 3 && n <= 5000) shapiro.test(yield) else NULL
if (!is.null(sw)) print(sw) else
  cat("Shapiro-Wilk test not calculated in base R: it requires 3 to 5000 values.\n")
if (!is.null(sw) && n > 2000) cat("Shapiro-Wilk P is unreliable above 2000 observations.\n")
ln <- log(n)
cat("Sample size", n, "  Mean", six(mean(yield)), "  Standard deviation",
    six(sd(yield)), "\n")

# Scaled deviations avoid overflow/underflow in third and fourth moments.
# Skewness and kurtosis do not depend on this scale.
moment_scale <- max(abs(yield - mean(yield)))
u <- (yield - mean(yield)) / moment_scale
m2 <- mean(u^2)
m3 <- mean(u^3)
m4 <- mean(u^4)
skew <- m3 / m2^1.5
kurt <- m4 / m2^2

if (n >= 8) {
# Test of skewness (D'Agostino 1970), needing at least 8 observations
y <- skew * sqrt((n + 1) * (n + 3) / (6 * (n - 2)))
beta2 <- 3 * (n^2 + 27 * n - 70) * (n + 1) * (n + 3) /
         ((n - 2) * (n + 5) * (n + 7) * (n + 9))
w2 <- -1 + sqrt(2 * (beta2 - 1))
z1 <- asinh(y / sqrt(2 / (w2 - 1))) / sqrt(log(sqrt(w2)))
cat("Skewness", paste0(six(skew), ","), pv(2 * pnorm(-abs(z1))), "\n")

# Test of kurtosis (Anscombe and Glynn 1983)
xx <- (kurt - 3 * (n - 1) / (n + 1)) /
      sqrt(24 * n * (n - 2) * (n - 3) / ((n + 1)^2 * (n + 3) * (n + 5)))
mo <- 6 * (n^2 - 5 * n + 2) / ((n + 7) * (n + 9)) *
      sqrt(6 * (n + 3) * (n + 5) / (n * (n - 2) * (n - 3)))
a <- 6 + 8 / mo * (2 / mo + sqrt(1 + 4 / mo^2))
wh <- (1 - 2 / a) / (1 + xx * sqrt(2 / (a - 4)))
z2 <- if (wh > 0) (1 - 2 / (9 * a) - wh^(1 / 3)) / sqrt(2 / (9 * a)) else Inf
cat("Kurtosis", paste0(six(kurt), ","), pv(2 * pnorm(-abs(z2))), "\n")

# Omnibus test: K2 = Z1^2 + Z2^2 (D'Agostino, Belanger and D'Agostino 1990) with
# Royston's (1991) correction, which makes it closer to chi-square with 2 df.
# The corrected K2 is -2 log P.
zc <- -qnorm(-(z1^2 + z2^2) / 2, log.p = TRUE)     # K2's P as a normal deviate
cut <- 0.55 * n^0.2 - 0.21
a1 <- (-5 + 3.46 * ln) * exp(-1.37 * ln)
b1 <- 1 + (0.854 - 0.148 * ln) * exp(-0.55 * ln)
b2 <- 2.13 / (1 - 2.37 * ln)
zr <- if (zc < -1) zc else if (zc < cut) a1 + b1 * zc else
      a1 - b2 * cut + (b2 + b1) * zc
log_pk <- pnorm(-zr, log.p = TRUE)
pk <- exp(log_pk)
cat("Royston chi-sq", paste0(six(-2 * log_pk), ","), pv(pk), "\n")

} else {
  cat("Skewness", six(skew), " Kurtosis", six(kurt), "\n")
  cat("Skewness, kurtosis and omnibus P values require at least 8 observations.\n")
}

# StatsDirect adds V = (1 - W) / its null median (Royston's approximations).
if (!is.null(sw)) {
  median_1w <- if (n == 3) {
    1 - sin(pi / 12 + asin(sqrt(0.75)))^2
  } else if (n <= 11) {
    mu <- 0.544 + n * (-0.39978 + n * (0.025054 - n * 0.0006714))
    exp(n * 0.459 - 2.273 - exp(-mu))
  } else {
    exp(-1.5861 + ln * (-0.31082 + ln * (-0.083751 + ln * 0.0038915)))
  }
  cat("Shapiro-Wilk W", paste0(six(sw$statistic), ","),
      "V =", paste0(six((1 - sw$statistic) / median_1w), ","), pv(sw$p.value), "\n")
}

# Shapiro-Francia W': the squared correlation between the ordered values and
# Blom's normal scores for their positions, with P and V' from Royston's (1983)
# normalising transformation
if (n >= 5) {
x <- sort(yield)
m <- qnorm((1:n - 0.375) / (n + 0.25))
Wf <- cor(x, m)^2
h <- ln - 5
l <- -0.0480157 + h * (0.01971964 - 0.0119065 * h^2)
mf <- -exp(1.6930674 + h * (0.1441647 + h * (-0.01849276 + h * (0.031074485 +
                                                                  h * 0.0055717663))))
f <- exp(-0.510725 + h * (-0.1160364 + h * (-0.006702098 + h * (0.054465944 +
                                                                  h * 0.0087397329))))
psf <- pnorm(-(((1 - Wf)^l - 1) / l - mf) / f)
cat("Shapiro-Francia W'", paste0(six(Wf), ","),
    "V' =", paste0(six((1 - Wf) / (l * mf + 1)^(1 / l)), ","), pv(psf), "\n")
if (n > 5000) cat("Shapiro-Francia P is unreliable above 5000 observations.\n")

} else {
  Wf <- psf <- NA_real_
  cat("Shapiro-Francia test requires at least 5 observations.\n")
}

# StatsDirect's conclusion, from the smaller of the last two P values
test_p <- c(if (!is.null(sw)) sw$p.value, psf)
test_p <- test_p[is.finite(test_p)]
p <- if (length(test_p)) min(test_p) else NA_real_
cat(if (is.na(p)) "Too few observations for the tests (at least 3 are needed)"
    else if (p < 0.05) "Sample unlikely to be from a normal distribution"
    else if (p < 0.1) "Tests not quite significant but do not assume normality"
    else "No non-normality detected by tests: examine plot", "\n")

# The normal plot at the end of the report: each value against its Blom normal
# score put on the scale of the data (mean + z sd, with sd taken over n), and the
# line of equality
z <- qnorm((rank(yield) - 0.375) / (n + 0.25))
expected <- mean(yield) + z * moment_scale * sqrt(m2)
lim <- range(expected, yield)
if (!exists("yield_title")) yield_title <- "Sample"
plot(expected, yield, xlim = lim, ylim = lim, xlab = paste0("Normal (", yield_title, ")"),
     ylab = paste0("Observed (", yield_title, ")"))
abline(0, 1)
}

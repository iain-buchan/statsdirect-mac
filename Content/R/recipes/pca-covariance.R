# StatsDirect recipe: Principal components of the covariance matrix and scale reliability, as the help shows them in R.
# From the help's R code (regression_and_correlation/pca.htm); the data and settings above come from the run.
# data: q... = data
# settings: correct = correctForReversal, confidence = ci
# hand-edited: omit incomplete subjects before components and reliability estimates

q <- as.data.frame(q, check.names = FALSE)
q <- q[complete.cases(q), , drop = FALSE]
# Principal components and scale reliability: the StatsDirect help example (four
# questionnaire items answered by 60 people) in R. The data are the test workbook's
# Agreement worksheet columns Question 1 to 4.
if (is.null(names(q)) || any(names(q) == "")) names(q) <- paste("Item", seq_along(q))

# Items that load on the first component with the opposite sign to the first item
# are reversed, as the report did for questions 3 and 4, so that all the items
# point the same way (a component's sign is arbitrary, so the first item fixes
# it); then R's standard principal components analysis of the correlation matrix
if (isTRUE(correct)) {   # items whose first loading has the other sign are reversed, when the run asked
  loading1 <- prcomp(q, scale. = FALSE)$rotation[, 1]
  reverse <- which(sign(loading1) != sign(loading1[1]))
  reversed <- names(q)[reverse]
  cat("Sign was reversed for:", paste(reversed, collapse = "; "), "\n")
  for (j in reverse) q[[j]] <- max(q[[j]]) + min(q[[j]]) - q[[j]]
}
pc <- prcomp(q, scale. = FALSE)
print(summary(pc))

# The report's table to 6 places: the eigenvalues are the squared singular values
# over n - 1, with their proportions of the total variance
six <- function(x) ifelse(is.na(x), "*", formatC(x, digits = 6, format = "f", drop0trailing = TRUE))
eig <- pc$sdev^2
pct <- function(x) {
  paste0(formatC(100 * x, digits = 2, format = "f", drop0trailing = TRUE), "%")
}
for (i in seq_along(eig)) {
  cat(i, six(eig[i]), pct(eig[i] / sum(eig)), pct(cumsum(eig)[i] / sum(eig)), "\n")
}

# Cronbach's alpha of the four items, from the raw scores and from the standardised
# scores, its one-sided lower confidence limit (Feldt 1965: 1 - (1 - alpha)
# times the selected F quantile on n - 1 and (n - 1)(k - 1) df), and alpha with
# each item dropped
alpha <- function(x) {
  k <- ncol(x)
  if (k < 2) return(NA_real_)             # reliability needs at least two items
  k / (k - 1) * (1 - sum(apply(x, 2, var)) / var(rowSums(x)))
}
n <- nrow(q)
if (is.null(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95
k <- ncol(q)
for (kind in c("raw", "standardized")) {
  x <- if (kind == "raw") q else as.data.frame(scale(q))
  a <- alpha(x)
  lower <- 1 - (1 - a) * qf(confidence, n - 1, (n - 1) * (k - 1))
  if (lower < 0 || lower > a) lower <- 0
  cat("With", kind, "variables: Scale reliability alpha =", six(a),
      paste0("(", 100 * confidence, "% lower confidence limit ="), six(lower), ")\n")
  for (j in 1:k) {
    aj <- alpha(x[, -j, drop = FALSE])
    cat("  Question", j, "dropped:", six(aj), " change", six(aj - a), "\n")
  }
}

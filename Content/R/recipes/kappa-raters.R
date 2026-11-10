# StatsDirect recipe: Kappa agreement of more than two raters from their responses.
# data: ratings... = responses
# settings: confidence = ci, saved_grades = kappaGrades

# Agreement of more than two raters: a row for each subject and a column for each rater, with
# an empty cell where a rater did not rate the subject.  With two categories this is the kappa
# of Fleiss and Cuzick (1979), which allows subjects to have different numbers of ratings.
# With more it is the kappa of each category against the rest (Landis and Koch 1977) and the
# kappa of all the categories, with the standard errors of Fleiss, Nee and Landis (1979) when
# every subject has the same number of ratings
if (is.null(confidence) || !is.finite(confidence) || confidence <= 0 || confidence >= 1) confidence <- 0.95
subjects <- max(lengths(ratings))
ratings <- do.call(cbind, lapply(ratings, function(r) as.character(r)[seq_len(subjects)]))
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
pv <- function(p) {
  if (p < 0.0001) "P < 0.0001" else
    paste("P =", formatC(p, digits = 4, format = "f", drop0trailing = TRUE))
}
pct <- paste0(100 * confidence, "%")
z_ci <- qnorm((1 + confidence) / 2)

# the number of ratings of each subject (m), the number of subjects with a rating (n), and the
# mean and the harmonic mean of the numbers of ratings of those subjects
m <- rowSums(!is.na(ratings))
rated <- m > 0
n <- sum(rated)
mbar <- sum(m) / n
mbarh <- n / sum(1 / m[rated])
constant <- min(m[rated]) == max(m)
categories <- kappa_grade_order(ratings, saved_grades)
cat("General agreement over all (", length(categories), ") categories with ",
    if (constant) max(m) else paste0(min(m[rated]), " to ", max(m), " (median ", six(median(m)), ")"),
    " raters per subject\n\n", sep = "")

# kappa of a category against the rest, from the mean squares between and within subjects of
# the number of a subject's ratings that are in the category (Fleiss and Cuzick 1979); p is
# the proportion of all the ratings that are in the category
kappa_of <- function(category) {
  x <- rowSums(!is.na(ratings) & ratings == category)
  p <- sum(x) / (n * mbar)
  between <- sum(((x - m * p)^2 / m)[rated]) / n
  within <- sum((x * (m - x) / m)[rated]) / (n * (mbar - 1))
  c(kappa = (between - within) / (between + (mbar - 1) * within), p = p)
}

if (length(categories) < 2) {
  cat("Kappa is not defined: the raters used fewer than two categories\n")
} else if (length(categories) == 2) {
  first <- kappa_of(categories[1])
  kappa <- first[["kappa"]]
  p <- first[["p"]]
  q <- 1 - p
  # the standard error when there is no agreement beyond chance; the test and the interval
  # are both made with it
  se <- sqrt(2 * (mbarh - 1) + (mbar - mbarh) * (1 - 4 * p * q) / (mbar * p * q)) /
    ((mbar - 1) * sqrt(n * mbarh))
  # With the same m ratings per subject the lower bound is -1/(m - 1);
  # with a varying number of ratings use -1.
  lower <- max(if (constant) -1 / (max(m) - 1) else -1, kappa - z_ci * se)
  upper <- min(1, kappa + z_ci * se)
  cat("Cohen's kappa (Fleiss-Cuzick extension)\n")
  cat("Kappa = ", six(kappa), " (se = ", six(se), ")\n", sep = "")
  cat(pct, "confidence interval =", six(lower), "to", six(upper), "\n")
  cat("z (for k = 0) =", six(kappa / se), " ", pv(pnorm(kappa / se, lower.tail = FALSE)), "\n")
} else {
  each <- vapply(categories, kappa_of, c(kappa = 0, p = 0))
  kappa_j <- each["kappa", ]
  p <- each["p", ]
  q <- 1 - p
  # the kappa of all the categories is the mean of the categories' kappas weighted by p q
  kappa <- sum(p * q * kappa_j) / sum(p * q)
  cat("Cohen's kappa (Landis-Koch extension)\n")
  if (constant) {
    # the standard errors when there is no agreement beyond chance and every subject has
    # the same number of ratings
    mm <- max(m)
    se_j <- sqrt(2 / (n * mm * (mm - 1)))
    se <- sqrt(2) / (sum(p * q) * sqrt(n * mm * (mm - 1))) * sqrt(sum(p * q)^2 - sum(p * q * (q - p)))
    lower <- max(-1 / (mm - 1), kappa - z_ci * se)
    upper <- min(1, kappa + z_ci * se)
    print(data.frame(Response = categories, Kappa = six(kappa_j), se = six(se_j), z = six(kappa_j / se_j),
                     Probability = vapply(pnorm(kappa_j / se_j, lower.tail = FALSE), pv, "")),
          row.names = FALSE)
    cat("\nCombined (Fleiss-Nee-Landis test)\n")
    cat("Kappa =", six(kappa), "\n")
    cat(pct, "confidence interval =", six(lower), "to", six(upper), "\n")
    cat("z (for k = 0) =", six(kappa / se), " ", pv(pnorm(kappa / se, lower.tail = FALSE)), "\n")
  } else {
    print(data.frame(Response = categories, Kappa = six(kappa_j)), row.names = FALSE)
    cat("\nCombined\n")
    cat("Kappa =", six(kappa), "\n")
    cat("The number of ratings per subject is not constant, so the tests and the confidence interval do not apply\n")
  }
}

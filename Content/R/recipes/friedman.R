# StatsDirect recipe: Friedman or Cochran Q for selected blocks and treatments.
# matrix: grass
# hand-edited: selected data only; incomplete blocks are omitted as in StatsDirect.

grass <- grass[complete.cases(grass), , drop = FALSE]
b <- nrow(grass); k <- ncol(grass)
if (b < 2L || k < 2L) stop("At least two complete blocks and two treatments are required.")
r <- t(apply(grass, 1L, rank, ties.method = "average"))
R <- colSums(r); A1 <- sum(r^2)
denominator <- A1 - b * k * (k + 1)^2 / 4
if (denominator <= 0) stop("The selected blocks contain no rank variation.")
T1 <- (k - 1) * sum((R - b * (k + 1) / 2)^2) / denominator
T2 <- (b - 1) * T1 / (b * (k - 1) - T1)
binary <- all(grass %in% c(0, 1))
p <- if (binary) pchisq(T1, k - 1, lower.tail = FALSE) else
  pf(T2, k - 1, (b - 1) * (k - 1), lower.tail = FALSE)
friedman_result <- c(n = b, k = k, a2 = A1, t1 = T1, t2 = T2, p = p)
cat(if (binary) "Cochran Q test\n" else "Friedman test (Iman-Davenport F approximation)\n")
print(friedman_result)
cat("Mean ranks:\n"); print(R / b)
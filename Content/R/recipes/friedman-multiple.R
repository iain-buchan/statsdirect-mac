# StatsDirect recipe: selected Friedman multiple comparisons.
# matrix: grass
# settings: confidence = confidence, sided = sided
# hand-edited: selected confidence, sidedness, treatments and complete blocks.

grass <- grass[complete.cases(grass), , drop = FALSE]
b <- nrow(grass); k <- ncol(grass)
if (b < 2L || k < 2L) stop("At least two complete blocks and two treatments are required.")
r <- t(apply(grass, 1L, rank, ties.method = "average"))
R <- colSums(r); A1 <- sum(r^2)
if (A1 - b * k * (k + 1)^2 / 4 <= 0) stop("The selected blocks contain no rank variation.")
confidence <- as.numeric(confidence); sided <- as.integer(sided)
if (length(confidence) != 1L || !is.finite(confidence) || confidence <= 0 || confidence >= 1)
  stop("The saved multiple comparison has no valid confidence level.")
if (length(sided) != 1L || is.na(sided) || !sided %in% 1:2) stop("Select one- or two-sided comparisons.")
df <- (b - 1) * (k - 1)
se <- sqrt(abs(2 * (b * A1 - sum(R^2)) / df))
critical_t <- qt(1 - (1 - confidence) / sided, df)
critical_difference <- se * critical_t
labels <- colnames(grass)
if (is.null(labels)) labels <- paste("Treatment", seq_len(k))
pairs <- combn(k, 2L)
difference <- R[pairs[1L, ]] - R[pairs[2L, ]]
pair_p <- sided * pt(-abs(difference) / se, df)
friedman_comparisons <- data.frame(first = labels[pairs[1L, ]], second = labels[pairs[2L, ]],
  difference = difference, p = pair_p, significant = abs(difference) > critical_difference)
cat(100 * confidence, "% confidence;", sided, "sided; critical t =", critical_t,
    "; critical difference =", critical_difference, "\n")
print(friedman_comparisons, row.names = FALSE)
# Enter counts, not percentages; each independent observational unit contributes once.
# Sparse expected counts can make the asymptotic chi-square approximation unreliable.
# Paired or clustered observations require an analysis that respects that dependence.
if (!is.null(parameters$counts)) {
  counts <- do.call(rbind, lapply(parameters$counts, unlist))
  dimnames(counts) <- list(unlist(parameters$rowLabels), unlist(parameters$columnLabels))
} else {
  columns <- if (!is.null(data_frames$data)) sd_columns() else sd_columns("scrap")
  counts <- sd_matrix(lapply(columns, sd_numeric))
}
stopifnot(all(is.finite(counts)), all(counts >= 0), all(rowSums(counts) > 0), all(colSums(counts) > 0))
result <- chisq.test(counts, correct = FALSE)
print(result)
expected <- result$expected
cell_chi_square <- (counts - expected)^2 / expected
print(expected)
print(cell_chi_square)
positive <- counts > 0
G <- 2 * sum(counts[positive] * log(counts[positive] / expected[positive]))
print(c(G = G, df = unname(result$parameter), p.value = pchisq(G, result$parameter, lower.tail = FALSE)))
if (isTRUE(sd_parameter("show_pc", FALSE))) print(100 * prop.table(counts))
if (identical(dim(counts), c(2L, 2L))) {
  print(chisq.test(counts, correct = TRUE))
}
if (operation %in% c("ExactFisher", "ExactFisherX", "ExactORCML") ||
    isTRUE(sd_parameter("doExact", FALSE)) || isTRUE(sd_parameter("doFisher", FALSE))) {
  # Exact networks can exceed R's workspace; report this rather than silently simulate.
  exact_result <- tryCatch(fisher.test(counts, conf.level = confidence), error = function(e) {message(conditionMessage(e)); NULL})
  print(exact_result)
}
if (isTRUE(sd_parameter("doMonteCarlo", FALSE))) {
  set.seed(sd_parameter("seed", 12345))
  # Same conditional null model, but R and StatsDirect use different simulation streams.
  simulation <- chisq.test(counts, simulate.p.value = TRUE, B = sd_parameter("iterations", 1000000))
  print(simulation)
}
# Trend tests, mid-P and additional risk estimates in the StatsDirect report are not reproduced here.

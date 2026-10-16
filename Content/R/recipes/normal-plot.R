# StatsDirect recipe: one normal-scores chart using the selected method and scaling.
# data: observed = X
# settings: chart = chartSettings
# hand-edited: use final chart choices, without additional teaching plots or tests.

normal_original_chart <- chart
observed <- observed[!is.na(observed)]
if (!length(observed) || any(!is.finite(observed)))
  stop("A normal plot needs finite numeric observations.")
normal_method <- as.integer(sd_chart_get("method", 1L))
if (length(normal_method) != 1L || is.na(normal_method) || !normal_method %in% 1:3)
  stop("Unknown normal-score method.")
normal_scaled <- isTRUE(sd_chart_get("scaleZ", FALSE))
n <- length(observed)
if (normal_method == 3L && n > 4000L) {
  normal_method <- 1L
  message("Expected normal order scores use van der Waerden scores above 4000 observations, as in StatsDirect.")
}
normal_ranks <- rank(observed, ties.method = "average")
# E[Z_(r)] = E[qnorm(Beta(r,n+1-r))]. Integrating over uniform probability
# avoids underflow of the beta density for large n and shares exact mid-rank ties.
normal_expected_order <- function(r, n) {
  if (2 * r == n + 1L) return(0)
  sign <- if (r > (n + 1L) / 2) 1 else -1
  k <- min(r, n + 1L - r)
  sign * -integrate(function(u) qnorm(qbeta(u, k, n + 1L - k)), 0, 1,
                    rel.tol = 1e-9, subdivisions = 300L)$value
}
if (normal_method == 1L) normal_scores <- qnorm(normal_ranks / (n + 1))
if (normal_method == 2L) normal_scores <- qnorm((normal_ranks - 0.375) / (n + 0.25))
if (normal_method == 3L) {
  needed <- sort(unique(c(floor(normal_ranks), ceiling(normal_ranks))))
  orders <- setNames(vapply(needed, normal_expected_order, 0.0, n = n), needed)
  normal_scores <- (orders[as.character(floor(normal_ranks))] + orders[as.character(ceiling(normal_ranks))]) / 2
  normal_scores <- unname(normal_scores)
}
data_title <- sd_chart_strings(sd_chart_get("dataTitles", "Selected data"))[1L]
if (is.na(data_title) || !nzchar(data_title)) data_title <- "Selected data"
normal_x_title <- c("Normal scores (van der Waerden)", "Normal scores (Blom)",
                     "Expected normal order scores")[normal_method]
if (normal_scaled) {
  normal_scores <- mean(observed) + normal_scores * sqrt(mean((observed - mean(observed))^2))
  normal_x_title <- paste0("Normal (", data_title, ")")
}
if (is.list(chart)) {
  # Native normal plots derive these labels from the selected column and method;
  # their chart dialog does not expose generic axis-title boxes.
  chart$xTitle <- normal_x_title
  chart$yTitle <- paste0("Observed (", data_title, ")")
}
limits_x <- range(normal_scores); limits_y <- range(observed)
if (normal_scaled) limits_x <- limits_y <- range(limits_x, limits_y)
sd_chart_frame(limits_x, limits_y, "Normal plot", normal_x_title,
               paste0("Observed (", data_title, ")"))
marker <- sd_chart_marker(1L)
sd_chart_points(normal_scores, observed, marker)
if (normal_scaled) abline(0, 1, lwd = sd_chart_get("lineWidth", 1))
sd_chart_finish()
chart <- normal_original_chart

# Helpers preserve unequal group sizes; rows are aligned only for matched analyses.
sd_columns <- function(name = "data") {
  x <- data_frames[[name]]
  if (is.null(x)) stop(paste("Missing input:", name))
  x
}
sd_numeric <- function(x) {
  if (!is.numeric(x)) stop("This R recipe requires numeric columns; the original data have been retained.")
  x
}
sd_matrix <- function(x) {
  n <- max(lengths(x))
  do.call(cbind, lapply(x, function(v) { length(v) <- n; v }))
}
sd_parameter <- function(name, default = NULL) {
  value <- parameters[[name]]
  if (is.null(value) || (is.list(value) && isTRUE(value$skip))) default else value
}
confidence <- sd_parameter("gamma", sd_parameter("cco", sd_parameter("ci", 0.95)))

# StatsDirect recipe: Kaplan-Meier survival estimates, as the help shows them in R.
# From the help's R code (survival_analysis/kaplan_meier.htm); the data and settings above come from the run.
# data: time = times, event = deaths, group = groups
# settings: confidence = gamma
# settings: show_tics = use-tics, show_markers = use-markers

if (is.null(group)) group <- rep(1, length(time))
# Older records use the dialog defaults: censorship tics on, event markers off.
if (!exists("show_tics", inherits = FALSE) || is.null(show_tics)) show_tics <- TRUE
if (!exists("show_markers", inherits = FALSE) || is.null(show_markers)) show_markers <- FALSE
# Kaplan-Meier survival estimates: the StatsDirect help example (a hypothetical study
# of death from cancer in two groups of rats given different pre-treatments; the test
# workbook's Survival worksheet columns Group Surv, Time Surv and Censor Surv) in R
pct <- paste0(100 * confidence, "%")
if (!requireNamespace("survival", quietly = TRUE)) install.packages("survival", repos = "https://cloud.r-project.org")
library(survival)

# The groups in the order in which they first occur, as StatsDirect lists them
g <- factor(group, levels = unique(group))

# R's standard estimate: survfit gives the product limit estimate of S with Greenwood's
# variance. conf.type = "plain" makes its limits S +/- z SE(S), the scale on which the
# Brookmeyer-Crowley interval for the median is set (R's default is the log scale).
# print(fit) gives the median, the Brookmeyer-Crowley limits for it and, with
# rmean = "individual", the mean survival time restricted to each group's own longest
# time, as in the report.
fit <- survfit(Surv(time, event) ~ g, conf.type = "plain", conf.int = confidence)
print(fit, rmean = "individual")
print(summary(fit, censored = TRUE))

# The report's tables: every distinct time, with the cumulative hazard H = -ln(S)
# (Peterson) and its standard error from Greenwood's sum, which is SE(S) / S
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
z <- qnorm((1 + confidence) / 2)
s <- summary(fit, censored = TRUE)
H <- log(1 / s$surv)
means <- summary(fit, rmean = "individual")$table
# survfit returns a vector for one group and confidence-specific column names.
if (is.null(dim(means))) means <- matrix(means, nrow = 1L, dimnames = list("All", names(means)))
strata <- if (is.null(s$strata)) rep(rownames(means)[1L], length(s$time)) else as.character(s$strata)
median_limits <- grep("LCL$|UCL$", colnames(means))
for (k in rownames(means)) {
  i <- strata == k
  t <- s$time[i]
  n <- s$n.risk[i]
  d <- s$n.event[i]
  S <- s$surv[i]
  seS <- s$std.err[i]
  seH <- sqrt(cumsum(d / (n * (n - d))))   # infinite once S reaches 0
  cat("\nGroup Surv =", sub("^g=", "", k), "\n")
  print(data.frame(Time = t, "At risk" = n, Dead = d, Censored = s$n.censor[i],
                   S = six(S), "SE(S)" = ifelse(S > 0, six(seS), "*"),
                   H = ifelse(S > 0, six(H[i]), "infinity"),
                   "SE(H)" = ifelse(S > 0, six(seH), "*"), check.names = FALSE),
        row.names = FALSE)

  # The median: the first time at which S is 0.5 or below. Where S is exactly 0.5 from
  # that time to the next death time, the median is the midpoint of the two times (this
  # example has no run of S exactly 0.5)
  m <- which(S <= 0.5)[1]
  med <- means[k, "median"]
  # (a group whose S never falls to 0.5 has no median; the two intervals below need one)
  cat("Median survival time =", med, "\n")

  # Andersen's interval: the median +/- z SE(S at the median) / f, where f estimates the
  # density of the survival times at the median by the slope of S between the last time
  # with S >= 0.5 + 0.05 and the first time with S <= 0.5 - 0.05 (the margin of 0.05
  # is the same at every confidence level)
  hi <- which(S >= 0.55)
  lo <- which(S <= 0.45)
  andersen <- c(NA_real_, NA_real_)
  if (is.finite(med) && length(hi) && length(lo)) {
    hi <- max(hi); lo <- min(lo)
    f <- (S[hi] - S[lo]) / (t[lo] - t[hi])
    if (is.finite(f) && f > 0) andersen <- med + c(-1, 1) * z * seS[m] / f
  }
  cat("Andersen", pct, "CI for median survival time =", six(andersen[1]), "to",
      six(andersen[2]), "\n")

  # Brookmeyer-Crowley: the first times at which the lower and the upper confidence
  # limits of S are 0.5 or below. The times from the lower limit up to the upper are
  # those whose S is within z standard errors of 0.5, so the interval runs up to the
  # death time that follows the last of them. NA is a limit that the data do not
  # reach, which the report prints as infinity
  bc <- means[k, median_limits]
  cat("Brookmeyer-Crowley", pct, "CI for median survival time =", bc[1], "to", bc[2], "\n")

  # The mean survival time (the area under S up to the longest time), with the
  # standard error R gives it multiplied by sqrt(m / (m - 1)) for m deaths, the
  # correction of Hosmer and Lemeshow (1999) that StatsDirect applies
  deaths <- means[k, "events"]   # the factor needs at least two deaths
  mu <- means[k, "rmean"]
  se <- means[k, "se(rmean)"] * sqrt(deaths / (deaths - 1))
  last_death <- if (any(d > 0)) max(t[d > 0]) else NA_real_
  lim <- ""
  if (is.finite(last_death) && max(t) > last_death) lim <- sprintf("[limit: %s on %s] ", max(t), last_death)
  cat(sprintf("Mean survival time (%s CI) %s= %s (%s to %s)\n", pct, lim, six(mu),
              six(mu - z * se), six(mu + z * se)))
}

# Mark only actual observations: a tick at censorship-only times and a point at
# event times, using the same selections on each finite diagnostic transform.
km_marks <- function(x, y, keep, colour) {
  censored <- keep & s$n.censor > 0 & s$n.event == 0
  died <- keep & s$n.event > 0
  if (isTRUE(show_tics) && any(censored)) points(x[censored], y[censored], pch = "|", col = colour)
  if (isTRUE(show_markers) && any(died)) points(x[died], y[died], pch = 16, col = colour)
}
plot(fit, mark.time = FALSE, col = seq_along(levels(g)), xlab = "Times", ylab = "Survivor",
     main = "Survival Plot (PL estimates)")
for (j in seq_len(nrow(means))) km_marks(s$time, s$surv, strata == rownames(means)[j], j)
legend("topright", levels(g), col = seq_along(levels(g)), lty = 1, title = "Group Surv", bty = "n")


# StatsDirect includes these four diagnostic curves with its survival analysis.
# Keep the useful transformations; ordinary R lines draw them without custom graphics.
km_plot <- function(x, y, xlab, ylab, main, from = NULL) {
  valid <- is.finite(x) & is.finite(y)
  if (!any(valid)) return(invisible(NULL))
  plot(range(x[valid]), range(c(y[valid], from)), type = "n", xlab = xlab, ylab = ylab, main = main)
  for (j in seq_len(nrow(means))) {
    keep <- valid & strata == rownames(means)[j]
    if (!any(keep)) next
    xx <- x[keep]; yy <- y[keep]
    if (!is.null(from)) { xx <- c(min(x[valid]), xx); yy <- c(from, yy) }
    lines(xx, yy, type = "s", col = j)
    km_marks(x, y, keep, j)
  }
  legend("topleft", levels(g), col = seq_along(levels(g)), lty = 1, bty = "n")
}
km_plot(s$time, H, "Times", "Hazard", "Hazard Plot", from = 0)
km_plot(log(s$time), log(H), "Log Times", "Log Hazard", "Log Hazard Plot")
km_plot(log(s$time), qnorm(s$surv), "Log Times", "Z (Survivor)", "Lognormal Survival Plot")
km_plot(s$time, H / s$time, "Times", "Hazard / Time", "Hazard Rate Plot")

# StatsDirect recipe: Time series summary of repeated measurements, as the help shows it in R.
# From the help's R code (basic_descriptive_statistics/time_series.htm); the data and settings above come from the run.
# data: time = times, zidovudine = observations, patient = subjectIds, group = groups
# settings: confidence = ci, zero_at_start = addZeroObservationAtZeroTime

if (isTRUE(zero_at_start) && !any(time == 0)) {   # an observation of 0 at time 0 for each subject, as the run asked
  ids <- unique(patient); first <- match(ids, patient)
  time <- c(time, rep(0, length(ids))); zidovudine <- c(zidovudine, rep(0, length(ids))); if (!is.null(group)) group <- c(group, group[first]); patient <- c(patient, ids)
}
if (is.null(group)) group <- rep("All", length(time))
d <- data.frame(Time = time, Zidovudine = zidovudine, Patient = patient, Group = group)
# Time series summary: the StatsDirect help example (Bland 2000, blood levels of
# zidovudine after an oral dose in patients with and without malabsorption) in R
# The data are the Group, Time, Zidovudine and Patient columns of the Other
# worksheet of the StatsDirect test workbook.
# 2 decimal places, with halves rounded up as StatsDirect rounds them
pct <- paste0(100 * confidence, "%")
two <- function(x) {
  formatC(sign(x) * floor(abs(x) * 100 + 0.5 + 1e-9) / 100, digits = 2, format = "f",
          drop0trailing = TRUE)
}
iqr <- function(x) diff(quantile(x, c(0.25, 0.75), type = 2))

# R has no standard function for this summary, so it is built here. For each
# group and time: the number of observations, mean, SD, SE, median and IQR
# (quartiles by centile type 1, which is type 2 in R).
aucs <- list()
for (g in unique(d$Group)) {
  cat("Group:", g, "\n")
  s <- d[d$Group == g, ]
  cat("Time  Observations  Mean  SD  SE  Median  IQR\n")
  for (t in sort(unique(s$Time))) {
    y <- s$Zidovudine[s$Time == t]
    cat(t, length(y), two(mean(y)), two(sd(y)), two(sd(y) / sqrt(length(y))),
        two(median(y)), two(iqr(y)), "\n")
  }

  # For each subject: the baseline (the value at time 0), the smallest and
  # largest values, the time of the largest, the slope of a least squares line
  # through the values up to the largest, and the area under the curve by the
  # trapezium rule
  cat("Subject ID  Baseline  Min. observation  Max. observation  Time to max.",
      "Slope to max.  AUC\n")
  auc <- slope <- tmax <- c()
  for (id in sort(unique(s$Patient))) {
    p <- s[s$Patient == id, ]
    p <- p[order(p$Time), ]
    y <- p$Zidovudine
    t <- p$Time
    k <- which.max(y)
    tmax[id] <- t[k]
    slope[id] <- coef(lm(y[1:k] ~ t[1:k]))[2]
    auc[id] <- sum(diff(t) * (y[-1] + y[-length(y)]) / 2)
    cat(id, two(y[1]), two(min(y)), two(max(y)), t[k], two(slope[id]), two(auc[id]),
        "\n")
  }

  # The group's summary of the areas: t and z intervals for the mean, and a
  # bootstrap-t interval. StatsDirect's bootstrap uses its own random numbers, so
  # its limits differ a little from these.
  auc <- auc[!is.na(auc)]
  slope <- slope[!is.na(slope)]
  tmax <- tmax[!is.na(tmax)]
  n <- length(auc)
  se <- sd(auc) / sqrt(n)
  cat("Subjects:", n, "\n")
  cat("Total (mean per time point) observations:", nrow(s),
      paste0("(", nrow(s) / length(unique(s$Time)), ")"), "\n")
  cat("Mean (SD) area under curve (AUC):", two(mean(auc)),
      paste0("(", two(sd(auc)), ")"), "\n")
  cat("SE of mean AUC:", two(se), "\n")
  cat(pct, "t-interval for mean AUC:", two(mean(auc) - qt((1 + confidence) / 2, n - 1) * se), "to",
      two(mean(auc) + qt((1 + confidence) / 2, n - 1) * se), "\n")
  set.seed(2944296)
  tstar <- replicate(10000, {
    b <- auc[sample.int(n, n, replace = TRUE)]
    (mean(b) - mean(auc)) / (sd(b) / sqrt(n))
  })
  # Percentage points keep the 95% endpoints at .025 and .975: tiny subtraction
  # errors at an exact order statistic would otherwise change type 2's averaging.
  bootstrap_prob <- c(50 - 50 * confidence, 50 + 50 * confidence) / 100
  bootstrap_ci <- mean(auc) + quantile(tstar, bootstrap_prob,
      type = 2, na.rm = TRUE) * se
  cat(pct, "bootstrap-t interval for mean AUC (10000 iterations):",
      two(bootstrap_ci[1]), "to", two(bootstrap_ci[2]), "\n")
  cat(pct, "z-interval for mean AUC:", two(mean(auc) - qnorm((1 + confidence) / 2) * se), "to",
      two(mean(auc) + qnorm((1 + confidence) / 2) * se), "\n")
  cat("Median (IQR) area under curve:", two(median(auc)),
      paste0("(", two(iqr(auc)), ")"), "\n")
  cat("Median (IQR) time to maximum:", median(tmax), paste0("(", iqr(tmax), ")"), "\n")
  cat("Median (IQR) slope to maximum:", two(median(slope)),
      paste0("(", two(iqr(slope)), ")"), "\n")
  cat("Mean (SD) slope to maximum:", two(mean(slope)), paste0("(", two(sd(slope)), ")"),
      "\n")

  # The group's chart: each subject's values against time
  plot(s$Time, s$Zidovudine, type = "n", main = g, xlab = "Time", ylab = "Zidovudine")
  for (id in unique(s$Patient)) {
    p <- s[s$Patient == id, ]
    lines(p$Time[order(p$Time)], p$Zidovudine[order(p$Time)], type = "b")
  }
  aucs[[g]] <- auc
}

# The areas of the two groups compared with Welch's t test (R's default), which
# is what StatsDirect reports, followed in the report by its bootstrap version
groups <- sort(names(aucs))
if (length(groups) == 2) {   # two groups: their areas compared, as the report does
r <- t.test(aucs[[groups[1]]], aucs[[groups[2]]], conf.level = confidence)
cat("Group comparison:", groups[1], "vs.", groups[2], "\n")
cat("Welch t (SE of difference):", two(r$statistic), paste0("(", two(r$stderr), ")"),
    "\n")
cat("DF (Satterthwaite):", two(r$parameter), "\n")
cat("Two sided P =", formatC(r$p.value, digits = 4, format = "f"), "\n")
cat("AUC difference (", pct, "CI):", two(diff(rev(r$estimate))),
    paste0("(", two(r$conf.int[1]), " to ", two(r$conf.int[2]), ")"), "\n")
}

# The normal plot of the areas that ends the report (all subjects)
qqnorm(unlist(aucs), main = "Normal Plot for AUC",
       ylab = "Area Under Curve")
qqline(unlist(aucs))

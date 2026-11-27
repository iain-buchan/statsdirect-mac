# Independent base-R fixture calculations for StatsDirect worksheet distribution diagnostics.
# Windows PRs #40–42, through 6460e327a3c34952cf01654af23cefc04567aaba.
# Usage: Rscript --vanilla distribution-oracle.R [output-directory]

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 1L)
own_path <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
fence <- read.csv(file.path(dirname(own_path), "paired-outlier-fence.csv"))
stopifnot(identical(fence$pairs, 8:100), all(is.finite(fence$multiplier)), all(fence$multiplier > 0))

shapiro <- function(x) {
    available <- length(x) >= 3L && length(x) <= 100L && min(x) < max(x)
    if (!available) return(c(W = NA_real_, P = NA_real_))
    result <- stats::shapiro.test(x)
    c(W = unname(result$statistic), P = result$p.value)
}

quartiles <- function(x) {
    unname(stats::quantile(x, c(0.25, 0.75), type = 6))
}

finite_values <- function(x) {
    if (!is.numeric(x) || any(is.infinite(x))) stop("Non-finite measurement")
    x
}

paired_summary <- function(before, after) {
    stopifnot(length(before) == length(after))
    before <- finite_values(before)
    after <- finite_values(after)
    rows <- complete.cases(before, after)
    x <- before[rows] - after[rows]
    if (any(!is.finite(x))) stop("Paired difference overflows the numeric range")
    n <- length(x)
    varying <- n > 1L && min(x) < max(x)
    normality <- shapiro(x)
    outlier <- skewed <- heavy <- FALSE
    q <- rep(NA_real_, 2L)
    far <- NA_integer_
    skew <- excess <- NA_real_
    if (varying && n >= 4L) {
        # Scale before centering to keep large and very small finite values in range.
        span <- max(x) - min(x)
        scaled <- if (is.finite(span)) (x - min(x)) / span else x / max(abs(x))
        centered <- scaled - mean(scaled)
        variance <- mean(centered^2)
        skew <- mean(centered^3) / variance^1.5
        skewed <- abs(skew) >= 1
        # Use the raw scale when safe to preserve strict, exactly-on-the-fence comparisons.
        fence_data <- if (is.finite(span) && span > .Machine$double.xmin) x else scaled
        fq <- quartiles(fence_data)
        iqr <- fq[2L] - fq[1L]
        if (n > 100L) {
            q <- quartiles(x)
            far <- sum((fq[1L] - fence_data) / 3 > iqr | (fence_data - fq[2L]) / 3 > iqr)
            excess <- mean(centered^4) / variance^2 - 3
            outlier <- (1000 * far >= n)
            heavy <- excess >= 2
        } else if (n >= 8L) {
            multiplier <- fence$multiplier[match(n, fence$pairs)]
            outlier <- (fq[1L] - min(fence_data)) / multiplier > iqr ||
                (max(fence_data) - fq[2L]) / multiplier > iqr
        }
    }
    suggestion <- if (n < 3L || !varying || outlier || skewed || heavy) {
        NA_character_
    } else if (n > 100L) {
        "large"
    } else if (is.na(normality["P"])) {
        NA_character_
    } else if (normality[["P"]] < 0.05) {
        "non-normal"
    } else {
        "normal"
    }
    data.frame(n = n, W = normality[["W"]], P = normality[["P"]], varying = varying,
               Q1 = q[1L], Q3 = q[2L], farOut = far, skewness = skew, excessKurtosis = excess,
               fenceWarning = outlier, skewWarning = skewed, heavyTailWarning = heavy,
               suggestedBranch = suggestion, allowed = if (n > 100L) "large,non-normal" else "normal,non-normal")
}

independent_summary <- function(left, right) {
    group <- function(values) {
        values <- finite_values(values)
        values <- values[!is.na(values)]
        c(n = length(values), shapiro(values))
    }
    a <- group(left)
    b <- group(right)
    large <- min(a[["n"]], b[["n"]]) > 100L
    data.frame(n1 = a[["n"]], W1 = a[["W"]], P1 = a[["P"]],
               n2 = b[["n"]], W2 = b[["W"]], P2 = b[["P"]], large = large,
               allowedWhenSeparate = if (large) "large,non-normal" else "normal,non-normal")
}

normal_grid <- function(n) stats::qnorm(stats::ppoints(n))
from_differences <- function(d) list(before = d, after = rep(0, length(d)))
symmetric_gap <- function(gap) {
    positive <- gap + (1:10) / 10
    c(-positive, positive)
}
small_fence <- function(n, inside) {
    centre <- normal_grid(n - 1L)
    q <- quartiles(c(centre, 100))
    multiplier <- fence$multiplier[match(n, fence$pairs)]
    boundary <- q[2L] + multiplier * diff(q)
    c(centre, boundary + if (inside) -0.001 else 0.001)
}
paired <- c(
    list(
        pefr = list(before = c(312, 242, 340, 388, 296, 254, 391, 402, 290),
                    after = c(300, 201, 232, 312, 220, 256, 328, 330, 231)),
        alternating_missing = list(before = c(11, 13, 999, 12, NA, 12, 14),
                                   after = c(10, 10, NA, 10, 10, 10, 10))
    ),
    lapply(list(
        n0 = NA_real_, n1 = 1, n2 = c(1, 2), n3 = c(-1, 0, 1),
        constant_100 = rep(2, 100), constant_101 = rep(2, 101),
        n7_no_fence = c(-20, -2, -1, 0, 1, 2, 20),
        n8_fence_inside = small_fence(8L, TRUE), n8_fence_outside = small_fence(8L, FALSE),
        n100_fence_inside = small_fence(100L, TRUE), n100_fence_outside = small_fence(100L, FALSE),
        small_bimodal = c(-109:-100, 100:109),
        p_just_under = symmetric_gap(0.2189012), p_just_over = symmetric_gap(0.2144970),
        normal_100 = normal_grid(100L), normal_101 = normal_grid(101L),
        late_outlier_102 = c(normal_grid(101L), 30),
        large_heavy_symmetric = c(normal_grid(101L), -4.5, 4.5),
        large_skewed = c(rep(0, 40), rep(1, 65), rep(3.5, 10)),
        outlier_rate_1000 = c(normal_grid(999L), 5),
        outlier_rate_1001 = c(normal_grid(1000L), 5),
        on_outer_fences = c(rep(-1, 30), rep(0, 39), rep(1, 30), -7, 7),
        beyond_outer_fence = c(rep(-1, 30), rep(0, 39), rep(1, 30), -7, 7 + 2^-45),
        wide_finite_101 = normal_grid(101L) * 5e307
    ), from_differences)
)
independent <- list(
    uneven_missing = list(left = c(1, NA, 2, 4, 6, 8), right = c(NA, 0, 1, 2, NA, NA)),
    n101_n4 = list(left = normal_grid(101L), right = c(2, 4, 5, 9, rep(NA_real_, 97L))),
    n101_n100 = list(left = normal_grid(101L), right = c(normal_grid(100L), NA)),
    n101_n101 = list(left = normal_grid(101L), right = normal_grid(101L) + 1),
    constant_and_empty = list(left = rep(7, 4), right = rep(NA_real_, 4))
)

paired_results <- do.call(rbind, lapply(paired, function(x) do.call(paired_summary, x)))
independent_results <- do.call(rbind, lapply(independent, function(x) do.call(independent_summary, x)))
near <- function(x, y) abs(x - y) < 2e-9
row <- function(name) paired_results[name, ]
stopifnot(
    row("pefr")$n == 9L, near(row("pefr")$W, 0.9393051840), near(row("pefr")$P, 0.5746038208),
    row("alternating_missing")$n == 5L, near(row("alternating_missing")$P, 0.8139521274),
    is.na(row("n2")$W), !is.na(row("n3")$W), !row("constant_101")$varying,
    !row("n7_no_fence")$fenceWarning, !row("n8_fence_inside")$fenceWarning, row("n8_fence_outside")$fenceWarning,
    !row("n100_fence_inside")$fenceWarning, row("n100_fence_outside")$fenceWarning,
    row("small_bimodal")$suggestedBranch == "non-normal", row("normal_100")$suggestedBranch == "normal",
    row("p_just_under")$P < 0.05, row("p_just_under")$suggestedBranch == "non-normal",
    row("p_just_over")$P > 0.05, row("p_just_over")$suggestedBranch == "normal",
    is.na(row("normal_101")$W), row("normal_101")$suggestedBranch == "large",
    row("normal_101")$allowed == "large,non-normal", row("late_outlier_102")$farOut == 1L,
    row("large_heavy_symmetric")$heavyTailWarning, !row("large_heavy_symmetric")$skewWarning,
    row("large_skewed")$skewWarning, is.na(row("large_skewed")$suggestedBranch),
    row("outlier_rate_1000")$fenceWarning, !row("outlier_rate_1001")$fenceWarning,
    row("on_outer_fences")$farOut == 0L, row("beyond_outer_fence")$farOut == 1L,
    near(row("wide_finite_101")$excessKurtosis, row("normal_101")$excessKurtosis),
    identical(unname(as.integer(independent_results["uneven_missing", c("n1", "n2")])), c(5L, 3L)),
    is.na(independent_results["n101_n4", "W1"]), !is.na(independent_results["n101_n4", "W2"]),
    !independent_results["n101_n100", "large"], independent_results["n101_n101", "large"]
)
overflow <- tryCatch(paired_summary(1e308, -1e308), error = conditionMessage)
stopifnot(identical(overflow, "Paired difference overflows the numeric range"))

if (length(args)) {
    dir.create(args[1L], recursive = TRUE, showWarnings = FALSE)
    write_result <- function(x, path) {
        rows <- data.frame(case = rownames(x), x, row.names = NULL)
        write.table(rows, file.path(args[1L], path), row.names = FALSE, sep = "\t", na = "", quote = FALSE)
    }
    write_input <- function(cases, path) {
        rows <- lapply(names(cases), function(id) {
            x <- cases[[id]]
            data.frame(case = rep(id, length(x[[1L]])), row = seq_along(x[[1L]]),
                       first = x[[1L]], second = x[[2L]])
        })
        write.table(do.call(rbind, rows), file.path(args[1L], path),
                    row.names = FALSE, sep = "\t", na = "", quote = FALSE)
    }
    write_input(paired, "paired-input.tsv")
    write_input(independent, "independent-input.tsv")
    write_result(paired_results, "paired-expected.tsv")
    write_result(independent_results, "independent-expected.tsv")
}
cat(sprintf("PASS: %d paired and %d independent fixtures, plus paired-overflow rejection.\n",
            nrow(paired_results), nrow(independent_results)))

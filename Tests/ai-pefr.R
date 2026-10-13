t.test(before, after, paired = TRUE)
t.test(d, mu = 0)
matplot(cbind(before, after) |> t(), type = "b", lty = 1, pch = 16,
        xaxt = "n", xlab = "", ylab = "PEFR")
axis(1, at = 1:2, labels = c("Before", "After"))
qqnorm(d)
qqline(d)
wilcox.test(before, after, paired = TRUE, exact = FALSE)
nonzero <- d[d != 0]
binom.test(sum(nonzero > 0), length(nonzero), p = 0.5)
log_result <- t.test(log(after) - log(before))
exp(c(ratio = unname(log_result$estimate), lower = log_result$conf.int[1], upper = log_result$conf.int[2]))

# Binomial inference assumes independent Bernoulli trials with a common probability.
# Exact intervals can be conservative; this is an interval for that probability.
probability <- sd_parameter("qpi", 0.5)
result <- binom.test(parameters$r, parameters$n, p = probability, conf.level = confidence)
print(result)
# R's two-sided test uses probability ordering. StatsDirect may also display doubled-tail or mid-P results.

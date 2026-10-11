# StatsDirect recipe: Random numbers from the Poisson distribution, as the help shows R's generator.
# From the help's R code (randomization/generate_random_numbers.htm); the settings above come from the run.
# settings: rows = rows, cols = cols, seed = seed, mean = xm
# hand-edited: one distribution of the help's illustration, with the run's settings

# StatsDirect and R both use the Mersenne Twister generator, but each seeds it in its own way, so
# the same seed gives a different series in each program. Within one program a seed always
# repeats its own series: set.seed() then the r* function.
if (!exists("seed") || is.null(seed)) seed <- sample.int(1e6, 1)   # StatsDirect took its seed from the clock
set.seed(seed)
x <- matrix(rpois(rows * cols, lambda = mean), rows, cols)
print(round(x, 6))
cat("Mean =", round(mean(x), 6), " sd =", round(sd(x), 6), "  (seed", seed, ")
")

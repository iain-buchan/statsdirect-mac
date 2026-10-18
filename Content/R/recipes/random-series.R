# StatsDirect recipe: Random allocation of the numbers in a series, as the help shows it in R.
# From the help's R code (randomization/x_y_series.htm); the data and settings above come from the run.
# settings: x = low, y = high, seed = seed

if (!exists("seed") || is.null(seed)) seed <- sample.int(1e6, 1)   # StatsDirect took its seed from the clock
# Randomizing a series of integers: the StatsDirect help illustration (the numbers
# 1 to 49, as in a lottery, put in a random order with seed 10) in R

# Sampling positions returns the integers x to y in a random order, every order being
# equally likely. StatsDirect and R each have their own Mersenne Twister generator
# and their own way of turning its output into a random order, so the same seed
# gives a different series in R: the two columns of the output are the same, the
# numbers are not. Keep the seed with the series, as either program can then repeat it.
set.seed(seed)
values <- seq.int(x, y)
series <- values[sample.int(length(values))]
cat("Random allocation of numbers in a series\n")
cat("Randomized with seed:", seed, "\n")
print(data.frame(position = seq_along(series), number = series), row.names = FALSE)

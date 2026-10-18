# StatsDirect recipe: Randomized intervention-control pairs, as the help shows them in R.
# From the help's R code (randomization/intervention_control_pairs.htm); the data and settings above come from the run.
# settings: pairs = pairs, seed = seed, balance = balance

if (!exists("seed") || is.null(seed)) seed <- sample.int(1e6, 1)   # StatsDirect took its seed from the clock
# Randomization of intervention-control pairs: the StatsDirect help example (50
# patients, each given both treatments, allocated to the order intervention then
# control or control then intervention, seed 10, balanced allocation) in R
orders <- c("Intervention - Control", "Control - Intervention")

# StatsDirect and R each have their own random number generator, so the same seed
# gives a different sequence in each program: this script repeats its own
# allocation every time it is run, but it does not repeat the table above.
# Balanced allocation gives each order to exactly half of the pairs (so the
# number of pairs must be even) in a random arrangement: sample() without
# replacement returns the 25 copies of each order in a random permutation.
set.seed(seed)
if (!exists("balance") || is.null(balance)) balance <- TRUE
balanced <- isTRUE(balance) && pairs %% 2 == 0
allocation <- if (balanced) sample(rep(orders, pairs / 2)) else
  sample(orders, pairs, replace = TRUE)
cat("Randomized intervention-control pairs\n")
cat("Randomized with seed:", seed,
    if (balanced) "balanced allocation" else "unbalanced allocation", "\n")
print(data.frame(pair = seq_len(pairs), order = allocation), row.names = FALSE)
cat("Pairs allocated Intervention - Control =", sum(allocation == orders[1]), "\n")
cat("Pairs allocated Control - Intervention =", sum(allocation == orders[2]), "\n")

# Every arrangement of 25 of each order is equally likely: there are choose(50, 25)
if (balanced) cat("Equally likely balanced arrangements =",
    formatC(choose(pairs, pairs / 2), format = "f", digits = 0), "\n")

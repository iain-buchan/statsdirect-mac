# tar is time at risk. The interval models a Poisson count with fixed exposure time.
# Clustering or overdispersion can invalidate this uncertainty calculation.
result <- poisson.test(parameters$revents, T = parameters$tar, conf.level = confidence)
print(result)

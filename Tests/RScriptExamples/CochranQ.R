# Independent selected-data reference using base R's test and rank-model residuals.
emit <- function(x) cat(formatC(as.double(x), digits = 8, format = 'f'), '\n')
m <- matrix(c(1,0,0,0,1,0,1,1,1,0,1,0,1,0,0,1,1,1), ncol=3, byrow=TRUE)
ranks <- t(apply(m, 1L, rank))
n <- nrow(m); k <- ncol(m)
sums <- colSums(ranks)
if (all(m %in% c(0,1))) {
  row_totals <- rowSums(m)
  statistic <- k*(k-1)*sum((colSums(m)-sum(m)/k)^2)/sum(row_totals*(k-row_totals))
} else statistic <- unname(friedman.test(m)$statistic)
f <- (n-1)*statistic/(n*(k-1)-statistic)
p <- if(all(m %in% c(0,1))) pchisq(statistic,k-1,lower.tail=FALSE) else pf(f,k-1,(n-1)*(k-1),lower.tail=FALSE)
emit(c(n,k,sum(ranks^2),statistic,f,p))
emit(sums/n)

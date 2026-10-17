# Independent selected-data reference using base R's test and rank-model residuals.
emit <- function(x) cat(formatC(as.double(x), digits = 8, format = 'f'), '\n')
m <- matrix(c(4,3,2,1,4,2,3,1,3,1.5,1.5,4,3,1,2,4,4,2,1,3,2,2,2,4,1,3,2,4,2,4,1,3,3.5,1,2,3.5,4,1,3,2,4,2,3,1,3.5,1,2,3.5), ncol=4, byrow=TRUE)
ranks <- t(apply(m, 1L, rank))
n <- nrow(m); k <- ncol(m)
sums <- colSums(ranks)
if (all(m %in% c(0,1))) {
  row_totals <- rowSums(m)
  statistic <- k*(k-1)*sum((colSums(m)-sum(m)/k)^2)/sum(row_totals*(k-row_totals))
} else statistic <- unname(friedman.test(m)$statistic)
f <- (n-1)*statistic/(n*(k-1)-statistic)
p <- if(all(m %in% c(0,1))) pchisq(statistic,k-1,lower.tail=FALSE) else pf(f,k-1,(n-1)*(k-1),lower.tail=FALSE)
rank_model <- lm(as.vector(ranks) ~ factor(rep(seq_len(k),each=n)) + factor(rep(seq_len(n),k)))
se <- sqrt(2*n)*summary(rank_model)$sigma
critical <- qt(.975,df.residual(rank_model))
pairs <- combn(k,2L)
differences <- sums[pairs[1L,]]-sums[pairs[2L,]]
probabilities <- 2*pt(-abs(differences)/se,df.residual(rank_model))
emit(c(critical,critical*se))
emit(c(differences,probabilities,as.integer(abs(differences)>critical*se)))

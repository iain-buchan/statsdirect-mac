# Independent checks of the host's table orientation, grouping and numeric inputs.
values <- list()
add <- function(operation, key, value) {
  values[[length(values)+1L]] <<- data.frame(operation=operation, key=key, value=value)
}
t <- (12-10)/(3/sqrt(10))
add('TSingleSummary','t',t)
add('TSingleSummary','p_2',2*pt(-abs(t),9))
add('TSingleSummary','from',2-qt(.975,9)*3/sqrt(10))
add('TSingleSummary','to',2+qt(.975,9)*3/sqrt(10))
add('ExactFisher','p_2',fisher.test(matrix(c(1,11,9,3),nrow=2))$p.value)
one <- summary(aov(c(1,2,3,4,3,5,6,8,7,8,9,11) ~ factor(rep(1:3,each=4))))[[1]]
add('OneWay','f',one[1,'F value'])
add('OneWay','p',one[1,'Pr(>F)'])
add('Spearman','rho',cor(1:5,c(3,1,4,5,7),method='spearman'))
add('SimpleLinearRegression','slope',coef(lm(c(3,4,5,7,9,11)~c(1,2,3,4,5,6)))[2])
subject <- factor(rep(1:3,4)); treatment <- factor(rep(rep(1:2,each=3),2))
two <- summary(aov(c(1,2,4,3,4,5,2,3,3,5,6,7) ~ subject*treatment))[[1]]
add('ReplicateTwoWay','sub_vr',two[1,'F value'])
add('ReplicateTwoWay','grp_vr',two[2,'F value'])
add('ReplicateTwoWay','grp_p',two[2,'Pr(>F)'])
x <- c(1:5,2:6); y <- c(2,3,5,7,10,3,6,8,11,12); group <- factor(rep(1:2,each=5))
model <- anova(lm(y~group*x))
add('GroupedCovariance','bet_vr',model[3,'F value'])
add('GroupedCovariance','bet_p',model[3,'Pr(>F)'])
write.table(do.call(rbind,values),row.names=FALSE,sep='\t',quote=FALSE)

# Independent selected transformation reference using R's lm, anova and cor.
emit <- function(x) cat(formatC(as.double(x), digits = 8, format = 'f'), '\n')
y <- c(1182,1172,1264,1493,1571,1711,1804,1840,1956,1954); x <- c(1290,1350,1470,1600,1710,1840,1980,2230,2400,2930); model <- 0
tx <- switch(as.character(model),"0"=x,"1"=log(x),"2"=1/x)
ty <- if(model==2L) 1/y else log(y)
fit <- lm(ty~tx)
intercept <- unname(coef(fit)[1L]); slope <- unname(coef(fit)[2L])
emit(c(if(model==2L)slope else exp(intercept),if(model==2L)intercept else slope,cor(tx,ty),summary(fit)$sigma))

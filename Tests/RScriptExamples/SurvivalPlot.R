# Independent R survival::survfit reference supplies the selected S and log-log limits.
emit <- function(x) cat(formatC(as.double(x),digits=8,format="f"),"\n")
times <- list(c(142,157,163,198,204,205,232,232,232,233,233,233,233,239,240,261,280,280,295,295,323,344),c(143,165,188,188,190,192,206,208,212,216,216,220,227,230,235,244,246,265,303))
events <- list(c(1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0),c(1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0,1,1,1))
emit(length(times))
for(i in seq_along(times)) {
 fit <- survival::survfit(survival::Surv(times[[i]],events[[i]])~1,conf.type="log-log")
 k <- match(times[[i]],fit$time)
 emit(c(length(k),times[[i]],fit$surv[k],fit$lower[k],fit$upper[k],events[[i]]))
}

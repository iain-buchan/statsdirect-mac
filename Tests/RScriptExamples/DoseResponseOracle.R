# Test oracle from the binomial likelihood and expected Fisher information.
# This file never sources a production recipe or a StatsDirect numerical routine.
verify_dose_response_oracle <- function() {
  x <- age; n <- girls; r <- menses
  F <- if (model == "probit") pnorm else function(eta) plogis(2 * eta)
  density <- if (model == "probit") dnorm else function(eta) { p <- plogis(2 * eta); 2 * p * (1 - p) }
  if (nc > 0 && nrc > 0) {
    initial <- suppressWarnings(glm(cbind(r, n-r) ~ x, family = binomial(link = model)))
    ab <- coef(initial) / if (model == "logit") 2 else 1
    objective <- function(z) {
      c <- plogis(z[3]); q <- c + (1-c) * F(z[1] + z[2]*x)
      -sum(dbinom(r, n, q, log = TRUE)) - dbinom(nrc, nc, c, log = TRUE)
    }
    gradient <- function(z) {
      c <- plogis(z[3]); eta <- z[1] + z[2]*x; latent <- F(eta)
      q <- c + (1-c)*latent; residual <- (r-n*q)/(q*(1-q))
      da <- residual*(1-c)*density(eta)
      -c(sum(da), sum(da*x), c*(1-c)*sum(residual*(1-latent)) + nrc-nc*c)
    }
    attempts <- lapply(pmin(.98, pmax(1e-6, c(.5, 1, 1.5)*nrc/nc)), function(c)
      nlminb(c(ab, qlogis(c)), objective, gradient,
             control = list(rel.tol = 1e-14, x.tol = 1e-12, iter.max = 10000, eval.max = 10000)))
    best <- attempts[[which.min(vapply(attempts, function(z) z$objective, 0.0))]]
    oa <- unname(best$par[1]); ob <- unname(best$par[2]); oc <- plogis(best$par[3])
    q <- oc + (1-oc)*F(oa + ob*x)
    G <- cbind((1-oc)*density(oa+ob*x), (1-oc)*density(oa+ob*x)*x, 1-F(oa+ob*x))
    info <- crossprod(G, G*(n/(q*(1-q))))
    info[3,3] <- info[3,3] + nc/(oc*(1-oc))
    covariance <- solve(info)
    stopifnot(max(abs(gradient(best$par))) < 2e-4)
  } else {
    fit0 <- glm(cbind(r, n-r) ~ x, family = binomial(link = model))
    fit0 <- update(fit0, start = coef(fit0))
    scale <- if (model == "logit") 2 else 1
    oa <- unname(coef(fit0)[1])/scale; ob <- unname(coef(fit0)[2])/scale; oc <- 0
    q <- F(oa+ob*x); G <- cbind(density(oa+ob*x), density(oa+ob*x)*x)
    covariance <- matrix(0, 3, 3)
    covariance[1:2,1:2] <- solve(crossprod(G, G*(n/(q*(1-q)))))
  }
  ochi <- sum((r-n*q)^2/(n*q*(1-q))) +
    if (oc > 0) (nrc-nc*oc)^2/(nc*oc*(1-oc)) else 0
  close <- function(actual, expected, tolerance = 3e-6)
    stopifnot(all(abs(actual-expected) <= tolerance*pmax(1, abs(expected))))
  close(c(a,b,natural_response,chi), c(oa,ob,oc,ochi))
  stopifnot(all(abs(unname(covariance_full)-unname(covariance)) <=
    2e-5*pmax(1e-8, abs(covariance)) + 1e-10))
  stopifnot(df == length(x)-2L, heterogeneity == (pchisq(ochi, df, lower.tail=FALSE) < .05))
  selected <- covariance[1:2,1:2] * if (heterogeneity) ochi/df else 1
  critical0 <- if (heterogeneity) qt((1+confidence)/2, df) else qnorm((1+confidence)/2)
  close(se_slope^2, selected[2,2])
  for (p in c(.5, centile/100)) {
    target <- if (model == "probit") qnorm(p) else qlogis(p)/2
    A <- ob^2-critical0^2*selected[2,2]
    B <- 2*ob*(oa-target)-2*critical0^2*selected[1,2]
    C <- (oa-target)^2-critical0^2*selected[1,1]
    discriminant <- B^2-4*A*C
    actual <- interval_for(p)
    close(actual$g, critical0^2*selected[2,2]/ob^2)
    if (A > 0 && discriminant >= 0) {
      expected <- sort(c(-B-sqrt(discriminant), -B+sqrt(discriminant))/(2*A))
      stopifnot(actual$status == "bounded")
      close(actual$limits, expected, 2e-5)
      # Both endpoints must satisfy the independent quadratic inversion equation.
      residual <- (a+b*actual$limits-target)^2 - critical0^2 *
        (selected_covariance[1,1] + 2*actual$limits*selected_covariance[1,2] + actual$limits^2*selected_covariance[2,2])
      stopifnot(max(abs(residual)) < 1e-8)
    } else stopifnot(actual$status %in% c("unbounded", "disjoint", "empty"), any(!is.finite(actual$limits)))
  }
  cat("INDEPENDENT DOSE RESPONSE ORACLE VERIFIED\n")
}

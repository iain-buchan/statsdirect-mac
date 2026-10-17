# Independent test oracle: maximise the binomial likelihood, invert the expected
# Fisher matrix, then solve the Fieller polynomial. This deliberately does not
# reuse the production Finney working-response iteration or interval formula.
dose_reference <- function(x, n, r, model, nc = 0, nrc = 0) {
  # Use robust centering/scaling so a distant low-dose group does not obscure
  # the seven tightly spaced treatment groups in the optimiser. Transform the
  # estimates and full covariance back to the caller's dose scale afterwards.
  centre <- median(x); spread <- IQR(x)
  if (spread <= 0) spread <- sd(x)
  stopifnot(is.finite(spread), spread > 0)
  x <- (x-centre)/spread
  link <- make.link(model)
  initial <- glm(cbind(r, n-r) ~ x, family = binomial(link = model),
                 control = glm.control(epsilon = 1e-12, maxit = 200L))
  if (nc > 0 && nrc > 0) {
    likelihood <- function(theta) {
      background <- plogis(theta[3L])
      eta <- theta[1L] + theta[2L] * x
      f <- link$linkinv(eta); d <- link$mu.eta(eta)
      p <- background + (1-background) * f
      score <- (r-n*p)/(p*(1-p))
      list(value = -sum(dbinom(r, n, p, log = TRUE)) -
             dbinom(nrc, nc, background, log = TRUE),
           gradient = -c(sum(score*(1-background)*d),
             sum(score*(1-background)*d*x),
             (sum(score*(1-f)) + (nrc-nc*background)/
                (background*(1-background))) * background*(1-background)))
    }
    fits <- lapply(c(.03, nrc/nc, .2), function(background)
      optim(c(coef(initial), qlogis(background)),
            function(theta) likelihood(theta)$value,
            function(theta) likelihood(theta)$gradient,
            method = "BFGS", control = list(reltol = 1e-13, maxit = 10000L)))
    optimum <- fits[[which.min(vapply(fits, function(f) f$value, 0.0))]]
    stopifnot(optimum$convergence == 0L,
              max(abs(likelihood(optimum$par)$gradient)) < 1e-4)
    beta <- unname(optimum$par[1:2]); background <- plogis(optimum$par[3L])
  } else {
    beta <- unname(coef(initial)); background <- 0
  }
  eta <- beta[1L] + beta[2L] * x
  f <- link$linkinv(eta); d <- link$mu.eta(eta)
  p <- background + (1-background)*f
  jacobian <- cbind((1-background)*d, (1-background)*d*x)
  if (background > 0) jacobian <- cbind(jacobian, 1-f)
  information <- crossprod(jacobian, jacobian*(n/(p*(1-p))))
  control_chi <- 0
  if (background > 0) {
    information[3L,3L] <- information[3L,3L] + nc/(background*(1-background))
    control_chi <- (nrc-nc*background)^2/(nc*background*(1-background))
  }
  covariance <- solve(information)
  transform <- diag(ncol(covariance))
  transform[1L,2L] <- -centre/spread
  transform[2L,2L] <- 1/spread
  beta <- drop(transform[1:2,1:2] %*% beta)
  covariance <- transform %*% covariance %*% t(transform)
  chi <- sum((r-n*p)^2/(n*p*(1-p))) + control_chi
  df <- length(x)-2L
  heterogeneous <- pchisq(chi, df, lower.tail = FALSE) < .05
  phi <- if (heterogeneous) chi/df else 1
  list(beta = beta, background = background, covariance = covariance,
       probability = p, excess = f, chi = chi, df = df, phi = phi,
       heterogeneous = heterogeneous, model = model)
}

dose_reference_interval <- function(reference, probability, confidence) {
  covariance <- reference$covariance[1:2,1:2] * reference$phi
  critical <- if (reference$heterogeneous)
    qt((1+confidence)/2, reference$df) else qnorm((1+confidence)/2)
  a <- reference$beta[1L] - make.link(reference$model)$linkfun(probability)
  b <- reference$beta[2L]
  # Solve in displacement from the estimated dose. The two raw roots can be
  # very close to one another but far from zero; centering avoids unnecessary
  # cancellation/imaginary roundoff in R's general polynomial root finder.
  centre <- -a/b
  transform <- rbind(c(1,centre),c(0,1))
  covariance <- transform %*% covariance %*% t(transform)
  polynomial <- c(-critical^2*covariance[1L,1L],
                  -2*critical^2*covariance[1L,2L],
                  b*b-critical^2*covariance[2L,2L])
  stopifnot(polynomial[3L] > 0)
  roots <- polyroot(polynomial)
  stopifnot(max(abs(Im(roots))) < 1e-10)
  centre + sort(Re(roots))
}

# Independent binomial likelihood, Fisher information and Fieller inversion.
# hand-edited: shared by the self-contained probit and logit replay scripts.
sd_dose_response_link <- function(model) {
  if (model == "probit") list(probability = pnorm, density = dnorm, quantile = qnorm, scale = 1) else
    list(probability = function(eta) plogis(2 * eta), density = function(eta) {
      p <- plogis(2 * eta); 2 * p * (1 - p)
    }, quantile = function(p) qlogis(p) / 2, scale = 2)
}

sd_dose_response_fit <- function(dose, subjects, responses, model, nc = 0, nrc = 0) {
  link <- sd_dose_response_link(model)
  if (nc <= 0 || nrc <= 0) {
    age <- dose
    fit <- glm(cbind(responses, subjects - responses) ~ age, family = binomial(link = model))
    fit <- glm(cbind(responses, subjects - responses) ~ age, family = binomial(link = model), start = coef(fit))
    if (!isTRUE(fit$converged) || any(!is.finite(coef(fit))) || any(!is.finite(vcov(fit))))
      stop("The selected binomial model did not give a converged, identifiable dose-response fit.")
    a <- unname(coef(fit)[1L]) / link$scale; b <- unname(coef(fit)[2L]) / link$scale
    centre <- mean(dose); scale <- sqrt(mean((dose - centre)^2))
    probability <- link$probability(a + b * dose); density <- link$density(a + b * dose)
    informative <- probability > 0 & probability < 1 & density > 0
    design <- cbind(1, (dose - centre) / scale)
    weights <- subjects[informative] * density[informative]^2 / (probability[informative] * (1 - probability[informative]))
    information <- crossprod(design[informative, , drop = FALSE] * sqrt(weights))
    transformation <- rbind(c(1, -centre / scale), c(0, 1 / scale))
    exact_covariance <- tryCatch(transformation %*% solve(information) %*% t(transformation), error = function(e) NULL)
    if (is.null(exact_covariance) || any(!is.finite(exact_covariance)))
      stop("The final binomial fit has singular Fisher information.")
    covariance <- matrix(0, 3L, 3L, dimnames = list(c("a", "b", "natural"), c("a", "b", "natural")))
    covariance[1:2, 1:2] <- exact_covariance
    return(list(fit = fit, a = a, b = b, natural_response = 0, covariance = covariance))
  }
  if (nrc >= nc) stop("A natural-response model needs at least one responding and one nonresponding control subject.")
  centre <- mean(dose); scale <- sqrt(mean((dose - centre)^2))
  if (!is.finite(scale) || scale <= 0) stop("Select at least two distinct dose levels.")
  x <- (dose - centre) / scale
  observed <- responses / subjects
  design <- cbind(1, x)
  evaluate <- function(parameters, information = FALSE) {
    c <- plogis(parameters[3L]); eta <- drop(design %*% parameters[1:2])
    f <- link$probability(eta); density <- link$density(eta)
    q <- c + (1 - c) * f
    q <- pmin(1 - .Machine$double.eps, pmax(.Machine$double.eps, q))
    c <- min(1 - .Machine$double.eps, max(.Machine$double.eps, c))
    value <- -sum(responses * log(q) + (subjects - responses) * log1p(-q)) -
      nrc * log(c) - (nc - nrc) * log1p(-c)
    gradient_q <- cbind((1 - c) * density, (1 - c) * density * x, (1 - f) * c * (1 - c))
    gradient <- -drop(crossprod(gradient_q, (responses - subjects * q) / (q * (1 - q))))
    gradient[3L] <- gradient[3L] - (nrc - nc * c)
    info <- NULL
    if (information) {
      weighted <- gradient_q * sqrt(subjects / (q * (1 - q)))
      info <- crossprod(weighted)
      info[3L, 3L] <- info[3L, 3L] + nc * c * (1 - c)
    }
    list(value = value, gradient = gradient, information = info, natural = c)
  }
  starts <- unique(pmin(.95, pmax(1e-6, (nrc / nc) * c(.5, 1, 1.5))))
  candidates <- lapply(starts, function(c) {
    adjusted <- pmin(1 - .5 / subjects, pmax(.5 / subjects, (observed - c) / (1 - c)))
    initial_line <- lm.wfit(design, link$quantile(adjusted), subjects)$coefficients
    if (any(!is.finite(initial_line))) initial_line <- c(0, 1)
    initial <- c(initial_line, qlogis(c))
    optim(initial, function(p) evaluate(p)$value, function(p) evaluate(p)$gradient,
          method = "BFGS", control = list(maxit = 1000L, reltol = 1e-13))
  })
  best <- candidates[[which.min(vapply(candidates, function(result) result$value, 0.0))]]
  parameters <- best$par
  # Fisher scoring polishes the likelihood solution after an objective-based optimizer
  # stops, using a line search so every accepted step preserves the likelihood.
  for (iteration in seq_len(50L)) {
    current <- evaluate(parameters, TRUE)
    step <- tryCatch(solve(current$information, current$gradient), error = function(e) rep(NA_real_, 3L))
    if (any(!is.finite(step))) break
    if (max(abs(step)) < 1e-11) break
    fraction <- 1
    repeat {
      next_parameters <- parameters - fraction * step
      next_value <- evaluate(next_parameters)$value
      if (is.finite(next_value) && next_value <= current$value + 1e-12 * (1 + abs(current$value))) break
      fraction <- fraction / 2
      if (fraction < 2^-25) break
    }
    if (fraction < 2^-25) break
    parameters <- next_parameters
  }
  final <- evaluate(parameters, TRUE)
  inverse_information <- tryCatch(solve(final$information), error = function(e) NULL)
  if (is.null(inverse_information) || any(!is.finite(inverse_information)))
    stop("The selected control-adjusted model has singular Fisher information.")
  final_step <- drop(inverse_information %*% final$gradient)
  scaled_score <- max(abs(final$gradient) / sqrt(diag(final$information)))
  converged <- all(is.finite(final_step)) && is.finite(scaled_score) &&
    max(abs(final_step) / (1 + abs(parameters))) < 1e-7 && scaled_score < 1e-5
  if (!converged) stop("The joint dose-response and natural-response likelihood did not converge; confidence limits have not been calculated.")
  c <- final$natural
  transformation <- rbind(c(1, -centre / scale, 0), c(0, 1 / scale, 0), c(0, 0, c * (1 - c)))
  covariance <- transformation %*% inverse_information %*% t(transformation)
  dimnames(covariance) <- list(c("a", "b", "natural"), c("a", "b", "natural"))
  a <- parameters[1L] - parameters[2L] * centre / scale
  b <- parameters[2L] / scale
  coefficients <- setNames(c(a, b) * link$scale, c("(Intercept)", "age"))
  fit <- structure(list(coefficients = coefficients, family = binomial(link = model),
    natural_response = c, covariance = covariance, native_scale = link$scale,
    fitted.values = c + (1 - c) * link$probability(a + b * dose),
    df.residual = length(dose) - 2L, converged = converged,
    scaled_score = scaled_score, final_step = final_step, objective = final$value), class = "statsdirect_dose_response")
  list(fit = fit, a = unname(a), b = unname(b), natural_response = c, covariance = covariance)
}

predict.statsdirect_dose_response <- function(object, newdata = NULL, type = c("link", "response"), ...) {
  type <- match.arg(type)
  if (is.null(newdata)) {
    if (type == "response") return(object$fitted.values)
    stop("Supply a dose column to obtain the fitted link values.")
  }
  dose <- if ("dose" %in% names(newdata)) newdata$dose else newdata$age
  eta <- object$coefficients[1L] + object$coefficients[2L] * dose
  if (type == "link") eta else object$natural_response +
    (1 - object$natural_response) * object$family$linkinv(eta)
}
vcov.statsdirect_dose_response <- function(object, ...) object$covariance[1:2, 1:2] * object$native_scale^2
summary.statsdirect_dose_response <- function(object, ...) {
  data.frame(estimate = c(object$coefficients / object$native_scale, object$natural_response),
    standard_error = sqrt(diag(object$covariance)), row.names = c("constant", "slope", "natural response"))
}

sd_dose_response_fieller <- function(a, b, covariance, target, critical) {
  if (any(!is.finite(covariance)) || !is.finite(critical))
    return(list(status = "unbounded", intervals = matrix(c(-Inf, Inf), nrow = 1L),
      critical = critical, g = Inf, limits = c(-Inf, Inf)))
  A <- b^2 - critical^2 * covariance[2L, 2L]
  B <- 2 * ((a - target) * b - critical^2 * covariance[1L, 2L])
  C <- (a - target)^2 - critical^2 * covariance[1L, 1L]
  discriminant <- B^2 - 4 * A * C
  tolerance <- 64 * .Machine$double.eps * max(abs(c(B^2, 4 * A * C)), .Machine$double.xmin)
  if (discriminant < 0 && discriminant > -tolerance) discriminant <- 0
  if (A == 0) {
    if (B == 0) intervals <- if (C <= 0) matrix(c(-Inf, Inf), nrow = 1L) else matrix(numeric(), ncol = 2L) else
      intervals <- matrix(if (B > 0) c(-Inf, -C / B) else c(-C / B, Inf), nrow = 1L)
  } else if (discriminant < 0 || (A < 0 && discriminant == 0)) {
    intervals <- if (A < 0) matrix(c(-Inf, Inf), nrow = 1L) else matrix(numeric(), ncol = 2L)
  } else {
    # Stable quadratic roots avoid subtracting nearly equal numbers at a distant centile.
    q <- -.5 * (B + if (B >= 0) sqrt(discriminant) else -sqrt(discriminant))
    roots <- if (q == 0) rep(-B / (2 * A), 2L) else sort(c(q / A, C / q))
    intervals <- if (A > 0) matrix(roots, nrow = 1L) else rbind(c(-Inf, roots[1L]), c(roots[2L], Inf))
  }
  status <- if (!nrow(intervals)) "empty" else if (nrow(intervals) == 2L) "disjoint" else
    if (all(is.finite(intervals))) "bounded" else "unbounded"
  list(status = status, intervals = intervals, critical = critical,
       g = critical^2 * covariance[2L, 2L] / b^2,
       limits = if (!nrow(intervals)) c(NA_real_, NA_real_) else c(min(intervals[, 1L]), max(intervals[, 2L])))
}

sd_dose_response_pearson <- function(responses, subjects, probability) {
  residual <- responses - subjects * probability
  variance <- subjects * probability * (1 - probability)
  value <- rep(Inf, length(residual))
  positive <- is.finite(variance) & variance > 0
  value[positive] <- residual[positive]^2 / variance[positive]
  exact <- is.finite(variance) & variance == 0 & is.finite(residual) & residual == 0
  value[exact] <- 0
  value
}

# ============================================================================
# Fast exact entropy-balancing solver for the selected P5 path
# ============================================================================
# The exact ATT entropy-balancing problem has only the balance variables as
# unknowns.  Solving its moment equations directly avoids the many full-data
# objective evaluations performed by WeightIt's generic BFGS path.
#
# This file is opt-in.  It leaves the certified P4 implementation untouched
# until lmv2_install_p5_newton_solver() is called by a selected-P5 runner.

LMV2_P5_NEWTON_VERSION <- "lmv2_p5_newton_v1"

lmv2_p5_newton_tilt <- function(beta, X, prior) {
  eta <- drop(X %*% beta)
  eta <- eta - max(eta)
  prior * exp(eta)
}

lmv2_p5_newton_moments <- function(beta, X, prior, target) {
  q <- lmv2_p5_newton_tilt(beta, X, prior)
  mass <- sum(q)
  if (!is.finite(mass) || mass <= 0) {
    return(rep(.Machine$double.xmax, ncol(X)))
  }
  drop(crossprod(X, q) / mass) - target
}

lmv2_p5_newton_jacobian <- function(beta, X, prior, target) {
  q <- lmv2_p5_newton_tilt(beta, X, prior)
  mass <- sum(q)
  mu <- drop(crossprod(X, q) / mass)
  crossprod(X, X * as.numeric(q / mass)) - tcrossprod(mu)
}

lmv2_ebal_fit_cohort_newton <- function(
    vars, data, D_col = "D", s_weights,
    estimand = "ATT", moments = 1,
    maxit = LMV2_P4_EBAL$tolerances$maxit) {
  stopifnot(
    nrow(data) == length(s_weights),
    D_col %in% names(data))
  if (!identical(estimand, "ATT") || !identical(moments, 1)) {
    return(lmv2_p5_weightit_fit_cohort(
      vars, data, D_col, s_weights, estimand, moments, maxit))
  }
  if (!requireNamespace("nleqslv", quietly = TRUE)) {
    return(lmv2_p5_weightit_fit_cohort(
      vars, data, D_col, s_weights, estimand, moments, maxit))
  }

  std <- lmv2_ebal_standardize_cohort(vars, data)
  use_vars <- setdiff(vars, std$zero_variance)
  if (!length(use_vars)) {
    return(list(
      fit = simpleError("no non-degenerate balance variables"),
      zero_variance = std$zero_variance,
      formula_vars = use_vars,
      standardized_data = std$data,
      scaler = std$scaler))
  }

  D <- data[[D_col]]
  treated <- which(D == 1L & is.finite(s_weights) & s_weights > 0)
  control <- which(D == 0L & is.finite(s_weights) & s_weights > 0)
  if (!length(treated) || !length(control)) {
    return(list(
      fit = simpleError("empty positive-weight treated or control arm"),
      zero_variance = std$zero_variance,
      formula_vars = use_vars,
      standardized_data = std$data,
      scaler = std$scaler))
  }

  X_all <- as.matrix(std$data[use_vars])
  qr_x <- qr(X_all[control, , drop = FALSE])
  solver_vars <- use_vars[qr_x$pivot[seq_len(qr_x$rank)]]
  X_control <- X_all[control, solver_vars, drop = FALSE]
  X_treated <- X_all[treated, solver_vars, drop = FALSE]
  treated_prior <- s_weights[treated]
  control_prior <- s_weights[control]
  target <- drop(
    crossprod(X_treated, treated_prior) / sum(treated_prior))

  solved <- tryCatch(
    nleqslv::nleqslv(
      x = rep(0, length(solver_vars)),
      fn = lmv2_p5_newton_moments,
      jac = lmv2_p5_newton_jacobian,
      X = X_control,
      prior = control_prior,
      target = target,
      method = "Newton",
      global = "dbldog",
      control = list(
        ftol = LMV2_P4_EBAL$tolerances$exact_tol / 10,
        xtol = 1e-10,
        maxit = min(as.integer(maxit), 1000L))),
    error = function(e) e)

  fit <- if (inherits(solved, "condition") ||
             !solved$termcd %in% c(1L, 2L) ||
             !all(is.finite(solved$x))) {
    if (inherits(solved, "condition")) solved else
      simpleError(sprintf(
        "Newton entropy solver did not converge (termcd=%s)",
        solved$termcd))
  } else {
    raw <- rep(1, nrow(data))
    raw[control] <- lmv2_p5_newton_tilt(
      solved$x, X_control, rep(1, length(control)))
    list(
      weights = raw,
      fit.obj = list(
        solver = "nleqslv_newton",
        coefficients = stats::setNames(solved$x, solver_vars),
        termcd = solved$termcd,
        message = solved$message,
        iterations = solved$iter,
        residual = max(abs(solved$fvec))))
  }

  list(
    fit = fit,
    zero_variance = std$zero_variance,
    formula_vars = use_vars,
    standardized_data = std$data,
    scaler = std$scaler)
}

lmv2_install_p5_newton_solver <- function() {
  if (!exists(
      "lmv2_p5_weightit_fit_cohort",
      envir = .GlobalEnv,
      inherits = FALSE)) {
    assign(
      "lmv2_p5_weightit_fit_cohort",
      lmv2_ebal_fit_cohort,
      envir = .GlobalEnv)
  }
  assign(
    "lmv2_ebal_fit_cohort",
    lmv2_ebal_fit_cohort_newton,
    envir = .GlobalEnv)
  invisible(TRUE)
}

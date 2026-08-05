# Database-free certification for the selected-P5 Newton entropy solver.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
source(file.path(BASE, "R", "18j_lmv2_p5_newton_solver.R"))

set.seed(1805)
vars <- c(LMV2_HYBRID_INV_VARS, LMV2_HYBRID_FIRM_VARS)
n_t <- 700L
n_c <- 2800L
latent <- matrix(stats::rnorm((n_t + n_c) * 4L), ncol = 4L)
X <- cbind(
  latent,
  latent[, 1] * 0.55 + latent[, 2] * 0.20 +
    stats::rnorm(n_t + n_c, sd = 0.7),
  latent[, 3] * -0.30 + stats::rnorm(n_t + n_c, sd = 0.8),
  stats::rnorm(n_t + n_c),
  stats::rnorm(n_t + n_c))
X[seq_len(n_t), ] <- X[seq_len(n_t), ] + 0.08
fixture <- as.data.frame(X)
names(fixture) <- vars
fixture$D <- c(rep(1L, n_t), rep(0L, n_c))

run_pair <- function(prior) {
  t_weightit <- system.time({
    old <- lmv2_p5_weightit_fit_cohort(
      vars, fixture, "D", prior, "ATT", 1, 10000L)
    old_final <- lmv2_ebal_finalize_weights(
      old$fit, fixture$D, prior)
  })[["elapsed"]]
  t_newton <- system.time({
    new <- lmv2_ebal_fit_cohort_newton(
      vars, fixture, "D", prior, "ATT", 1, 10000L)
    new_final <- lmv2_ebal_finalize_weights(
      new$fit, fixture$D, prior)
  })[["elapsed"]]
  stopifnot(old_final$ok, new_final$ok)
  list(
    max_weight_diff = max(
      abs(old_final$weight - new_final$weight)),
    max_balance = lmv2_ebal_balance_maxdiff(
      vars, new$standardized_data, fixture$D, new_final$weight),
    weightit_seconds = unname(t_weightit),
    newton_seconds = unname(t_newton))
}

lmv2_p5_weightit_fit_cohort <- lmv2_ebal_fit_cohort
uniform <- run_pair(rep(1, nrow(fixture)))

equal_deal_prior <- c(
  rep(c(0.4, 0.8, 1.2, 1.6), length.out = n_t),
  rep(c(0.5, 1.0, 1.5), length.out = n_c))
equal_deal <- run_pair(equal_deal_prior)

# A linearly dependent variable must not make the direct root solve singular.
fixture[[vars[[length(vars)]]]] <-
  fixture[[vars[[1]]]] + 2 * fixture[[vars[[2]]]]
collinear <- run_pair(equal_deal_prior)

checks <- data.frame(
  check = c(
    "uniform_weights_match",
    "uniform_exact_balance",
    "equal_deal_weights_match",
    "equal_deal_exact_balance",
    "collinear_weights_match",
    "collinear_exact_balance",
    "newton_faster_uniform",
    "newton_faster_equal_deal"),
  observed = c(
    uniform$max_weight_diff,
    uniform$max_balance,
    equal_deal$max_weight_diff,
    equal_deal$max_balance,
    collinear$max_weight_diff,
    collinear$max_balance,
    uniform$newton_seconds / uniform$weightit_seconds,
    equal_deal$newton_seconds / equal_deal$weightit_seconds),
  threshold = c(
    5e-6, LMV2_P4_EBAL$tolerances$exact_tol,
    5e-6, LMV2_P4_EBAL$tolerances$exact_tol,
    5e-6, LMV2_P4_EBAL$tolerances$exact_tol,
    1, 1),
  stringsAsFactors = FALSE)
checks$pass <- checks$observed <= checks$threshold
print(checks, row.names = FALSE)
if (!all(checks$pass)) {
  stop("Selected-P5 Newton certification failed")
}
message("Selected-P5 Newton certification passed: ",
        sum(checks$pass), "/", nrow(checks))

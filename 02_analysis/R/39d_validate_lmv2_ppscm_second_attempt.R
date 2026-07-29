# ============================================================================
# PPSCM v2 rolling validation
# ============================================================================
# Reads only certified event times -5 through -1. No database or post-period
# outcome table is opened by this stage.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c(
    "DBI", "duckdb", "data.table", "Matrix", "quadprog",
    "digest", "MASS")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(
  BASE, "R", "39a_lmv2_ppscm_second_attempt_config.R"))
config <- lmv2_ppscm_v2_config()
freeze_sha256 <- lmv2_ppscm_assert_freeze(config)

args <- commandArgs(trailingOnly = TRUE)
mode_arg <- grep("^--mode=", args, value = TRUE)
mode <- if (length(mode_arg)) sub("^--mode=", "", mode_arg[[1]]) else
  "production"
if (!mode %in% c("deterministic", "profile", "production")) {
  stop("--mode must be deterministic, profile, or production")
}
bootstrap_reps <- switch(
  mode, deterministic = 0L, profile = 3L,
  production = config$bootstrap_replications)
out_dir <- if (mode == "production") config$validation_dir else
  file.path(config$validation_dir, paste0("_", mode))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

source_path <- file.path(
  BASE, "R", "39d_validate_lmv2_ppscm_second_attempt.R")
source_sha256 <- lmv2_ppscm_sha256(source_path)
config_sha256 <- lmv2_ppscm_sha256(file.path(
  BASE, "R", "39a_lmv2_ppscm_second_attempt_config.R"))
census_manifest_path <- file.path(
  config$census_dir, "census_manifest.csv")
census_manifest <- utils::read.csv(
  census_manifest_path, stringsAsFactors = FALSE)
if (nrow(census_manifest) != 1L ||
    !isTRUE(as.logical(census_manifest$census_pass)) ||
    !identical(census_manifest$status, "CERTIFIED_TO_VALIDATE") ||
    as.integer(census_manifest$maximum_outcome_event_time) != -1L ||
    isTRUE(as.logical(census_manifest$post_outcomes_queried)) ||
    isTRUE(as.logical(census_manifest$optimized_weights_estimated)) ||
    !identical(
      tolower(census_manifest$freeze_sha256), tolower(freeze_sha256)) ||
    !identical(
      tolower(census_manifest$config_sha256), tolower(config_sha256))) {
  stop("39d requires a current certified census manifest")
}
census_manifest_sha256 <- lmv2_ppscm_sha256(census_manifest_path)

path_prepanel <- file.path(config$census_dir, "ppscm_prepanel.parquet")
path_all_prepanel <- file.path(
  config$census_dir, "ppscm_prepanel_all_top20.parquet")
path_edges <- file.path(
  config$census_dir, "eligible_candidate_edges.parquet")
path_treated <- file.path(
  config$census_dir, "treated_preperiod_paths.parquet")
path_donor <- file.path(
  config$census_dir, "donor_preperiod_paths.parquet")
required_files <- c(
  path_prepanel, path_all_prepanel, path_edges, path_treated, path_donor)
if (any(!file.exists(required_files))) {
  stop("Missing certified Stage C validation input")
}
if (!identical(
    tolower(census_manifest$prepanel_sha256),
    tolower(lmv2_ppscm_sha256(path_prepanel))) ||
    !identical(
      tolower(census_manifest$eligible_edges_sha256),
      tolower(lmv2_ppscm_sha256(path_edges))) ||
    !identical(
      tolower(census_manifest$treated_paths_sha256),
      tolower(lmv2_ppscm_sha256(path_treated))) ||
    !identical(
      tolower(census_manifest$donor_paths_sha256),
      tolower(lmv2_ppscm_sha256(path_donor)))) {
  stop("Stage C validation input hash mismatch")
}

read_parquet_dt <- function(path) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  quoted <- as.character(DBI::dbQuoteString(
    con, normalizePath(path, winslash = "/", mustWork = TRUE)))
  data.table::as.data.table(DBI::dbGetQuery(
    con, paste0("SELECT * FROM read_parquet(", quoted, ")")))
}

weighted_cluster_se <- function(x, a) {
  a <- a / sum(a)
  mu <- sum(a * x)
  denom <- max(1 - sum(a^2), 1e-12)
  sqrt(sum(a^2 * (x - mu)^2) / denom)
}

safe_inverse <- function(x) {
  tryCatch(solve(x), error = function(e) MASS::ginv(x))
}

build_design <- function(panel, times, deal_weights) {
  deals <- sort(unique(panel$deal_id))
  deal_weights <- deal_weights[as.character(deals)]
  deal_weights <- deal_weights / sum(deal_weights)
  donors <- lapply(deals, function(d) {
    sort(unique(panel[deal_id == d]$donor_group))
  })
  block_sizes <- lengths(donors)
  starts <- cumsum(c(1L, head(block_sizes, -1L)))
  total_w <- sum(block_sizes)
  total_sep <- length(deals) * length(times)
  x_i <- integer()
  x_j <- integer()
  x_v <- numeric()
  xp_i <- integer()
  xp_j <- integer()
  xp_v <- numeric()
  y_sep <- numeric(total_sep)
  y_pool <- numeric(length(times))
  row_weight <- numeric(total_sep)
  weight_deal_weight <- numeric(total_w)
  keys <- vector("list", length(deals))
  for (j in seq_along(deals)) {
    d <- deals[[j]]
    z <- panel[deal_id == d]
    dg <- donors[[j]]
    cols <- starts[[j]]:(starts[[j]] + block_sizes[[j]] - 1L)
    rows <- ((j - 1L) * length(times) + 1L):(j * length(times))
    ty <- z[match(times, event_time), log1p(treated_outcome)]
    dx <- vapply(dg, function(g) {
      z[donor_group == g][match(times, event_time), log1p(donor_outcome)]
    }, numeric(length(times)))
    if (is.null(dim(dx))) dx <- matrix(dx, ncol = 1L)
    x_i <- c(x_i, rep(rows, times = length(cols)))
    x_j <- c(x_j, rep(cols, each = length(rows)))
    x_v <- c(x_v, as.numeric(dx))
    xp_i <- c(xp_i, rep(seq_along(times), times = length(cols)))
    xp_j <- c(xp_j, rep(cols, each = length(times)))
    xp_v <- c(xp_v, as.numeric(dx) * deal_weights[[j]])
    y_sep[rows] <- ty
    y_pool <- y_pool + deal_weights[[j]] * ty
    row_weight[rows] <- deal_weights[[j]] / length(times)
    weight_deal_weight[cols] <- deal_weights[[j]]
    keys[[j]] <- data.table::data.table(
      deal_id = d, donor_group = dg, column = cols)
  }
  x_sep <- Matrix::sparseMatrix(
    i = x_i, j = x_j, x = x_v,
    dims = c(total_sep, total_w))
  x_pool <- Matrix::sparseMatrix(
    i = xp_i, j = xp_j, x = xp_v,
    dims = c(length(times), total_w))
  block_matrix <- Matrix::sparseMatrix(
    i = rep(seq_along(block_sizes), block_sizes),
    j = seq_len(total_w), x = 1,
    dims = c(length(block_sizes), total_w))
  list(
    deals = deals, deal_weights = deal_weights,
    donors = donors, block_sizes = block_sizes, starts = starts,
    keys = data.table::rbindlist(keys),
    x_sep = x_sep, x_pool = x_pool, block_matrix = block_matrix,
    y_sep = y_sep, y_pool = y_pool,
    row_weight = row_weight,
    weight_deal_weight = weight_deal_weight,
    times = times)
}

solve_separate_qp <- function(dm, lambda) {
  w <- numeric(ncol(dm$x_sep))
  for (j in seq_along(dm$deals)) {
    rows <- ((j - 1L) * length(dm$times) + 1L):(
      j * length(dm$times))
    cols <- dm$starts[[j]]:(
      dm$starts[[j]] + dm$block_sizes[[j]] - 1L)
    x <- as.matrix(dm$x_sep[rows, cols, drop = FALSE])
    y <- dm$y_sep[rows]
    h <- crossprod(x) / length(rows) +
      lambda * diag(length(cols))
    b <- as.numeric(crossprod(x, y)) / length(rows)
    solution <- quadprog::solve.QP(
      Dmat = 2 * h, dvec = 2 * b,
      Amat = cbind(rep(1, length(cols)), diag(length(cols))),
      bvec = c(1, rep(0, length(cols))), meq = 1L)
    w[cols] <- pmax(solution$solution, 0)
    w[cols] <- w[cols] / sum(w[cols])
  }
  w
}

solve_weight_qp <- function(dm, lambda, nu, sep_denom, pool_denom,
                            start_w = NULL) {
  nw <- ncol(dm$x_sep)
  ns <- nrow(dm$x_sep)
  np <- nrow(dm$x_pool)
  qp_dims <- c(nw, nrow(dm$x_sep), np, nrow(dm$block_matrix))
  if (length(qp_dims) != 4L || any(!is.finite(qp_dims)) ||
      any(qp_dims < 1)) {
    stop("Invalid QP dimensions: ", paste(qp_dims, collapse = ","))
  }
  sep_factor <- if (nu < 1 && sep_denom > 1e-14) {
    (1 - nu) / sep_denom
  } else 0
  pool_factor <- if (nu > 0 && pool_denom > 1e-14) {
    nu / pool_denom
  } else 0
  w <- if (is.null(start_w)) {
    unlist(lapply(dm$block_sizes, function(k) rep(1 / k, k)))
  } else start_w
  residuals <- matrix(0, nrow = length(dm$deals), ncol = np)
  x_blocks <- vector("list", length(dm$deals))
  y_blocks <- vector("list", length(dm$deals))
  for (j in seq_along(dm$deals)) {
    rows <- ((j - 1L) * np + 1L):(j * np)
    cols <- dm$starts[[j]]:(
      dm$starts[[j]] + dm$block_sizes[[j]] - 1L)
    x_blocks[[j]] <- as.matrix(dm$x_sep[rows, cols, drop = FALSE])
    y_blocks[[j]] <- dm$y_sep[rows]
    residuals[j, ] <- y_blocks[[j]] - x_blocks[[j]] %*% w[cols]
  }
  pooled_residual <- colSums(residuals * dm$deal_weights)
  converged <- FALSE
  maximum_change <- Inf
  previous_objective <- Inf
  relative_objective_change <- Inf
  maximum_iterations <- if (mode == "production") 2000L else 100L
  for (iteration in seq_len(maximum_iterations)) {
    maximum_change <- 0
    for (j in seq_along(dm$deals)) {
      cols <- dm$starts[[j]]:(
        dm$starts[[j]] + dm$block_sizes[[j]] - 1L)
      x <- x_blocks[[j]]
      y <- y_blocks[[j]]
      a <- dm$deal_weights[[j]]
      residual_without_j <- pooled_residual - a * residuals[j, ]
      h <- (
        sep_factor / np + pool_factor * a / np) *
        crossprod(x) + lambda * diag(length(cols))
      b <- sep_factor / np * as.numeric(crossprod(x, y)) +
        pool_factor / np * as.numeric(crossprod(
          x, residual_without_j + a * y))
      scale <- max(abs(h))
      if (is.finite(scale) && scale > 0) {
        h <- h / scale
        b <- b / scale
      }
      h <- h + diag(1e-10, nrow(h))
      solution <- quadprog::solve.QP(
        Dmat = 2 * h, dvec = 2 * b,
        Amat = cbind(rep(1, length(cols)), diag(length(cols))),
        bvec = c(1, rep(0, length(cols))), meq = 1L)$solution
      new_w <- pmax(solution, 0)
      new_w <- new_w / sum(new_w)
      new_w <- 0.5 * new_w + 0.5 * w[cols]
      maximum_change <- max(maximum_change, max(abs(new_w - w[cols])))
      w[cols] <- new_w
      residuals[j, ] <- y - x %*% new_w
      pooled_residual <- residual_without_j + a * residuals[j, ]
    }
    objective <- sep_factor * sum(
      dm$deal_weights * rowMeans(residuals^2)) +
      pool_factor * mean(pooled_residual^2) +
      lambda * sum(dm$weight_deal_weight * w^2)
    relative_objective_change <- abs(previous_objective - objective) /
      max(1, abs(previous_objective), abs(objective))
    if (maximum_change <= 5e-4 ||
        (is.finite(relative_objective_change) &&
         relative_objective_change <= 1e-8)) {
      converged <- TRUE
      break
    }
    previous_objective <- objective
  }
  if (!converged) {
    if (mode == "production") {
      stop(
        "Block-coordinate QP did not converge; max change=",
        signif(maximum_change,6),
        "; relative objective change=",
        signif(relative_objective_change,6))
    }
  }
  if (any(w < -1e-10) ||
      max(abs(as.numeric(dm$block_matrix %*% w) - 1)) > 1e-8) {
    stop("Block-coordinate QP simplex certification failed")
  }
  pmax(w, 0)
}

imbalance_metrics <- function(dm, w) {
  sep <- dm$y_sep - as.numeric(dm$x_sep %*% w)
  pool <- dm$y_pool - as.numeric(dm$x_pool %*% w)
  qj <- vapply(seq_along(dm$deals), function(j) {
    rows <- ((j - 1L) * length(dm$times) + 1L):(
      j * length(dm$times))
    sqrt(mean(sep[rows]^2))
  }, numeric(1))
  list(
    sep = sep, pool = pool, qj = qj,
    qsep2 = sum(dm$row_weight * sep^2),
    qpool2 = mean(pool^2))
}

fit_ppscm <- function(panel, times, deal_weights, lambda,
                      nu_override = NULL, joint_start = NULL) {
  dm <- build_design(panel, times, deal_weights)
  separate_w <- solve_separate_qp(dm, lambda)
  separate <- imbalance_metrics(dm, separate_w)
  avg_unit_fit <- sum(dm$deal_weights * separate$qj)
  pooled_fit <- sqrt(separate$qpool2)
  numerical_zero <- 1e-6
  nu <- if (avg_unit_fit <= numerical_zero ||
            pooled_fit <= numerical_zero) 0 else
    min(1, max(0, pooled_fit / avg_unit_fit))
  if (!is.null(nu_override)) nu <- nu_override
  if (separate$qsep2 <= 1e-14 && separate$qpool2 <= 1e-14) {
    w <- separate_w
  } else {
    w <- solve_weight_qp(
      dm, lambda, nu,
      sep_denom = max(separate$qsep2, 1e-14),
      pool_denom = max(separate$qpool2, 1e-14),
      start_w = if (is.null(joint_start)) separate_w else joint_start)
  }
  wt <- data.table::copy(dm$keys)
  wt[, scm_weight := w[column]]
  list(
    weights = wt, nu = nu, lambda = lambda,
    fit = imbalance_metrics(dm, w), separate = separate)
}

evaluate_model <- function(panel, weights, times, deal_weights) {
  z <- merge(
    panel[event_time %in% times], weights,
    by = c("deal_id", "donor_group"), sort = FALSE)
  deal <- z[, .(
    cohort = unique(cohort),
    n_treated = unique(n_treated),
    treated_raw = unique(treated_outcome),
    synthetic_raw = sum(scm_weight * donor_outcome),
    treated_log = unique(log1p(treated_outcome)),
    synthetic_log = sum(scm_weight * log1p(donor_outcome))),
    by = .(deal_id, event_time)]
  deal[, `:=`(
    raw_gap = treated_raw - synthetic_raw,
    log_gap = treated_log - synthetic_log)]
  deal[, aggregation_weight :=
    deal_weights[as.character(deal_id)]]
  pooled <- deal[, .(
    treated_raw = sum(aggregation_weight * treated_raw),
    synthetic_raw = sum(aggregation_weight * synthetic_raw),
    raw_gap = sum(aggregation_weight * raw_gap),
    treated_log = sum(aggregation_weight * treated_log),
    synthetic_log = sum(aggregation_weight * synthetic_log),
    log_gap = sum(aggregation_weight * log_gap)),
    by = event_time]
  list(deal = deal, pooled = pooled)
}

select_lambda <- function(panel, train_times, deal_weights) {
  predictions <- setNames(
    vector("list", length(config$ridge_grid)),
    as.character(config$ridge_grid))
  for (held in train_times) {
    joint_start <- NULL
    for (lambda in config$ridge_grid) {
      if (mode != "production") {
        message(
          "  nested CV | train=",paste(train_times,collapse=","),
          " | inner hold=",held,
          " | lambda=",format(lambda,scientific=TRUE))
      }
      fit <- fit_ppscm(
        panel, setdiff(train_times, held), deal_weights, lambda,
        joint_start = joint_start)
      joint_start <- fit$weights[order(column)]$scm_weight
      ev <- evaluate_model(panel, fit$weights, held, deal_weights)$deal
      ev[, `:=`(
        lambda = lambda, held_time = held,
        squared_raw_error = raw_gap^2)]
      key <- as.character(lambda)
      predictions[[key]] <- c(
        predictions[[key]], list(ev))
    }
  }
  cv_rows <- list()
  deal_losses <- list()
  for (lambda in config$ridge_grid) {
    key <- as.character(lambda)
    dl <- data.table::rbindlist(predictions[[key]])[, .(
      mean_squared_raw_error = mean(squared_raw_error)),
      by = deal_id]
    a <- deal_weights[as.character(dl$deal_id)]
    loss <- sum(a * dl$mean_squared_raw_error)
    se <- weighted_cluster_se(dl$mean_squared_raw_error, a)
    cv_rows[[key]] <- data.frame(
      lambda = lambda, loss = loss, standard_error = se)
    dl[, lambda := lambda]
    deal_losses[[key]] <- dl
  }
  curve <- data.table::rbindlist(cv_rows)
  min_row <- curve[which.min(loss)]
  eligible <- curve[loss <= min_row$loss + min_row$standard_error]
  selected_lambda <- max(eligible$lambda)
  list(
    selected_lambda = selected_lambda,
    curve = curve,
    deal_losses = data.table::rbindlist(deal_losses))
}

rolling_validate <- function(panel, aggregation = "inventor_weighted",
                             nu_override = NULL, fixed_lambdas = NULL) {
  deal_info <- unique(panel[, .(deal_id, cohort, n_treated)])
  a <- if (aggregation == "inventor_weighted") {
    deal_info$n_treated / sum(deal_info$n_treated)
  } else {
    rep(1 / nrow(deal_info), nrow(deal_info))
  }
  names(a) <- as.character(deal_info$deal_id)
  folds <- list(
    `-3` = c(-5L, -4L),
    `-2` = c(-5L, -4L, -3L),
    `-1` = c(-5L, -4L, -3L, -2L))
  all_deal <- list()
  all_pooled <- list()
  all_weights <- list()
  all_curves <- list()
  all_selection <- list()
  for (held_name in names(folds)) {
    held <- as.integer(held_name)
    train_times <- folds[[held_name]]
    if (mode != "production") {
      message(
        "rolling ",aggregation," | hold ",held,
        " | train ",paste(train_times,collapse=","))
    }
    if (is.null(fixed_lambdas)) {
      cv <- select_lambda(panel, train_times, a)
      lambda <- cv$selected_lambda
      curve <- cv$curve
    } else {
      lambda <- fixed_lambdas[[held_name]]
      curve <- data.table::data.table()
    }
    fit <- fit_ppscm(
      panel, train_times, a, lambda, nu_override = nu_override)
    ev <- evaluate_model(panel, fit$weights, held, a)
    ev$deal[, `:=`(
      held_time = held, aggregation = aggregation,
      nu = fit$nu, lambda = lambda)]
    ev$pooled[, `:=`(
      held_time = held, aggregation = aggregation,
      nu = fit$nu, lambda = lambda)]
    wt <- data.table::copy(fit$weights)
    wt[, `:=`(
      held_time = held, aggregation = aggregation,
      nu = fit$nu, lambda = lambda)]
    if (nrow(curve)) {
      curve[, `:=`(
        held_time = held, aggregation = aggregation)]
    }
    all_deal[[held_name]] <- ev$deal
    all_pooled[[held_name]] <- ev$pooled
    all_weights[[held_name]] <- wt
    all_curves[[held_name]] <- curve
    all_selection[[held_name]] <- data.frame(
      held_time = held, aggregation = aggregation,
      training_times = paste(train_times, collapse = ";"),
      selected_lambda = lambda, nu = fit$nu)
  }
  deal <- data.table::rbindlist(all_deal)
  pooled <- data.table::rbindlist(all_pooled)
  list(
    deal = deal, pooled = pooled,
    weights = data.table::rbindlist(all_weights),
    curves = data.table::rbindlist(all_curves, fill = TRUE),
    selection = data.table::rbindlist(all_selection),
    rmse = sqrt(mean(pooled$raw_gap^2)),
    max_abs_gap = max(abs(pooled$raw_gap)),
    deal_weights = a)
}

fixed_weight_validation <- function(panel, type, aggregation) {
  deal_info <- unique(panel[, .(deal_id, n_treated)])
  a <- if (aggregation == "inventor_weighted") {
    deal_info$n_treated / sum(deal_info$n_treated)
  } else rep(1 / nrow(deal_info), nrow(deal_info))
  names(a) <- as.character(deal_info$deal_id)
  if (type == "uniform") {
    wt <- unique(panel[, .(deal_id, donor_group)])
    wt[, scm_weight := 1 / .N, by = deal_id]
  } else {
    wt <- unique(panel[, .(deal_id, donor_group, donor_rank)])
    wt <- wt[donor_rank == min(donor_rank), .(
      donor_group, scm_weight = 1), by = deal_id]
  }
  ev <- evaluate_model(panel, wt, config$validation_times, a)
  list(
    deal = ev$deal, pooled = ev$pooled,
    rmse = sqrt(mean(ev$pooled$raw_gap^2)),
    max_abs_gap = max(abs(ev$pooled$raw_gap)),
    weights = wt, deal_weights = a)
}

reaggregate_rolling <- function(panel, rolling, aggregation) {
  deal_info <- unique(panel[, .(deal_id, n_treated)])
  a <- if (aggregation == "inventor_weighted") {
    deal_info$n_treated / sum(deal_info$n_treated)
  } else rep(1 / nrow(deal_info), nrow(deal_info))
  names(a) <- as.character(deal_info$deal_id)
  deal_rows <- list()
  pooled_rows <- list()
  for (held in config$validation_times) {
    wt <- rolling$weights[held_time == held, .(
      deal_id, donor_group, scm_weight)]
    ev <- evaluate_model(panel, wt, held, a)
    ev$deal[, `:=`(
      held_time = held, aggregation = aggregation)]
    ev$pooled[, `:=`(
      held_time = held, aggregation = aggregation)]
    deal_rows[[as.character(held)]] <- ev$deal
    pooled_rows[[as.character(held)]] <- ev$pooled
  }
  deal <- data.table::rbindlist(deal_rows)
  pooled <- data.table::rbindlist(pooled_rows)
  list(
    deal = deal, pooled = pooled,
    rmse = sqrt(mean(pooled$raw_gap^2)),
    max_abs_gap = max(abs(pooled$raw_gap)),
    deal_weights = a)
}

weighted_gap_covariance <- function(deal, deal_weights) {
  wide <- data.table::dcast(
    deal, deal_id ~ event_time, value.var = "raw_gap")
  ids <- wide$deal_id
  x <- as.matrix(wide[, -1])
  a <- deal_weights[as.character(ids)]
  a <- a / sum(a)
  mu <- colSums(x * a)
  influence <- sweep(x, 2, mu, "-") * a
  g <- nrow(influence)
  v <- g / max(g - 1, 1) * crossprod(influence)
  list(mu = mu, covariance = v, statistic = as.numeric(
    t(mu) %*% safe_inverse(v) %*% mu))
}

select_pool <- function(edges, metric, k) {
  delta_cols <- grep("^delta_", names(edges), value = TRUE)
  keep <- delta_cols
  include_tech <- TRUE
  if (metric == "drop_ipc") include_tech <- FALSE
  if (metric == "drop_career") {
    keep <- setdiff(keep, c(
      "delta_mean_career_age_m4", "delta_median_career_age_m4"))
  }
  if (metric == "drop_outcome_level") {
    keep <- setdiff(keep, c(
      "delta_log1p_mean_patent_m5",
      "delta_log1p_mean_patent_m4"))
  }
  out <- data.table::copy(edges)
  out[, sensitivity_distance := sqrt(
    rowSums(as.matrix(.SD)^2) +
      if (include_tech) distance_component_technology^2 else 0),
    .SDcols = keep]
  data.table::setorder(
    out, cohort, deal_id, sensitivity_distance, donor_group)
  out <- out[, head(.SD, k), by = .(cohort, deal_id)]
  out[, donor_rank := seq_len(.N), by = .(cohort, deal_id)]
  out
}

build_spec_panel <- function(selected, treated_path, donor_path,
                             add_deal69 = FALSE) {
  panel <- merge(
    selected[, .(
      cohort, deal_id, treated_group, donor_group, donor_rank,
      distance = sensitivity_distance, cosine)],
    donor_path, by = c("cohort", "donor_group"), sort = FALSE)
  panel <- merge(
    panel, treated_path,
    by.x = c("cohort", "deal_id", "treated_group", "event_time"),
    by.y = c("cohort", "deal_id", "focal_group", "event_time"),
    sort = FALSE)
  panel[, `:=`(
    treated_log1p = log1p(treated_outcome),
    donor_log1p = log1p(donor_outcome))]
  hull <- panel[event_time %in% config$screening_times, .(
    treated_log1p = unique(treated_log1p),
    donor_min_log1p = min(donor_log1p),
    donor_max_log1p = max(donor_log1p)),
    by = .(cohort, deal_id, event_time)]
  hull[, inside_hull :=
    treated_log1p >= donor_min_log1p - 1e-12 &
    treated_log1p <= donor_max_log1p + 1e-12]
  support <- hull[, .(
    two_period_hull_support =
      .N == length(config$screening_times) && all(inside_hull)),
    by = .(cohort, deal_id)]
  keep <- support[two_period_hull_support == TRUE, .(cohort, deal_id)]
  if (add_deal69) {
    keep <- unique(rbind(
      keep, data.table::data.table(cohort = 2000L, deal_id = 69)))
  }
  panel <- merge(panel, keep, by = c("cohort", "deal_id"))
  list(panel = panel, hull = hull, support = support)
}

message("39d: load certified pre-period artifacts")
primary_panel <- read_parquet_dt(path_prepanel)
edges <- read_parquet_dt(path_edges)
treated_path <- read_parquet_dt(path_treated)
donor_path <- read_parquet_dt(path_donor)
if (min(primary_panel$event_time) != -5L ||
    max(primary_panel$event_time) != -1L ||
    data.table::uniqueN(primary_panel$deal_id) != 235L ||
    any(!is.finite(primary_panel$treated_outcome)) ||
    any(!is.finite(primary_panel$donor_outcome))) {
  stop("Primary prepanel invariant failed")
}

message("39d: run governing rolling validation")
started <- proc.time()[["elapsed"]]
primary <- rolling_validate(primary_panel, "inventor_weighted")
lmv2_ppscm_atomic_csv(
  primary$pooled,file.path(out_dir,"_checkpoint_primary_pooled.csv"))
lmv2_ppscm_atomic_csv(
  primary$selection,file.path(out_dir,"_checkpoint_primary_selection.csv"))
equal_deal <- reaggregate_rolling(
  primary_panel, primary, "equal_deal")
uniform_primary <- fixed_weight_validation(
  primary_panel, "uniform", "inventor_weighted")
uniform_equal <- fixed_weight_validation(
  primary_panel, "uniform", "equal_deal")
nearest <- fixed_weight_validation(
  primary_panel, "nearest", "inventor_weighted")
fixed_lambdas <- setNames(
  primary$selection$selected_lambda,
  as.character(primary$selection$held_time))
endpoint_separate <- rolling_validate(
  primary_panel, "inventor_weighted",
  nu_override = 0, fixed_lambdas = fixed_lambdas)
endpoint_pooled <- rolling_validate(
  primary_panel, "inventor_weighted",
  nu_override = 1, fixed_lambdas = fixed_lambdas)
deterministic_seconds <- proc.time()[["elapsed"]] - started

observed_joint <- weighted_gap_covariance(
  primary$deal, primary$deal_weights)

message("39d: run frozen screening sensitivities")
specifications <- data.table::data.table(
  specification = c(
    "full_k10", "full_k20", "full_k50",
    "drop_ipc_k20", "drop_career_k20",
    "drop_outcome_level_k20", "deal69_primary_k20"),
  metric = c(
    "full", "full", "full", "drop_ipc", "drop_career",
    "drop_outcome_level", "full"),
  k = c(10L, 20L, 50L, 20L, 20L, 20L, 20L),
  add_deal69 = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE))
sensitivity_rows <- list()
sensitivity_paths <- list()
for (i in seq_len(nrow(specifications))) {
  s <- specifications[i]
  if (s$specification == "full_k20") {
    fit <- primary
    panel <- primary_panel
    selected <- select_pool(edges, "full", 20L)
    built <- build_spec_panel(selected, treated_path, donor_path)
  } else {
    selected <- select_pool(edges, s$metric, s$k)
    built <- build_spec_panel(
      selected, treated_path, donor_path, s$add_deal69)
    panel <- built$panel
    fit <- rolling_validate(
      panel, "inventor_weighted", fixed_lambdas = fixed_lambdas)
  }
  uniform <- fixed_weight_validation(
    panel, "uniform", "inventor_weighted")
  deal_info <- unique(panel[, .(deal_id, n_treated)])
  sensitivity_rows[[s$specification]] <- data.frame(
    specification = s$specification,
    metric = s$metric, donor_cap = s$k,
    hull_supported_deals = sum(
      built$support$two_period_hull_support),
    validation_deals = data.table::uniqueN(panel$deal_id),
    retained_treated_inventors = sum(deal_info$n_treated),
    treated_coverage = sum(deal_info$n_treated) /
      as.numeric(utils::read.csv(config$units_manifest_path)$treated_inventors),
    ppscm_validation_rmse = fit$rmse,
    uniform_validation_rmse = uniform$rmse,
    maximum_absolute_ppscm_gap = fit$max_abs_gap,
    stringsAsFactors = FALSE)
  sensitivity_paths[[s$specification]] <- transform(
    fit$pooled, specification = s$specification)
}
sensitivity_summary <- data.table::rbindlist(sensitivity_rows)
sensitivity_pooled <- data.table::rbindlist(sensitivity_paths, fill = TRUE)

ess <- primary$weights[, .(
  donor_ess = 1 / sum(scm_weight^2),
  maximum_weight = max(scm_weight)),
  by = .(held_time, deal_id)]
p10_ess <- as.numeric(stats::quantile(
  ess$donor_ess, 0.10, names = FALSE))

loco <- primary$deal[, {
  cohorts <- sort(unique(cohort))
  data.table::rbindlist(lapply(cohorts, function(drop_g) {
    z <- .SD[cohort != drop_g]
    z[, aggregation_weight := n_treated / sum(n_treated),
      by = event_time]
    z[, .(
      dropped_cohort = drop_g,
      gap = sum(aggregation_weight * raw_gap)),
      by = event_time]
  }))
}]
largest_contribution <- unique(primary$deal[, .(
  deal_id, cohort, n_treated)])
largest_contribution[, deal_weight := n_treated / sum(n_treated)]
contribution_size <- merge(
  primary$deal, largest_contribution[, .(deal_id, deal_weight)],
  by = "deal_id")
top10 <- contribution_size[, .(
  absolute_contribution = max(abs(deal_weight * raw_gap))),
  by = deal_id][order(-absolute_contribution)][1:10]
influence_delete <- data.table::rbindlist(lapply(top10$deal_id, function(d) {
  z <- primary$deal[deal_id != d]
  z[, aggregation_weight := n_treated / sum(n_treated), by = event_time]
  z[, .(
    deleted_deal = d,
    gap = sum(aggregation_weight * raw_gap)),by = event_time]
}))

bootstrap <- data.table::data.table()
bootstrap_seconds <- 0
bootstrap_truncation_rate <- NA_real_
joint_p <- NA_real_
improvement_requirement_prebootstrap <- uniform_primary$rmse <=
  config$validation_equivalence_band ||
  primary$rmse <= 0.5 * uniform_primary$rmse
deterministic_terminal_failure <- !all(c(
  data.table::uniqueN(primary_panel$deal_id) >=
    config$minimum_retained_deals,
  unique(primary_panel[
    ,sum(unique(.SD[,.(deal_id,n_treated)])$n_treated)]) /
    as.numeric(utils::read.csv(config$units_manifest_path)$treated_inventors) >=
    config$minimum_treated_coverage,
  min(primary_panel[
    ,data.table::uniqueN(donor_group),by=deal_id]$V1) >=
    config$minimum_donor_firms,
  primary$rmse <= config$validation_equivalence_band,
  primary$max_abs_gap <= config$validation_equivalence_band,
  primary$rmse <= uniform_primary$rmse &&
    improvement_requirement_prebootstrap,
  primary$rmse <= nearest$rmse,
  equal_deal$rmse <= config$equal_deal_validation_band &&
    equal_deal$max_abs_gap <= config$equal_deal_validation_band,
  stats::median(ess$donor_ess) >= config$minimum_median_ess,
  p10_ess >= config$minimum_p10_ess,
  max(ess$maximum_weight) <= config$maximum_donor_weight,
  max(abs(loco$gap)) <= config$equal_deal_validation_band,
  max(abs(influence_delete$gap)) <=
    config$equal_deal_validation_band))
run_bootstrap <- bootstrap_reps > 0L &&
  !(mode == "production" && deterministic_terminal_failure)
if (mode == "production" && deterministic_terminal_failure) {
  message(
    "39d: deterministic governing gate failed; ",
    "skip Webb bootstrap because it cannot change the terminal decision")
}
if (run_bootstrap) {
  message("39d: fit all-preperiod null model for Webb reconstruction")
  all_cv <- select_lambda(
    primary_panel, config$pre_times, primary$deal_weights)
  all_fit <- fit_ppscm(
    primary_panel, config$pre_times, primary$deal_weights,
    all_cv$selected_lambda)
  all_eval <- evaluate_model(
    primary_panel, all_fit$weights, config$pre_times,
    primary$deal_weights)
  null_base <- all_eval$deal[, .(
    deal_id, event_time, synthetic_raw, raw_gap)]
  pooled_gap <- all_eval$pooled[, .(
    event_time, pooled_raw_gap = raw_gap)]
  null_base <- merge(null_base, pooled_gap, by = "event_time")
  null_base[, centered_residual := raw_gap - pooled_raw_gap]
  deal_ids <- sort(unique(primary_panel$deal_id))
  webb <- c(
    -sqrt(1.5), -1, -sqrt(0.5),
    sqrt(0.5), 1, sqrt(1.5))
  set.seed(config$bootstrap_seed)
  multipliers <- matrix(
    sample(webb, length(deal_ids) * bootstrap_reps, replace = TRUE),
    nrow = length(deal_ids), ncol = bootstrap_reps)
  clipped <- 0
  reconstructed <- 0
  boot_started <- proc.time()[["elapsed"]]
  boot_rows <- vector("list", bootstrap_reps)
  for (b in seq_len(bootstrap_reps)) {
    mult <- data.table::data.table(
      deal_id = deal_ids, multiplier = multipliers[, b])
    pseudo_treated <- merge(null_base, mult, by = "deal_id")
    pseudo_treated[, raw_unclipped :=
      synthetic_raw + multiplier * centered_residual]
    clipped <- clipped + sum(pseudo_treated$raw_unclipped < 0)
    reconstructed <- reconstructed + nrow(pseudo_treated)
    pseudo_treated[, treated_boot := pmax(raw_unclipped, 0)]
    boot_panel <- merge(
      primary_panel,
      pseudo_treated[, .(deal_id, event_time, treated_boot)],
      by = c("deal_id", "event_time"), sort = FALSE)
    boot_panel[, treated_outcome := treated_boot]
    boot_fit <- rolling_validate(
      boot_panel, "inventor_weighted")
    boot_joint <- weighted_gap_covariance(
      boot_fit$deal, boot_fit$deal_weights)
    boot_rows[[b]] <- data.frame(
      replication = b,
      statistic = boot_joint$statistic,
      gap_m3 = boot_joint$mu[[1]],
      gap_m2 = boot_joint$mu[[2]],
      gap_m1 = boot_joint$mu[[3]])
    if (b %% 25L == 0L) {
      message("39d Webb bootstrap: ", b, "/", bootstrap_reps)
    }
  }
  bootstrap_seconds <- proc.time()[["elapsed"]] - boot_started
  bootstrap <- data.table::rbindlist(boot_rows)
  bootstrap_truncation_rate <- clipped / max(reconstructed, 1L)
  joint_p <- (
    1 + sum(bootstrap$statistic >= observed_joint$statistic)) /
    (bootstrap_reps + 1)
}

improvement_requirement <- improvement_requirement_prebootstrap
gate <- data.frame(
  gate = c(
    "minimum_retained_deals",
    "minimum_treated_coverage",
    "minimum_donor_firms",
    "validation_rmse_within_0_05_redundant",
    "each_validation_gap_within_0_05_redundant",
    "no_worse_than_uniform_and_required_improvement",
    "no_worse_than_nearest_donor",
    "joint_webb_p_above_0_10",
    "equal_deal_validation_within_0_075",
    "weight_concentration",
    "leave_one_cohort_out_within_0_075",
    "largest_contribution_deletions_within_0_075"),
  value = c(
    data.table::uniqueN(primary_panel$deal_id),
    unique(primary_panel[,sum(unique(.SD[,.(deal_id,n_treated)])$n_treated)]) /
      as.numeric(utils::read.csv(config$units_manifest_path)$treated_inventors),
    min(primary_panel[,data.table::uniqueN(donor_group),by=deal_id]$V1),
    primary$rmse,primary$max_abs_gap,primary$rmse,primary$rmse,
    joint_p,max(equal_deal$rmse,equal_deal$max_abs_gap),
    max(
      config$minimum_median_ess / stats::median(ess$donor_ess),
      config$minimum_p10_ess / p10_ess,
      max(ess$maximum_weight) / config$maximum_donor_weight),
    max(abs(loco$gap)),max(abs(influence_delete$gap))),
  threshold = c(
    paste0(">=",config$minimum_retained_deals),
    paste0(">=",config$minimum_treated_coverage),
    paste0(">=",config$minimum_donor_firms),
    "<=0.05 (logically redundant)","<=0.05 (logically redundant)",
    paste0("<=",signif(uniform_primary$rmse,6)),
    paste0("<=",signif(nearest$rmse,6)),">0.10",
    "RMSE and max |gap| <=0.075",
    "median ESS>=2; p10 ESS>=1.25; max weight<=0.90",
    "<=0.075","<=0.075"),
  pass = c(
    data.table::uniqueN(primary_panel$deal_id) >=
      config$minimum_retained_deals,
    unique(primary_panel[,sum(unique(.SD[,.(deal_id,n_treated)])$n_treated)]) /
      as.numeric(utils::read.csv(config$units_manifest_path)$treated_inventors) >=
      config$minimum_treated_coverage,
    min(primary_panel[,data.table::uniqueN(donor_group),by=deal_id]$V1) >=
      config$minimum_donor_firms,
    primary$rmse <= config$validation_equivalence_band,
    primary$max_abs_gap <= config$validation_equivalence_band,
    primary$rmse <= uniform_primary$rmse && improvement_requirement,
    primary$rmse <= nearest$rmse,
    is.finite(joint_p) && joint_p > 0.10,
    equal_deal$rmse <= config$equal_deal_validation_band &&
      equal_deal$max_abs_gap <= config$equal_deal_validation_band,
    stats::median(ess$donor_ess) >= config$minimum_median_ess &&
      p10_ess >= config$minimum_p10_ess &&
      max(ess$maximum_weight) <= config$maximum_donor_weight,
    max(abs(loco$gap)) <= config$equal_deal_validation_band,
    max(abs(influence_delete$gap)) <=
      config$equal_deal_validation_band),
  governing = c(
    TRUE,TRUE,TRUE,FALSE,FALSE,TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,TRUE),
  stringsAsFactors = FALSE)
if (mode != "production") {
  gate$pass[gate$gate == "joint_webb_p_above_0_10"] <- FALSE
}
validation_pass <- mode == "production" && all(gate$pass)

lmv2_ppscm_atomic_csv(
  primary$pooled,file.path(out_dir,"primary_validation_pooled.csv"))
lmv2_ppscm_atomic_csv(
  primary$deal,file.path(out_dir,"primary_validation_deal.csv"))
lmv2_ppscm_atomic_csv(
  primary$weights,file.path(out_dir,"primary_validation_weights.csv"))
lmv2_ppscm_atomic_csv(
  primary$selection,file.path(out_dir,"primary_fold_selection.csv"))
lmv2_ppscm_atomic_csv(
  primary$curves,file.path(out_dir,"primary_nested_cv_curves.csv"))
lmv2_ppscm_atomic_csv(
  data.table::rbindlist(list(
    transform(uniform_primary$pooled,estimator="uniform_inventor"),
    transform(uniform_equal$pooled,estimator="uniform_equal_deal"),
    transform(nearest$pooled,estimator="nearest_inventor"),
    transform(equal_deal$pooled,estimator="ppscm_equal_deal"),
    transform(endpoint_separate$pooled,estimator="ppscm_nu_0"),
    transform(endpoint_pooled$pooled,estimator="ppscm_nu_1")),
    fill=TRUE),
  file.path(out_dir,"validation_benchmarks.csv"))
lmv2_ppscm_atomic_csv(
  ess,file.path(out_dir,"weight_concentration.csv"))
lmv2_ppscm_atomic_csv(
  loco,file.path(out_dir,"leave_one_cohort_out.csv"))
lmv2_ppscm_atomic_csv(
  influence_delete,file.path(out_dir,"influence_deletions.csv"))
lmv2_ppscm_atomic_csv(
  sensitivity_summary,file.path(out_dir,"screening_sensitivity_summary.csv"))
lmv2_ppscm_atomic_csv(
  sensitivity_pooled,file.path(out_dir,"screening_sensitivity_paths.csv"))
lmv2_ppscm_atomic_csv(
  bootstrap,file.path(out_dir,"webb_bootstrap_draws.csv"))
lmv2_ppscm_atomic_csv(
  gate,file.path(out_dir,"validation_gate.csv"))

summary <- data.frame(
  version = config$version, mode = mode,
  source_sha256 = source_sha256,
  config_sha256 = config_sha256,
  freeze_sha256 = freeze_sha256,
  census_manifest_sha256 = census_manifest_sha256,
  retained_deals = data.table::uniqueN(primary_panel$deal_id),
  retained_treated_inventors = unique(primary_panel[
    ,sum(unique(.SD[,.(deal_id,n_treated)])$n_treated)]),
  primary_validation_rmse = primary$rmse,
  primary_validation_max_abs_gap = primary$max_abs_gap,
  uniform_validation_rmse = uniform_primary$rmse,
  nearest_validation_rmse = nearest$rmse,
  equal_deal_validation_rmse = equal_deal$rmse,
  joint_observed_statistic = observed_joint$statistic,
  joint_webb_p_value = joint_p,
  bootstrap_replications_requested = bootstrap_reps,
  bootstrap_replications_completed = nrow(bootstrap),
  bootstrap_skipped_for_terminal_deterministic_failure =
    mode == "production" && deterministic_terminal_failure,
  bootstrap_truncation_rate = bootstrap_truncation_rate,
  deterministic_seconds = deterministic_seconds,
  bootstrap_seconds = bootstrap_seconds,
  projected_production_hours = if (nrow(bootstrap) > 0)
    bootstrap_seconds / bootstrap_reps *
      config$bootstrap_replications / 3600 else NA_real_,
  optimized_weights_estimated = TRUE,
  post_outcomes_queried = FALSE,
  validation_pass = validation_pass,
  status = if (validation_pass) "CERTIFIED_TO_CONTROL_NULL" else
    if (mode == "production") "VALIDATION_FAILED" else
      "NONCERTIFYING_PROFILE",
  stringsAsFactors = FALSE)
lmv2_ppscm_atomic_csv(
  summary,file.path(out_dir,"validation_summary.csv"))

artifact_paths <- list.files(out_dir, full.names = TRUE)
artifact_paths <- artifact_paths[
  basename(artifact_paths) != "artifact_hashes.csv" &
    !file.info(artifact_paths)$isdir]
artifact_hashes <- data.frame(
  artifact=basename(artifact_paths),
  sha256=vapply(
    artifact_paths,lmv2_ppscm_sha256,character(1)),
  stringsAsFactors=FALSE)
lmv2_ppscm_atomic_csv(
  artifact_hashes,file.path(out_dir,"artifact_hashes.csv"))

message(
  "39d ",mode," complete | PPSCM RMSE=",
  sprintf("%.5f",primary$rmse),
  " | uniform=",sprintf("%.5f",uniform_primary$rmse),
  " | Webb p=",ifelse(is.finite(joint_p),sprintf("%.4f",joint_p),"pending"),
  " | status=",summary$status)

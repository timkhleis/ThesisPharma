# ============================================================================
# 12c_verginer_ebal_utils.R -- cell engine, diagnostics, bootstrap, reporting
# ============================================================================

required_packages_12(c("did", "WeightIt", "digest", "ggplot2"))

rhs_labels_12 <- function(rhs) {
  paste(deparse(rhs), collapse = "")
}

ess_12 <- function(w) {
  w <- w[is.finite(w) & w > 0]
  if (length(w) == 0L) return(NA_real_)
  sum(w)^2 / sum(w^2)
}

weighted_mean_12 <- function(x, w) {
  sum(w * x) / sum(w)
}

model_matrix_no_intercept_12 <- function(rhs, data) {
  mm <- stats::model.matrix(rhs, data = data)
  mm[, colnames(mm) != "(Intercept)", drop = FALSE]
}

standardize_ebal_data_12 <- function(rhs, data) {
  out <- data
  for (v in all.vars(rhs)) {
    if (v %in% names(out) && is.numeric(out[[v]])) {
      s <- stats::sd(out[[v]], na.rm = TRUE)
      m <- mean(out[[v]], na.rm = TRUE)
      if (is.finite(s) && s > 0) out[[v]] <- (out[[v]] - m) / s
    }
  }
  out
}

balance_maxdiff_12 <- function(rhs, data, D, w) {
  mm <- model_matrix_no_intercept_12(rhs, data)
  if (ncol(mm) == 0L) return(0)
  max(vapply(seq_len(ncol(mm)), function(j) {
    abs(weighted_mean_12(mm[D == 1L, j], w[D == 1L]) -
          weighted_mean_12(mm[D == 0L, j], w[D == 0L]))
  }, numeric(1)))
}

covariate_balance_12 <- function(rhs, data, D, w) {
  mm <- model_matrix_no_intercept_12(rhs, data)
  if (ncol(mm) == 0L) {
    return(data.frame(
      covariate = character(), treated_mean = numeric(),
      control_mean = numeric(), difference = numeric(),
      abs_difference = numeric()
    ))
  }
  rows <- lapply(seq_len(ncol(mm)), function(j) {
    mt <- weighted_mean_12(mm[D == 1L, j], w[D == 1L])
    mc <- weighted_mean_12(mm[D == 0L, j], w[D == 0L])
    data.frame(
      covariate = colnames(mm)[j],
      treated_mean = mt,
      control_mean = mc,
      difference = mt - mc,
      abs_difference = abs(mt - mc)
    )
  })
  do.call(rbind, rows)
}

classify_balance_12 <- function(maxdiff, mass_ok = TRUE, weights_ok = TRUE,
                                empty_cell = FALSE, solver_error = FALSE) {
  if (empty_cell) return("true_feasibility_failure")
  if (solver_error || !mass_ok || !weights_ok || !is.finite(maxdiff)) {
    return("true_feasibility_failure")
  }
  if (maxdiff <= BALANCE_TOL) return("exact_pass")
  if (maxdiff <= SOLVER_RESIDUAL_TOL) return("solver_tolerance_residual")
  if (maxdiff <= LARGE_RESIDUAL_TOL) return("review_residual")
  "true_feasibility_failure"
}

make_panel_arrays_12 <- function(data, outcome, id_col = "codinv") {
  d <- data[order(data[[id_col]], data$calendar_year), ]
  ids <- unique(d[[id_col]])
  years <- sort(unique(d$calendar_year))
  unit_rows <- match(ids, d[[id_col]])
  unit <- d[unit_rows, , drop = FALSE]
  y <- matrix(NA_real_, nrow = length(ids), ncol = length(years))
  y[cbind(match(d[[id_col]], ids), match(d$calendar_year, years))] <- d[[outcome]]
  if (anyNA(y)) stop("Panel is not balanced for outcome: ", outcome)
  list(ids = ids, years = years, unit = unit, y = y)
}

cell_indices_12 <- function(years, g, event_window = EVENT_WINDOW) {
  out <- lapply(event_window, function(e) {
    target <- as.integer(g + e)
    target_idx <- match(target, years)
    if (is.na(target_idx) || target_idx <= 1L) return(NULL)
    pre_idx <- target_idx - 1L
    if (target >= g) {
      pretreat <- which(years < g)
      if (length(pretreat) == 0L) return(NULL)
      pre_idx <- pretreat[length(pretreat)]
    }
    data.frame(
      group = as.integer(g),
      time = target,
      event_time = as.integer(e),
      pre_time = years[pre_idx],
      target_idx = target_idx,
      pre_idx = pre_idx
    )
  })
  do.call(rbind, out)
}

all_cells_12 <- function(unit, years, event_window = EVENT_WINDOW) {
  support <- did_support_universe_12(unit, years)
  out <- lapply(support$treated_groups, cell_indices_12,
                years = support$support_years, event_window = event_window)
  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out
}

did_support_universe_12 <- function(unit, years) {
  glist_all <- sort(unique(unit$treatment_year))
  positive_groups <- glist_all[glist_all > 0]
  support_years <- sort(unique(years))
  excluded_latest_group <- NA_integer_
  support_rule <- "all_positive_treated_groups"
  if (CONTROL_GROUP == "notyettreated" && !any(glist_all == 0L)) {
    excluded_latest_group <- max(positive_groups, na.rm = TRUE)
    positive_groups <- positive_groups[positive_groups < excluded_latest_group]
    support_years <- support_years[support_years < excluded_latest_group - ANTICIPATION]
    support_rule <- "did_2.5_no_never_notyet_exclude_latest_group_and_later_periods"
  }
  first_period <- min(support_years, na.rm = TRUE)
  treated_groups <- positive_groups[positive_groups > first_period + ANTICIPATION]
  list(
    treated_groups = treated_groups,
    support_years = support_years,
    excluded_latest_group = excluded_latest_group,
    support_rule = support_rule
  )
}

cell_engine_12 <- function(data, outcome, spec, rhs = ~1, method = c("unadjusted", "ebal"),
                           id_col = "codinv", bootstrap_replication = 0L,
                           return_weights = FALSE, stop_on_failure = FALSE) {
  method <- match.arg(method)
  arr <- make_panel_arrays_12(data, outcome, id_col = id_col)
  unit <- arr$unit
  years <- arr$years
  cells <- all_cells_12(unit, years)
  results <- list()
  failures <- list()
  balance <- list()
  weight_diag <- list()
  covariate_balance <- list()
  problem_cells <- list()
  weights <- list()

  for (i in seq_len(nrow(cells))) {
    ce <- cells[i, ]
    D <- as.integer(unit$treatment_year == ce$group)
    threshold <- ce$time + ANTICIPATION
    C <- as.integer(unit$treatment_year == 0L |
                      (unit$treatment_year > threshold &
                         unit$treatment_year != ce$group))
    keep <- D == 1L | C == 1L
    Dk <- D[keep]
    idx <- which(keep)
    n_t <- sum(Dk == 1L)
    n_c <- sum(Dk == 0L)
    if (n_t == 0L || n_c == 0L) {
      msg <- if (n_t == 0L) "empty_treated_cell" else "empty_control_cell"
      failures[[length(failures) + 1L]] <- data.frame(
        specification = spec, bootstrap_replication = bootstrap_replication,
        group = ce$group, time = ce$time, event_time = ce$event_time,
        reason = msg,
        balance_category = "true_feasibility_failure"
      )
      problem_cells[[length(problem_cells) + 1L]] <- data.frame(
        specification = spec, bootstrap_replication = bootstrap_replication,
        group = ce$group, time = ce$time, event_time = ce$event_time,
        n_treated = n_t, n_control = n_c,
        max_abs_mean_difference = NA_real_, control_ess = NA_real_,
        max_control_share = NA_real_,
        balance_category = "true_feasibility_failure",
        reason = msg
      )
      if (stop_on_failure) stop(msg)
      next
    }
    dy <- arr$y[idx, ce$target_idx] - arr$y[idx, ce$pre_idx]
    cd <- unit[idx, , drop = FALSE]
    cd$D <- Dk
    iw <- rep(1, length(dy))

    if (method == "unadjusted") {
      w <- iw
      converged <- TRUE
      maxdiff <- NA_real_
      raw_ratio <- NA_real_
      balance_category <- "not_applicable"
    } else {
      key <- digest::digest(list(
        specification = spec,
        bootstrap_replication = bootstrap_replication,
        group = ce$group,
        time = ce$time,
        base_period = BASE_PERIOD,
        ids = as.character(cd[[id_col]]),
        D = Dk,
        covariates = stats::model.matrix(rhs, data = cd),
        i.weights = iw
      ))
      ebal_formula <- stats::as.formula(paste("D", rhs_labels_12(rhs), sep = " "))
      ebal_data <- standardize_ebal_data_12(rhs, cd)
      fit <- tryCatch(
        WeightIt::weightit(
          ebal_formula, data = ebal_data, method = "ebal", estimand = "ATT",
          moments = 1, s.weights = iw, maxit = EBAL_MAXIT
        ),
        error = function(e) e
      )
      if (inherits(fit, "error")) {
        reason <- paste0("ebal_error: ", conditionMessage(fit))
        failures[[length(failures) + 1L]] <- data.frame(
          specification = spec, bootstrap_replication = bootstrap_replication,
          group = ce$group, time = ce$time, event_time = ce$event_time,
          reason = reason,
          balance_category = "true_feasibility_failure"
        )
        problem_cells[[length(problem_cells) + 1L]] <- data.frame(
          specification = spec, bootstrap_replication = bootstrap_replication,
          group = ce$group, time = ce$time, event_time = ce$event_time,
          n_treated = n_t, n_control = n_c,
          max_abs_mean_difference = NA_real_, control_ess = NA_real_,
          max_control_share = NA_real_,
          balance_category = "true_feasibility_failure",
          reason = reason
        )
        if (stop_on_failure) stop(conditionMessage(fit))
        next
      }
      raw_w <- as.numeric(fit$weights)
      w <- raw_w
      w[Dk == 1L] <- 1
      raw_control_mass <- sum(iw[Dk == 0L] * w[Dk == 0L])
      treated_mass <- sum(iw[Dk == 1L])
      if (!is.finite(raw_control_mass) || raw_control_mass <= 0) {
        failures[[length(failures) + 1L]] <- data.frame(
          specification = spec, bootstrap_replication = bootstrap_replication,
          group = ce$group, time = ce$time, event_time = ce$event_time,
          reason = "nonpositive_control_mass",
          balance_category = "true_feasibility_failure"
        )
        problem_cells[[length(problem_cells) + 1L]] <- data.frame(
          specification = spec, bootstrap_replication = bootstrap_replication,
          group = ce$group, time = ce$time, event_time = ce$event_time,
          n_treated = n_t, n_control = n_c,
          max_abs_mean_difference = NA_real_, control_ess = NA_real_,
          max_control_share = NA_real_,
          balance_category = "true_feasibility_failure",
          reason = "nonpositive_control_mass"
        )
        if (stop_on_failure) stop("nonpositive_control_mass")
        next
      }
      w[Dk == 0L] <- w[Dk == 0L] * treated_mass / raw_control_mass
      maxdiff <- balance_maxdiff_12(rhs, cd, Dk, w)
      weights_ok <- all(is.finite(w)) && all(w > 0) &&
        max(abs(w[Dk == 1L] - 1)) <= 1e-8
      mass_ok <- abs(sum(w[Dk == 0L]) - sum(w[Dk == 1L])) <= 1e-6
      balance_category <- classify_balance_12(maxdiff, mass_ok, weights_ok)
      converged <- balance_category %in% c(
        "exact_pass", "solver_tolerance_residual", "review_residual"
      )
      raw_ratio <- max(w[Dk == 0L]) / min(w[Dk == 0L])
      cb <- covariate_balance_12(rhs, cd, Dk, w)
      if (nrow(cb) > 0L) {
        cb$specification <- spec
        cb$bootstrap_replication <- bootstrap_replication
        cb$group <- ce$group
        cb$time <- ce$time
        cb$event_time <- ce$event_time
        cb$balance_category <- balance_category
        covariate_balance[[length(covariate_balance) + 1L]] <- cb
      }
      if (balance_category != "exact_pass") {
        problem_cells[[length(problem_cells) + 1L]] <- data.frame(
          specification = spec, bootstrap_replication = bootstrap_replication,
          group = ce$group, time = ce$time, event_time = ce$event_time,
          n_treated = n_t, n_control = n_c,
          max_abs_mean_difference = maxdiff,
          control_ess = ess_12(w[Dk == 0L]),
          max_control_share = max(w[Dk == 0L]) / sum(w[Dk == 0L]),
          balance_category = balance_category,
          reason = sprintf("maxdiff_%0.3e", maxdiff)
        )
      }
      if (balance_category == "true_feasibility_failure") {
        failures[[length(failures) + 1L]] <- data.frame(
          specification = spec, bootstrap_replication = bootstrap_replication,
          group = ce$group, time = ce$time, event_time = ce$event_time,
          reason = sprintf("large_residual_maxdiff_%0.3e", maxdiff),
          balance_category = balance_category
        )
        if (stop_on_failure) stop("balance_or_weight_gate_failed")
        next
      }
      if (return_weights) {
        weights[[length(weights) + 1L]] <- data.frame(
          specification = spec, bootstrap_replication = bootstrap_replication,
          group = ce$group, time = ce$time, event_time = ce$event_time,
          cache_key = key, unit_id = as.character(cd[[id_col]]), D = Dk, weight = w
        )
      }
    }

    att <- weighted_mean_12(dy[Dk == 1L], w[Dk == 1L]) -
      weighted_mean_12(dy[Dk == 0L], w[Dk == 0L])
    results[[length(results) + 1L]] <- data.frame(
      specification = spec, bootstrap_replication = bootstrap_replication,
      group = ce$group, time = ce$time, event_time = ce$event_time,
      pre_time = ce$pre_time, att = att, n_treated = n_t, n_control = n_c
    )
    weight_diag[[length(weight_diag) + 1L]] <- data.frame(
      specification = spec, bootstrap_replication = bootstrap_replication,
      group = ce$group, time = ce$time, event_time = ce$event_time,
      treated_mass = sum(w[Dk == 1L]), control_mass = sum(w[Dk == 0L]),
      control_ess = ess_12(w[Dk == 0L]),
      max_control_share = max(w[Dk == 0L]) / sum(w[Dk == 0L]),
      top5_control_share = sum(sort(w[Dk == 0L], decreasing = TRUE)[seq_len(min(5, n_c))]) /
        sum(w[Dk == 0L]),
      control_weight_ratio = raw_ratio,
      converged = converged,
      balance_category = balance_category
    )
    balance[[length(balance) + 1L]] <- data.frame(
      specification = spec, bootstrap_replication = bootstrap_replication,
      group = ce$group, time = ce$time, event_time = ce$event_time,
      max_abs_mean_difference = maxdiff,
      pass = isTRUE(converged),
      balance_category = balance_category
    )
  }

  list(
    cells = if (length(results)) do.call(rbind, results) else data.frame(),
    failures = if (length(failures)) do.call(rbind, failures) else data.frame(),
    balance = if (length(balance)) do.call(rbind, balance) else data.frame(),
    weight_diag = if (length(weight_diag)) do.call(rbind, weight_diag) else data.frame(),
    covariate_balance = if (length(covariate_balance)) do.call(rbind, covariate_balance) else data.frame(),
    problem_cells = if (length(problem_cells)) do.call(rbind, problem_cells) else data.frame(),
    weights = if (length(weights)) do.call(rbind, weights) else data.frame()
  )
}

cell_engine_multi_12 <- function(data, outcomes, spec, rhs = ~1,
                                 method = c("unadjusted", "ebal"),
                                 id_col = "codinv", bootstrap_replication = 0L,
                                 stop_on_failure = FALSE) {
  method <- match.arg(method)
  arr0 <- make_panel_arrays_12(data, outcomes[1], id_col = id_col)
  y_list <- lapply(outcomes, function(outcome) {
    make_panel_arrays_12(data, outcome, id_col = id_col)$y
  })
  names(y_list) <- outcomes
  unit <- arr0$unit
  years <- arr0$years
  cells <- all_cells_12(unit, years)
  results <- list()
  failures <- list()
  balance <- list()
  weight_diag <- list()

  for (i in seq_len(nrow(cells))) {
    ce <- cells[i, ]
    D <- as.integer(unit$treatment_year == ce$group)
    threshold <- ce$time + ANTICIPATION
    C <- as.integer(unit$treatment_year == 0L |
                      (unit$treatment_year > threshold &
                         unit$treatment_year != ce$group))
    keep <- D == 1L | C == 1L
    Dk <- D[keep]
    idx <- which(keep)
    n_t <- sum(Dk == 1L)
    n_c <- sum(Dk == 0L)
    if (n_t == 0L || n_c == 0L) {
      msg <- if (n_t == 0L) "empty_treated_cell" else "empty_control_cell"
      failures[[length(failures) + 1L]] <- data.frame(
        specification = spec, bootstrap_replication = bootstrap_replication,
        group = ce$group, time = ce$time, event_time = ce$event_time,
        reason = msg,
        balance_category = "true_feasibility_failure"
      )
      if (stop_on_failure) stop(msg)
      next
    }
    cd <- unit[idx, , drop = FALSE]
    cd$D <- Dk
    iw <- rep(1, length(Dk))
    if (method == "unadjusted") {
      w <- iw
      converged <- TRUE
      maxdiff <- NA_real_
      raw_ratio <- NA_real_
      balance_category <- "not_applicable"
    } else {
      ebal_formula <- stats::as.formula(paste("D", rhs_labels_12(rhs), sep = " "))
      ebal_data <- standardize_ebal_data_12(rhs, cd)
      fit <- tryCatch(
        WeightIt::weightit(
          ebal_formula, data = ebal_data, method = "ebal", estimand = "ATT",
          moments = 1, s.weights = iw, maxit = EBAL_MAXIT
        ),
        error = function(e) e
      )
      if (inherits(fit, "error")) {
        failures[[length(failures) + 1L]] <- data.frame(
          specification = spec, bootstrap_replication = bootstrap_replication,
          group = ce$group, time = ce$time, event_time = ce$event_time,
          reason = paste0("ebal_error: ", conditionMessage(fit)),
          balance_category = "true_feasibility_failure"
        )
        if (stop_on_failure) stop(conditionMessage(fit))
        next
      }
      w <- as.numeric(fit$weights)
      w[Dk == 1L] <- 1
      raw_control_mass <- sum(w[Dk == 0L])
      treated_mass <- sum(w[Dk == 1L])
      if (!is.finite(raw_control_mass) || raw_control_mass <= 0) {
        failures[[length(failures) + 1L]] <- data.frame(
          specification = spec, bootstrap_replication = bootstrap_replication,
          group = ce$group, time = ce$time, event_time = ce$event_time,
          reason = "nonpositive_control_mass",
          balance_category = "true_feasibility_failure"
        )
        if (stop_on_failure) stop("nonpositive_control_mass")
        next
      }
      w[Dk == 0L] <- w[Dk == 0L] * treated_mass / raw_control_mass
      maxdiff <- balance_maxdiff_12(rhs, cd, Dk, w)
      weights_ok <- all(is.finite(w)) && all(w > 0) &&
        max(abs(w[Dk == 1L] - 1)) <= 1e-8
      mass_ok <- abs(sum(w[Dk == 0L]) - sum(w[Dk == 1L])) <= 1e-6
      balance_category <- classify_balance_12(maxdiff, mass_ok, weights_ok)
      converged <- balance_category %in% c(
        "exact_pass", "solver_tolerance_residual", "review_residual"
      )
      raw_ratio <- max(w[Dk == 0L]) / min(w[Dk == 0L])
      if (balance_category == "true_feasibility_failure") {
        failures[[length(failures) + 1L]] <- data.frame(
          specification = spec, bootstrap_replication = bootstrap_replication,
          group = ce$group, time = ce$time, event_time = ce$event_time,
          reason = sprintf("large_residual_maxdiff_%0.3e", maxdiff),
          balance_category = balance_category
        )
        if (stop_on_failure) stop("balance_or_weight_gate_failed")
        next
      }
    }
    for (outcome in outcomes) {
      dy <- y_list[[outcome]][idx, ce$target_idx] - y_list[[outcome]][idx, ce$pre_idx]
      att <- weighted_mean_12(dy[Dk == 1L], w[Dk == 1L]) -
        weighted_mean_12(dy[Dk == 0L], w[Dk == 0L])
      results[[length(results) + 1L]] <- data.frame(
        outcome = outcome,
        specification = spec,
        bootstrap_replication = bootstrap_replication,
        group = ce$group, time = ce$time, event_time = ce$event_time,
        pre_time = ce$pre_time, att = att, n_treated = n_t, n_control = n_c
      )
    }
    weight_diag[[length(weight_diag) + 1L]] <- data.frame(
      specification = spec, bootstrap_replication = bootstrap_replication,
      group = ce$group, time = ce$time, event_time = ce$event_time,
      treated_mass = sum(w[Dk == 1L]), control_mass = sum(w[Dk == 0L]),
      control_ess = ess_12(w[Dk == 0L]),
      max_control_share = max(w[Dk == 0L]) / sum(w[Dk == 0L]),
      top5_control_share = sum(sort(w[Dk == 0L], decreasing = TRUE)[seq_len(min(5, n_c))]) /
        sum(w[Dk == 0L]),
      control_weight_ratio = raw_ratio,
      converged = converged,
      balance_category = balance_category
    )
    balance[[length(balance) + 1L]] <- data.frame(
      specification = spec, bootstrap_replication = bootstrap_replication,
      group = ce$group, time = ce$time, event_time = ce$event_time,
      max_abs_mean_difference = maxdiff,
      pass = isTRUE(converged),
      balance_category = balance_category
    )
  }

  list(
    cells = if (length(results)) do.call(rbind, results) else data.frame(),
    failures = if (length(failures)) do.call(rbind, failures) else data.frame(),
    balance = if (length(balance)) do.call(rbind, balance) else data.frame(),
    weight_diag = if (length(weight_diag)) do.call(rbind, weight_diag) else data.frame()
  )
}

aggregate_cells_12 <- function(cells, outcome, spec) {
  if (nrow(cells) == 0L) return(data.frame())
  dyn <- do.call(rbind, lapply(sort(unique(cells$event_time)), function(e) {
    cc <- cells[cells$event_time == e, , drop = FALSE]
    w <- cc$n_treated
    data.frame(
      outcome = outcome, outcome_label = unname(OUTCOME_LABELS[outcome]),
      specification = spec, event_time = e,
      att = weighted_mean_12(cc$att, w),
      n_cells = nrow(cc),
      n_treated_cells = sum(cc$n_treated),
      analytical_se_nonreportable = NA_real_
    )
  }))
  rownames(dyn) <- NULL
  dyn
}

summary_from_dynamic_12 <- function(dynamic, outcome, spec) {
  rows <- dynamic[dynamic$outcome == outcome & dynamic$specification == spec, ]
  get_att <- function(e) {
    v <- rows$att[rows$event_time == e]
    if (length(v) == 0L) NA_real_ else v[1]
  }
  post <- rows[rows$event_time %in% 1:5, , drop = FALSE]
  data.frame(
    outcome = outcome,
    outcome_label = unname(OUTCOME_LABELS[outcome]),
    specification = spec,
    summary = c("overall_post_t1_to_t5", "event_t0"),
    att = c(if (nrow(post)) mean(post$att) else NA_real_, get_att(0L))
  )
}

estimate_did_cells_12 <- function(data, outcome, rhs, spec, id_col = "codinv") {
  d <- data
  d$est_deal_year <- d$treatment_year
  messages <- character()
  att <- withCallingHandlers(
    did::att_gt(
      yname = outcome,
      tname = "calendar_year",
      idname = id_col,
      gname = "est_deal_year",
      xformla = rhs,
      data = d,
      panel = TRUE,
      allow_unbalanced_panel = FALSE,
      control_group = CONTROL_GROUP,
      anticipation = ANTICIPATION,
      base_period = BASE_PERIOD,
      est_method = "dr",
      bstrap = FALSE,
      cband = FALSE,
      print_details = FALSE,
      compute_inffunc = FALSE
    ),
    warning = function(w) {
      messages <<- c(messages, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  cells <- data.frame(
    specification = spec,
    bootstrap_replication = 0L,
    group = as.integer(att$group),
    time = as.integer(att$t),
    event_time = as.integer(att$t - att$group),
    att = as.numeric(att$att)
  )
  cells <- cells[cells$event_time >= EVENT_LO & cells$event_time <= EVENT_HI, ]
  unit <- d[!duplicated(d[[id_col]]), , drop = FALSE]
  n_by_group <- as.data.frame(table(group = unit$treatment_year))
  n_by_group$group <- as.integer(as.character(n_by_group$group))
  names(n_by_group)[2] <- "n_treated"
  cells$n_treated <- n_by_group$n_treated[match(cells$group, n_by_group$group)]
  cells$n_control <- NA_integer_
  list(cells = cells, warnings = unique(messages))
}

make_bootstrap_draws_12 <- function(deal_ids, biters, seed = SEED) {
  set.seed(seed)
  deals <- sort(unique(deal_ids))
  do.call(rbind, lapply(seq_len(biters), function(b) {
    data.frame(
      bootstrap_replication = b,
      draw_position = seq_along(deals),
      deal_id = sample(deals, length(deals), replace = TRUE)
    )
  }))
}

bootstrap_panel_12 <- function(panel, draws_b) {
  pieces <- vector("list", nrow(draws_b))
  for (i in seq_len(nrow(draws_b))) {
    x <- panel[panel$deal_id == draws_b$deal_id[i], , drop = FALSE]
    x$boot_cluster_position <- draws_b$draw_position[i]
    x$boot_uid <- paste(draws_b$bootstrap_replication[i], draws_b$draw_position[i],
                        x$codinv, sep = "_")
    pieces[[i]] <- x
  }
  do.call(rbind, pieces)
}

add_bootstrap_intervals_12 <- function(point_dynamic, boot_dynamic) {
  out <- point_dynamic
  out$bootstrap_se <- NA_real_
  out$ci_low <- NA_real_
  out$ci_high <- NA_real_
  out$simul_low <- NA_real_
  out$simul_high <- NA_real_
  keys <- unique(out[, c("outcome", "specification")])
  for (i in seq_len(nrow(keys))) {
    idx <- out$outcome == keys$outcome[i] & out$specification == keys$specification[i]
    pt <- out[idx, ]
    bt <- boot_dynamic[
      boot_dynamic$outcome == keys$outcome[i] &
        boot_dynamic$specification == keys$specification[i], ]
    for (e in pt$event_time) {
      vals <- bt$att[bt$event_time == e]
      vals <- vals[is.finite(vals)]
      j <- which(idx & out$event_time == e)
      if (length(vals) >= 2L) {
        out$bootstrap_se[j] <- stats::sd(vals)
        qs <- stats::quantile(vals, c(.025, .975), na.rm = TRUE, names = FALSE)
        out$ci_low[j] <- qs[1]
        out$ci_high[j] <- qs[2]
      }
    }
    se <- out$bootstrap_se[idx]
    if (all(is.finite(se) & se > 0)) {
      wide <- stats::reshape(
        bt[, c("bootstrap_replication", "event_time", "att")],
        idvar = "bootstrap_replication", timevar = "event_time", direction = "wide"
      )
      event_cols <- paste0("att.", pt$event_time)
      if (all(event_cols %in% names(wide))) {
        z <- sweep(as.matrix(wide[, event_cols, drop = FALSE]), 2, pt$att, "-")
        z <- sweep(z, 2, se, "/")
        crit <- stats::quantile(apply(abs(z), 1, max, na.rm = TRUE), .95,
                                na.rm = TRUE, names = FALSE)
        out$simul_low[idx] <- pt$att - crit * se
        out$simul_high[idx] <- pt$att + crit * se
      }
    }
  }
  out
}

pretrend_12 <- function(dynamic) {
  pre <- dynamic[dynamic$event_time >= EVENT_LO & dynamic$event_time <= -2L, ]
  do.call(rbind, lapply(split(pre, paste(pre$outcome, pre$specification, sep = "|")), function(x) {
    data.frame(
      outcome = x$outcome[1],
      specification = x$specification[1],
      n_pre_points = nrow(x),
      max_abs_pre_att = max(abs(x$att), na.rm = TRUE),
      n_pre_pointwise_excludes_zero = sum(
        is.finite(x$ci_low) & is.finite(x$ci_high) & (x$ci_low > 0 | x$ci_high < 0)
      )
    )
  }))
}

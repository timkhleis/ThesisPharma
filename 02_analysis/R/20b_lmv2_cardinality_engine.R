# Reuse-constrained cardinality matching engine.
#
# This engine targets a separate recovered-inventor ATT. It never modifies or
# appends rows to the entropy-balanced primary weights.

LMV2_CARDINALITY_FREEZE_SHA256 <-
  "850e46a6db785bfa8839031b7b073e0d8c5bd93cf261e391be7682a00098fbc4"
LMV2_CARDINALITY_FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_p5_cardinality_freeze.md")
observed_cardinality_freeze_hash <- lmv2_p3_file_hash(
  LMV2_CARDINALITY_FREEZE_PATH)
if (!identical(
    observed_cardinality_freeze_hash,
    LMV2_CARDINALITY_FREEZE_SHA256)) {
  stop(
    "P5.4 cardinality freeze drifted: expected ",
    LMV2_CARDINALITY_FREEZE_SHA256, ", observed ",
    observed_cardinality_freeze_hash)
}

LMV2_CARDINALITY <- list(
  maximum_candidates_per_treated = 50L,
  controls_per_treated = 2L,
  maximum_control_reuse = 5L,
  maximum_balance_smd = 0.10,
  distance_tiebreak = 1e-8,
  balance_variables = c(
    "log_patent_count_5y", "patent_trajectory", "career_age",
    "focal_group_exclusivity",
    "firm_log_patent_stock_5y",
    "firm_log_inventor_count_5y",
    "firm_patent_trajectory"),
  freeze_hash = LMV2_CARDINALITY_FREEZE_SHA256
)

lmv2_cardinality_match <- function(
    treated, controls, edges,
    balance_variables = LMV2_CARDINALITY$balance_variables,
    controls_per_treated =
      LMV2_CARDINALITY$controls_per_treated,
    maximum_control_reuse =
      LMV2_CARDINALITY$maximum_control_reuse,
    maximum_balance_smd =
      LMV2_CARDINALITY$maximum_balance_smd) {
  if (!requireNamespace("lpSolveAPI", quietly = TRUE)) {
    stop("The lpSolve package is required for cardinality matching")
  }
  treated_key <- c("cohort", "deal_id", "treated_codinv")
  control_key <- c(
    "cohort", "deal_id", "control_codinv", "control_group")
  edge_key <- c(treated_key, "control_codinv", "control_group")
  if (!all(c(treated_key, balance_variables) %in% names(treated)) ||
      !all(c(control_key, balance_variables) %in% names(controls)) ||
      !all(c(edge_key, "distance") %in% names(edges))) {
    stop("Cardinality input schema is incomplete")
  }
  if (anyDuplicated(treated[treated_key]) ||
      anyDuplicated(controls[control_key]) ||
      anyDuplicated(edges[edge_key])) {
    stop("Cardinality inputs contain duplicate keys")
  }
  if (!controls_per_treated %in% 1:10 ||
      !maximum_control_reuse %in% 1:100 ||
      !is.finite(maximum_balance_smd) ||
      maximum_balance_smd < 0 ||
      maximum_balance_smd > 1) {
    stop("Cardinality constraints are invalid")
  }

  candidate <- merge(
    edges, treated,
    by = treated_key, all = FALSE, sort = FALSE,
    suffixes = c("", "_treated"))
  candidate <- merge(
    candidate, controls,
    by = control_key, all = FALSE, sort = FALSE,
    suffixes = c("_treated", "_control"))
  required_values <- c(
    "distance",
    paste0(balance_variables, "_treated"),
    paste0(balance_variables, "_control"))
  candidate <- candidate[
    stats::complete.cases(candidate[required_values]) &
      is.finite(candidate$distance) &
      candidate$distance >= 0, , drop = FALSE]
  if (!nrow(candidate)) {
    return(list(
      status = "no_candidates",
      selected_edges = candidate,
      matched_treated = treated[0, , drop = FALSE],
      diagnostics = data.frame()))
  }

  treated_id <- interaction(
    candidate$cohort, candidate$deal_id,
    candidate$treated_codinv, drop = TRUE, lex.order = TRUE)
  control_id <- interaction(
    candidate$cohort, candidate$control_codinv,
    candidate$control_group, drop = TRUE, lex.order = TRUE)
  treated_firm_id <- interaction(
    candidate$cohort, candidate$deal_id,
    candidate$treated_codinv, candidate$control_group,
    drop = TRUE, lex.order = TRUE)
  counts <- table(treated_id)
  firm_counts <- tapply(
    candidate$control_group, treated_id,
    function(x) length(unique(x)))
  eligible_ids <- names(counts)[
    counts >= controls_per_treated &
      firm_counts[names(counts)] >= controls_per_treated]
  candidate <- candidate[
    as.character(treated_id) %in% eligible_ids, , drop = FALSE]
  if (!nrow(candidate)) {
    return(list(
      status = "no_diversified_candidates",
      selected_edges = candidate,
      matched_treated = treated[0, , drop = FALSE],
      diagnostics = data.frame()))
  }

  treated_id <- interaction(
    candidate$cohort, candidate$deal_id,
    candidate$treated_codinv, drop = TRUE, lex.order = TRUE)
  control_id <- interaction(
    candidate$cohort, candidate$control_codinv,
    candidate$control_group, drop = TRUE, lex.order = TRUE)
  treated_firm_id <- interaction(
    candidate$cohort, candidate$deal_id,
    candidate$treated_codinv, candidate$control_group,
    drop = TRUE, lex.order = TRUE)
  treated_levels <- levels(treated_id)
  control_levels <- levels(control_id)
  treated_firm_levels <- levels(treated_firm_id)
  n_edges <- nrow(candidate)
  n_treated <- length(treated_levels)
  n_controls <- length(control_levels)
  n_treated_firms <- length(treated_firm_levels)
  n_balance <- length(balance_variables)
  n_constraints <-
    n_treated + n_controls + n_treated_firms + 2L * n_balance
  n_variables <- n_edges + n_treated

  treated_lookup <- unique(candidate[
    c(treated_key, paste0(balance_variables, "_treated"))])
  treated_lookup$id <- interaction(
    treated_lookup$cohort, treated_lookup$deal_id,
    treated_lookup$treated_codinv, drop = TRUE, lex.order = TRUE)
  treated_lookup <- treated_lookup[
    match(treated_levels, as.character(treated_lookup$id)), ]

  scales <- vapply(balance_variables, function(variable) {
    values <- c(
      candidate[[paste0(variable, "_treated")]],
      candidate[[paste0(variable, "_control")]])
    scale <- stats::sd(values)
    if (is.finite(scale) && scale > 0) scale else 0
  }, numeric(1))

  model <- lpSolveAPI::make.lp(n_constraints, n_variables)
  lpSolveAPI::lp.control(model, sense = "max")

  treated_rows <- seq_len(n_treated)
  control_rows <- n_treated + seq_len(n_controls)
  firm_rows <- n_treated + n_controls + seq_len(n_treated_firms)
  upper_rows <- n_treated + n_controls + n_treated_firms +
    seq_len(n_balance)
  lower_rows <- n_treated + n_controls + n_treated_firms +
    n_balance + seq_len(n_balance)

  treated_index <- match(as.character(treated_id), treated_levels)
  control_index <- match(as.character(control_id), control_levels)
  firm_index <- match(
    as.character(treated_firm_id), treated_firm_levels)
  for (edge in seq_len(n_edges)) {
    control_values <- as.numeric(candidate[
      edge, paste0(balance_variables, "_control")])
    coefficients <- c(
      1, 1, 1,
      control_values / controls_per_treated,
      -control_values / controls_per_treated)
    lpSolveAPI::set.column(
      model, edge, as.numeric(coefficients),
      c(
        treated_rows[treated_index[[edge]]],
        control_rows[control_index[[edge]]],
        firm_rows[firm_index[[edge]]],
        upper_rows, lower_rows))
  }
  for (index in seq_len(n_treated)) {
    treated_values <- as.numeric(treated_lookup[
      index, paste0(balance_variables, "_treated")])
    coefficients <- c(
      -controls_per_treated,
      -(treated_values + maximum_balance_smd * scales),
      treated_values - maximum_balance_smd * scales)
    lpSolveAPI::set.column(
      model, n_edges + index, coefficients,
      c(treated_rows[[index]], upper_rows, lower_rows))
  }

  constraint_types <- c(
    rep("=", n_treated),
    rep("<=", n_controls + n_treated_firms + 2L * n_balance))
  rhs <- c(
    rep(0, n_treated),
    rep(maximum_control_reuse, n_controls),
    rep(1, n_treated_firms),
    rep(0, 2L * n_balance))
  lpSolveAPI::set.constr.type(
    model, constraint_types, seq_len(n_constraints))
  lpSolveAPI::set.rhs(model, rhs)
  lpSolveAPI::set.type(
    model, seq_len(n_variables), "binary")

  normalized_distance <- candidate$distance /
    max(1, max(candidate$distance))
  objective <- c(
    -LMV2_CARDINALITY$distance_tiebreak * normalized_distance,
    rep(1, n_treated))
  lpSolveAPI::set.objfn(model, objective)
  solve_status <- lpSolveAPI::solve.lpExtPtr(model)
  if (solve_status == 5L) {
    lpSolveAPI::set.objfn(
      model, c(rep(0, n_edges), rep(1, n_treated)))
    lpSolveAPI::lp.control(
      model,
      scaling = c("geometric", "equilibrate"),
      anti.degen = c(
        "numfailure", "lostfeas", "infeasible",
        "stalling", "fixedvars"),
      basis.crash = "leastdegenerate",
      epslevel = "medium")
    solve_status <- lpSolveAPI::solve.lpExtPtr(model)
  }
  if (solve_status != 0L) {
    return(list(
      status = paste0("solver_status_", solve_status),
      selected_edges = candidate[0, , drop = FALSE],
      matched_treated = treated[0, , drop = FALSE],
      diagnostics = data.frame(),
      n_candidate_treated = n_treated,
      n_matched_treated = 0L))
  }
  solution <- lpSolveAPI::get.variables(model)
  selected <- candidate[solution[seq_len(n_edges)] > 0.5, , drop = FALSE]
  matched_ids <- treated_levels[
    solution[n_edges + seq_len(n_treated)] > 0.5]
  matched <- treated[
    as.character(interaction(
      treated$cohort, treated$deal_id, treated$treated_codinv,
      drop = TRUE, lex.order = TRUE)) %in% matched_ids,
    , drop = FALSE]
  if (!nrow(selected)) {
    return(list(
      status = "no_balanced_recovery",
      selected_edges = selected,
      matched_treated = matched,
      diagnostics = data.frame(),
      n_candidate_treated = n_treated,
      n_matched_treated = 0L))
  }

  selected$control_weight <- 1 / controls_per_treated
  selected$treated_weight <- 1
  selected_treated_id <- interaction(
    selected$cohort, selected$deal_id,
    selected$treated_codinv, drop = TRUE, lex.order = TRUE)
  selected_control_id <- interaction(
    selected$cohort, selected$control_codinv,
    selected$control_group, drop = TRUE, lex.order = TRUE)
  if (any(table(selected_treated_id) != controls_per_treated) ||
      any(table(selected_control_id) > maximum_control_reuse) ||
      any(tapply(
        selected$control_group, selected_treated_id,
        function(x) length(unique(x))) < controls_per_treated)) {
    stop("Cardinality solution violates match or reuse constraints")
  }

  diagnostics <- do.call(rbind, lapply(
    balance_variables, function(variable) {
      treated_mean <- mean(
        selected[[paste0(variable, "_treated")]][
          !duplicated(selected_treated_id)])
      control_mean <- stats::weighted.mean(
        selected[[paste0(variable, "_control")]],
        selected$control_weight)
      scale <- scales[[variable]]
      smd <- if (scale > 0) {
        (control_mean - treated_mean) / scale
      } else if (isTRUE(all.equal(control_mean, treated_mean))) {
        0
      } else {
        Inf
      }
      data.frame(
        variable = variable, treated_mean = treated_mean,
        control_mean = control_mean, scale = scale, smd = smd,
        stringsAsFactors = FALSE)
    }))
  if (any(abs(diagnostics$smd) >
      maximum_balance_smd + 1e-6)) {
    stop("Cardinality solution violates the balance tolerance")
  }

  list(
    status = "optimal",
    selected_edges = selected,
    matched_treated = matched,
    diagnostics = diagnostics,
    n_candidate_treated = n_treated,
    n_matched_treated = nrow(matched),
    maximum_realized_reuse = max(table(selected_control_id)))
}

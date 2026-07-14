# ============================================================================
# 11j_build_robustness_weights.R -- Main DiD v1 robustness Phase 1
# ----------------------------------------------------------------------------
# Builds robustness weights and design diagnostics only. This script must not
# construct outcomes, open patent_enriched, or estimate treatment effects.
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))
source(file.path(BASE, "R", "11i_robustness_config.R"))
for (pkg in c("DBI", "duckdb", "WeightIt"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({library(DBI); library(duckdb); library(WeightIt)})
set.seed(SEED)

banner("MAIN DiD v1 ROBUSTNESS -- PHASE 1 DESIGN CHECKPOINT")

out_dir <- RESULTS_DIR
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

append_rows <- function(x, y) {
  if (is.null(x)) return(y)
  if (is.null(y)) return(x)
  alln <- union(names(x), names(y))
  for (nm in setdiff(alln, names(x))) x[[nm]] <- NA
  for (nm in setdiff(alln, names(y))) y[[nm]] <- NA
  rbind(x[, alln, drop = FALSE], y[, alln, drop = FALSE])
}

write_phase_csv <- function(df, path) {
  utils::write.csv(df, path, row.names = FALSE, na = "")
  invisible(path)
}

fail_integrity <- function(msg) stop("[INTEGRITY] ", msg, call. = FALSE)

unit_key <- function(df) paste(df$codinv, df$stack, df$treated, sep = "|")

assert_unique_unit_keys <- function(df, spec) {
  if (anyDuplicated(df[, c("codinv", "stack", "treated")]))
    fail_integrity(sprintf("%s has duplicate codinv x stack x treated unit keys.", spec))
}

assert_weights_finite <- function(w, spec) {
  if (any(!is.finite(w))) fail_integrity(sprintf("%s produced nonfinite weights.", spec))
}

as_factor_covars <- function(units) {
  units$qualifying_gap_cat <- droplevels(factor(pmin(units$qualifying_gap, 3L),
    levels = 0:3, labels = c("gap0", "gap1", "gap2", "gap3plus")))
  units$modal_family <- droplevels(factor(units$modal_family, levels = TECH_FAMILIES))
  units
}

prepare_units <- function(treated, control, firm_key_cols) {
  units <- rbind(treated, control)
  assert_unique_unit_keys(units, "prepared_units")
  units <- as_factor_covars(units)
  units$.cell <- do.call(paste, c(units[firm_key_cols], sep = "|"))
  cell_n <- table(units$.cell)
  units$n_qualifying_inventors <- as.integer(cell_n[units$.cell])
  miss <- rowSums(is.na(units[, c(FIRM_COVARS, INV_COVARS), drop = FALSE])) > 0
  if (any(miss)) {
    message("Dropping ", sum(miss), " units with missing design covariates.")
    units <- units[!miss, , drop = FALSE]
  }
  assert_unique_unit_keys(units, "prepared_units_after_missing_drop")
  units
}

compute_nt_inventor_covariates <- function(con, nt) {
  banner("Inventor covariates for never-target robustness units")
  stacks <- sort(unique(nt$stack))
  ic_list <- vector("list", length(stacks))
  for (i in seq_along(stacks)) {
    g <- stacks[i]
    keys <- unique(nt[nt$stack == g, c("codinv", "underlying_group_id")])
    keys <- data.frame(codinv = keys$codinv, g = g, grp = keys$underlying_group_id)
    t0 <- Sys.time()
    ic_list[[i]] <- compute_inventor_covariates(con, keys)
    message(sprintf("  stack %d: %d keys, %.1fs", g, nrow(keys),
                    as.numeric(Sys.time() - t0, units = "secs")))
  }
  ic_all <- do.call(rbind, ic_list)
  merge(nt, ic_all, by.x = c("codinv", "stack", "underlying_group_id"),
        by.y = c("codinv", "g", "grp"), all.x = TRUE)
}

load_treated_units <- function(con) {
  q <- sprintf("SELECT codinv, focal_deal_id, analysis_target_group_id AS underlying_group_id,
      stack, qualifying_gap, modal_family, %s
    FROM read_parquet('%s') WHERE treated = 1",
    paste(c(FIRM_COVARS, INV_COVARS), collapse = ", "), gsub("\\\\", "/", UNITS_PARQUET))
  treated <- dbGetQuery(con, q)
  treated$treated <- 1L
  treated$arm <- "treated"
  treated$real_control_deal_id <- NA_integer_
  treated$real_control_deal_year <- NA_integer_
  treated$underlying_group_id <- as.numeric(treated$underlying_group_id)
  treated$codinv <- as.numeric(treated$codinv)
  treated$stack <- as.integer(treated$stack)
  treated
}

load_never_target_units <- function(con) {
  nt <- dbGetQuery(con, sprintf("SELECT codinv, underlying_group_id, stack, qualifying_gap, %s,
      n_qualifying_inventors, ever_acquirer, acquirer_event_in_window
    FROM read_parquet('%s')",
    paste(FIRM_COVARS, collapse = ", "), gsub("\\\\", "/", NT_UNITS_PARQUET)))
  nt$codinv <- as.numeric(nt$codinv)
  nt$underlying_group_id <- as.numeric(nt$underlying_group_id)
  nt$stack <- as.integer(nt$stack)
  nt$treated <- 0L
  nt$arm <- "never_observed_target"
  nt$focal_deal_id <- NA_integer_
  nt$real_control_deal_id <- NA_integer_
  nt$real_control_deal_year <- NA_integer_
  nt
}

load_g7_units <- function(con) {
  q <- sprintf("SELECT codinv, focal_deal_id, future_control_deal_id, real_deal_year,
      analysis_target_group_id AS underlying_group_id, stack, arm, treated,
      qualifying_gap, qualifying_gap_cat, modal_family, %s
    FROM read_parquet('%s')",
    paste(c(FIRM_COVARS, INV_COVARS), collapse = ", "), gsub("\\\\", "/", UNITS_PARQUET))
  u <- dbGetQuery(con, q)
  u$codinv <- as.numeric(u$codinv)
  u$underlying_group_id <- as.numeric(u$underlying_group_id)
  u$stack <- as.integer(u$stack)
  u$treated <- as.integer(u$treated)
  u$real_control_deal_id <- ifelse(u$treated == 0L, as.integer(u$future_control_deal_id), NA_integer_)
  u$real_control_deal_year <- ifelse(u$treated == 0L, as.integer(u$real_deal_year), NA_integer_)
  u$future_control_deal_id <- NULL
  u$real_deal_year <- NULL
  u
}

acquirer_events_predeal <- function(con) {
  dbGetQuery(con, "
    SELECT DISTINCT CAST(id_group AS DOUBLE) AS underlying_group_id,
           CAST(deal_year AS INTEGER) AS deal_year
    FROM (
      SELECT acquirer_group AS id_group, deal_year
      FROM cassi_deal_spine WHERE acquirer_group IS NOT NULL
      UNION ALL
      SELECT acquirer_group_pre AS id_group, deal_year
      FROM cassi_deal_spine WHERE acquirer_group_pre IS NOT NULL
      UNION ALL
      SELECT fg.id_group AS id_group, s.deal_year
      FROM cassi_deal_spine s
      JOIN firm_group fg
        ON fg.compcod = s.acquirer_compcod
       AND fg.year = CAST(s.deal_year AS INTEGER) - 1
      WHERE s.acquirer_compcod IS NOT NULL
    )
    WHERE id_group IS NOT NULL AND deal_year IS NOT NULL")
}

drop_acquirer_clean_cells <- function(con, nt) {
  section("P2 acquirer-clean exclusion using pre-deal acquirer identity")
  ev <- acquirer_events_predeal(con)
  cells <- unique(nt[, c("underlying_group_id", "stack")])
  duckdb::duckdb_register(con, "robust_nt_cells", cells)
  duckdb::duckdb_register(con, "robust_acq_events", ev)
  on.exit({
    duckdb::duckdb_unregister(con, "robust_nt_cells")
    duckdb::duckdb_unregister(con, "robust_acq_events")
  }, add = TRUE)
  flagged <- dbGetQuery(con, "
    SELECT DISTINCT c.underlying_group_id, c.stack
    FROM robust_nt_cells c
    JOIN robust_acq_events e
      ON e.underlying_group_id = c.underlying_group_id
     AND e.deal_year BETWEEN c.stack - 1 AND c.stack + 5")
  key_flag <- paste(flagged$underlying_group_id, flagged$stack)
  key_nt <- paste(nt$underlying_group_id, nt$stack)
  nt$acquirer_clean_excluded_cell <- key_nt %in% key_flag
  message("P2 excluded control units: ", sum(nt$acquirer_clean_excluded_cell),
          " across firm-stack cells: ", nrow(flagged))
  nt[!nt$acquirer_clean_excluded_cell, , drop = FALSE]
}

validate_g7_clock <- function(con, g7) {
  ctl <- g7[g7$treated == 0L, , drop = FALSE]
  if (any(is.na(ctl$real_control_deal_id)))
    fail_integrity("g+7 controls have missing real_control_deal_id.")
  if (any((ctl$real_control_deal_year - ctl$stack) != CONTROL_LAG))
    fail_integrity("g+7 control clock violates real_control_deal_year - stack == 7.")
  if (any((ctl$stack + 5L) > (ctl$real_control_deal_year - 2L)))
    fail_integrity("g+7 panel end would enter the two-year pre-acquisition buffer.")
  per_unit <- aggregate(real_control_deal_id ~ codinv + stack, ctl,
                        function(x) length(unique(x)))
  if (any(per_unit$real_control_deal_id != 1L))
    fail_integrity("A g+7 control unit maps to more than one real_control_deal_id.")
  spine <- dbGetQuery(con, "
    SELECT CAST(deal_id AS INTEGER) AS real_control_deal_id,
           COUNT(DISTINCT CAST(deal_year AS INTEGER)) AS n_years,
           COUNT(DISTINCT CAST(target_group AS DOUBLE)) AS n_targets
    FROM cassi_deal_group_spine
    GROUP BY deal_id")
  m <- merge(unique(ctl[, c("real_control_deal_id"), drop = FALSE]), spine, by = "real_control_deal_id",
             all.x = TRUE)
  if (any(is.na(m$n_years)) || any(m$n_years != 1L) || any(m$n_targets != 1L))
    fail_integrity("A real_control_deal_id does not map to exactly one deal year and future target identity.")
  data.frame(check = c("real_control_deal_year_minus_stack", "panel_end_buffer",
                       "unit_maps_one_real_control_deal", "deal_maps_one_year_target"),
             pass = TRUE)
}

balance_table <- function(units, weights, spec, constrained_covars) {
  do.call(rbind, lapply(FULL_NUMERIC_COVARS, function(v) {
    data.frame(
      spec = spec,
      covariate = v,
      constrained = v %in% constrained_covars,
      smd_unweighted = smd_weighted(units[[v]], units$treated, rep(1, nrow(units))),
      smd_weighted = smd_weighted(units[[v]], units$treated, weights),
      stringsAsFactors = FALSE
    )
  }))
}

stack_mass_table <- function(units, weights, spec) {
  d <- data.frame(spec = spec, stack = units$stack, treated = units$treated,
                  final_weight = weights)
  ag <- aggregate(final_weight ~ spec + stack + treated, d, sum)
  wide <- reshape(ag, idvar = c("spec", "stack"), timevar = "treated", direction = "wide")
  names(wide) <- sub("final_weight\\.0", "control_mass", names(wide))
  names(wide) <- sub("final_weight\\.1", "treated_mass", names(wide))
  if (!"control_mass" %in% names(wide)) wide$control_mass <- 0
  if (!"treated_mass" %in% names(wide)) wide$treated_mass <- 0
  wide$relative_discrepancy <- abs(wide$control_mass - wide$treated_mass) / wide$treated_mass
  wide
}

concentration_table <- function(units, weights, spec, p4 = FALSE) {
  ctl <- units$treated == 0L
  out <- NULL
  add_level <- function(level, id) {
    mass <- tapply(weights[ctl], id[ctl], sum)
    data.frame(
      spec = spec, level = level,
      n_entities = length(mass),
      ess = ess(as.numeric(mass)),
      max_share = max(mass) / sum(mass),
      top5_share = sum(head(sort(mass, decreasing = TRUE), 5)) / sum(mass),
      stringsAsFactors = FALSE
    )
  }
  out <- append_rows(out, add_level("underlying_control_firm", units$underlying_group_id))
  if (p4) out <- append_rows(out, add_level("future_control_deal", units$real_control_deal_id))
  out
}

quantile_table <- function(units, weights, spec) {
  q <- weight_quantile_diag(weights[units$treated == 0L])
  cbind(spec = spec, arm = "control", q)
}

diagnose_fit <- function(spec, units, weights, fit, constrained_covars, p4 = FALSE) {
  assert_weights_finite(weights, spec)
  firm_mass <- fit$firm_data$firm_stage_mass
  if (is.null(firm_mass))
    firm_mass <- fit$firm_data$n_qualifying_inventors * fit$firm_data$firm_multiplier
  firm_md <- ebal_max_meandiff(model_matrix_cols(fit$firm_form, fit$firm_data),
                               fit$firm_data$treated, firm_mass)
  inv_md <- ebal_max_meandiff(model_matrix_cols(fit$inv_form, units), units$treated, weights)
  bal <- balance_table(units, weights, spec, constrained_covars)
  conc <- concentration_table(units, weights, spec, p4 = p4)
  sm <- stack_mass_table(units, weights, spec)
  omitted_smd <- abs(bal$smd_weighted[!bal$constrained])
  omitted_smd <- omitted_smd[is.finite(omitted_smd)]
  list(
    balance = bal,
    concentration = conc,
    stack_mass = sm,
    quantiles = quantile_table(units, weights, spec),
    metrics = data.frame(
      spec = spec,
      firm_converged = firm_md <= EBAL_CONSTRAINT_TOL,
      inv_converged = inv_md <= EBAL_CONSTRAINT_TOL,
      firm_meandiff = firm_md,
      inv_meandiff = inv_md,
      max_smd_constrained = max(abs(bal$smd_weighted[bal$constrained]), na.rm = TRUE),
      max_smd_omitted = if (length(omitted_smd)) max(omitted_smd) else NA_real_,
      max_smd_all = max(abs(bal$smd_weighted), na.rm = TRUE),
      no_empty_stack = all(sort(unique(units$stack[units$treated == 1L])) %in%
                             sort(unique(units$stack[units$treated == 0L]))),
      max_stack_mass_discrepancy = max(sm$relative_discrepancy, na.rm = TRUE),
      n_treated = sum(units$treated == 1L),
      n_control = sum(units$treated == 0L),
      n_units = nrow(units),
      stringsAsFactors = FALSE
    )
  )
}

feasibility_row <- function(spec, status, metrics, reasons) {
  data.frame(spec = spec, status = status,
             feasible = identical(status, "FEASIBLE"),
             reason = paste(reasons, collapse = "; "),
             metrics, stringsAsFactors = FALSE)
}

evaluate_common_gates <- function(spec, metrics, conc, treated_ok, p2 = FALSE) {
  reasons <- character(0)
  firm_conc <- conc[conc$level == "underlying_control_firm", ]
  if (!isTRUE(metrics$firm_converged)) reasons <- c(reasons, "firm stage did not converge")
  if (!isTRUE(metrics$inv_converged)) reasons <- c(reasons, "inventor stage did not converge")
  if (p2) {
    if (metrics$max_smd_all > ROBUST_MAX_SMD_CONSTRAINED)
      reasons <- c(reasons, sprintf("full covariate max |SMD| %.4f > %.2f",
                                    metrics$max_smd_all, ROBUST_MAX_SMD_CONSTRAINED))
  } else {
    if (metrics$max_smd_constrained > ROBUST_MAX_SMD_CONSTRAINED)
      reasons <- c(reasons, sprintf("constrained max |SMD| %.4f > %.2f",
                                    metrics$max_smd_constrained, ROBUST_MAX_SMD_CONSTRAINED))
    if (metrics$max_smd_omitted > ROBUST_MAX_SMD_OMITTED)
      reasons <- c(reasons, sprintf("omitted max |SMD| %.4f > %.2f",
                                    metrics$max_smd_omitted, ROBUST_MAX_SMD_OMITTED))
  }
  if (firm_conc$ess < ROBUST_MIN_ESS)
    reasons <- c(reasons, sprintf("underlying-firm ESS %.1f < %d", firm_conc$ess, ROBUST_MIN_ESS))
  if (firm_conc$max_share > ROBUST_MAX_SHARE)
    reasons <- c(reasons, sprintf("max underlying-firm share %.3f > %.2f",
                                  firm_conc$max_share, ROBUST_MAX_SHARE))
  if (!isTRUE(metrics$no_empty_stack)) reasons <- c(reasons, "empty control stack")
  if (metrics$max_stack_mass_discrepancy > STACK_MASS_TOL)
    reasons <- c(reasons, sprintf("stack mass discrepancy %.2e > %.1e",
                                  metrics$max_stack_mass_discrepancy, STACK_MASS_TOL))
  if (!treated_ok) reasons <- c(reasons, "treated weights not exactly one")
  if (length(reasons) == 0) "FEASIBLE" else reasons
}

run_inventor_weighted <- function(spec, units, firm_key_cols, firm_covars, inv_covars,
                                  constrained_covars, out_parquet, p2 = FALSE) {
  section(paste(spec, "two-stage inventor-weighted ebal"))
  fit <- tryCatch(
    two_stage_ebal(units, firm_key_cols, firm_covars, inv_covars, INV_FACTOR_COVARS,
                   cont_covars = FULL_CONT_COVARS, maxit = 30000),
    error = function(e) e
  )
  if (inherits(fit, "error")) {
    return(list(status = "INFEASIBLE", reason = conditionMessage(fit)))
  }
  u <- fit$units
  w <- u$final_weight
  assert_weights_finite(w, spec)
  if (any(w <= 0)) {
    return(list(status = "INFEASIBLE",
      reason = sprintf("%d finite but nonpositive weights", sum(w <= 0)),
      units = u, weights = w, diagnostics = NULL))
  }
  treated_ok <- max(abs(w[u$treated == 1L] - 1)) < 1e-8
  if (!treated_ok) fail_integrity(sprintf("%s treated weights are not exactly one.", spec))
  diag <- diagnose_fit(spec, u, w, fit, constrained_covars)
  gate <- evaluate_common_gates(spec, diag$metrics, diag$concentration, treated_ok, p2 = p2)
  status <- if (identical(gate, "FEASIBLE")) "FEASIBLE" else "INFEASIBLE"
  if (status == "FEASIBLE") {
    out <- u[, c("codinv", "underlying_group_id", "stack", "treated", "final_weight",
                 "n_qualifying_inventors")]
    if ("focal_deal_id" %in% names(u)) out$focal_deal_id <- u$focal_deal_id
    if ("real_control_deal_id" %in% names(u)) out$real_control_deal_id <- u$real_control_deal_id
    duckdb::duckdb_register(con, paste0("out_", spec), out)
    dbExecute(con, sprintf("COPY (SELECT * FROM out_%s) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
                           spec, gsub("\\\\", "/", out_parquet)))
    duckdb::duckdb_unregister(con, paste0("out_", spec))
  }
  list(status = status, reason = if (status == "FEASIBLE") "all gates passed" else paste(gate, collapse = "; "),
       units = u, weights = w, diagnostics = diag)
}

two_stage_deal_ebal <- function(units, firm_key_cols, firm_covars, inv_covars, inv_factors,
                                cont_covars, maxit = 30000) {
  zc <- intersect(cont_covars, c(firm_covars, inv_covars))
  for (v in zc) units[[v]] <- standardize_continuous(units[[v]])
  units$.fk <- do.call(paste, c(units[firm_key_cols], sep = "|"))
  firm_data <- unique(units[, c(".fk", firm_key_cols, "treated", "stack", firm_covars,
                                "n_qualifying_inventors")])
  stopifnot(!anyDuplicated(firm_data$.fk))
  cell_base <- aggregate(treated_base_weight_id ~ .fk, units, sum)
  names(cell_base)[2] <- "treated_base_cell_mass"
  firm_data <- merge(firm_data, cell_base, by = ".fk", all.x = TRUE)
  firm_data$firm_stage_s_weight <- ifelse(firm_data$treated == 1L,
                                          firm_data$treated_base_cell_mass,
                                          firm_data$n_qualifying_inventors)
  firm_form <- stats::reformulate(c(firm_covars, "factor(stack)"), response = "treated")
  W_firm <- WeightIt::weightit(firm_form, data = firm_data, method = "ebal", estimand = "ATT",
                               s.weights = firm_data$firm_stage_s_weight, maxit = maxit)
  firm_data$firm_multiplier <- as.numeric(W_firm$weights)
  firm_data$firm_stage_mass <- firm_data$firm_stage_s_weight * firm_data$firm_multiplier
  units$firm_multiplier <- firm_data$firm_multiplier[match(units$.fk, firm_data$.fk)]
  units$analysis_s_weight <- ifelse(units$treated == 1L, units$treated_base_weight_id, 1)
  units$inventor_base_weight <- ifelse(units$treated == 1L, 1, units$firm_multiplier)
  inv_form <- stats::reformulate(c(firm_covars, inv_covars, inv_factors, "factor(stack)"),
                                 response = "treated")
  W_inv <- WeightIt::weightit(inv_form, data = units, method = "ebal", estimand = "ATT",
                              s.weights = units$analysis_s_weight,
                              base.weights = units$inventor_base_weight, maxit = maxit)
  units$weightit_weight <- as.numeric(W_inv$weights)
  units$final_weight <- units$analysis_s_weight * units$weightit_weight
  list(units = units, firm_data = firm_data, W_firm = W_firm, W_inv = W_inv,
       firm_form = firm_form, inv_form = inv_form)
}

p4_selftest <- function() {
  set.seed(7)
  treated <- rbind(
    data.frame(deal = 1L, treated = 1L, n = 2L, x = 0, z = c(0, 1)),
    data.frame(deal = 2L, treated = 1L, n = 5L, x = 1, z = c(0, 0, 1, 1, 1))
  )
  control <- rbind(
    data.frame(deal = 3L, treated = 0L, n = 2L, x = 0, z = c(0, 1)),
    data.frame(deal = 4L, treated = 0L, n = 4L, x = 0, z = c(0, 1, 0, 1)),
    data.frame(deal = 5L, treated = 0L, n = 5L, x = 1, z = c(0, 0, 1, 1, 1)),
    data.frame(deal = 6L, treated = 0L, n = 3L, x = 1, z = c(0, 1, 1))
  )
  d <- rbind(treated, control)
  d$codinv <- seq_len(nrow(d))
  d$stack <- 2000L
  d$focal_deal_id <- d$deal
  d$underlying_group_id <- d$deal
  d$arm <- ifelse(d$treated == 1L, "treated", "control")
  d$qualifying_gap <- 1L
  d$modal_family <- factor("other", levels = TECH_FAMILIES)
  d$qualifying_gap_cat <- factor("gap1", levels = c("gap0", "gap1", "gap2", "gap3plus"))
  d$n_qualifying_inventors <- d$n
  nt <- sum(d$treated == 1L)
  deal_n <- table(d$focal_deal_id[d$treated == 1L])
  D <- length(deal_n)
  d$treated_base_weight_id <- ifelse(d$treated == 1L,
    nt / (D * as.numeric(deal_n[as.character(d$focal_deal_id)])), 1)
  fit <- two_stage_deal_ebal(d, c("focal_deal_id", "underlying_group_id", "stack", "arm"),
                             firm_covars = "x", inv_covars = "z", inv_factors = character(0),
                             cont_covars = character(0), maxit = 10000)
  u <- fit$units
  deal_mass <- tapply(u$final_weight[u$treated == 1L], u$focal_deal_id[u$treated == 1L], sum)
  mt <- weighted.mean(u$x[u$treated == 1L], u$final_weight[u$treated == 1L])
  mc <- weighted.mean(u$x[u$treated == 0L], u$final_weight[u$treated == 0L])
  treated_not_one <- any(abs(u$final_weight[u$treated == 1L] - 1) > 1e-8)
  control_mass <- tapply(u$final_weight[u$treated == 0L], u$focal_deal_id[u$treated == 0L], sum)
  ratio_4_to_3 <- as.numeric(control_mass["4"] / control_mass["3"])
  lm1 <- coef(stats::lm(z ~ treated, data = u, weights = final_weight))[["treated"]]
  lm2 <- coef(stats::lm(z ~ treated, data = u, weights = 11 * final_weight))[["treated"]]
  data.frame(
    check = c("unequal_deals_equal_mass", "firm_size_enters_once",
              "controls_match_deal_weighted_moments", "treated_not_reset_to_one",
              "global_rescaling_invariant"),
    pass = c(max(abs(deal_mass - nt / D)) < 1e-8,
             abs(ratio_4_to_3 - 2) < 0.10,
             abs(mt - mc) < 1e-5,
             treated_not_one,
             abs(lm1 - lm2) < 1e-12),
    detail = c(sprintf("deal masses: %s", paste(round(deal_mass, 8), collapse = ", ")),
               sprintf("identical-control mass ratio=%.3f", ratio_4_to_3),
               sprintf("treated x=%.6f control x=%.6f", mt, mc),
               sprintf("treated weight range %.4f..%.4f",
                       min(u$final_weight[u$treated == 1L]), max(u$final_weight[u$treated == 1L])),
               sprintf("coef %.12f vs %.12f", lm1, lm2))
  )
}

run_deal_weighted_p4 <- function(units) {
  spec <- "P4"
  section("P4 proper deal-weighted two-stage ebal")
  treated <- units$treated == 1L
  deal_n <- table(units$focal_deal_id[treated])
  N_T <- sum(treated)
  D <- length(deal_n)
  units$treated_base_weight_id <- ifelse(treated,
    N_T / (D * as.numeric(deal_n[as.character(units$focal_deal_id)])), 1)
  target_mass <- N_T / D
  pre_mass <- tapply(units$treated_base_weight_id[treated], units$focal_deal_id[treated], sum)
  if (max(abs(pre_mass - target_mass) / target_mass) > P4_DEAL_MASS_TOL)
    fail_integrity("P4 treated_base_weight_id does not give equal treated deal totals.")
  fit <- tryCatch(
    two_stage_deal_ebal(units, c("focal_deal_id", "underlying_group_id", "stack", "arm"),
                        FIRM_COVARS, INV_COVARS, INV_FACTOR_COVARS, FULL_CONT_COVARS),
    error = function(e) e
  )
  if (inherits(fit, "error")) {
    return(list(status = "INFEASIBLE", reason = conditionMessage(fit)))
  }
  u <- fit$units
  w <- u$final_weight
  assert_weights_finite(w, spec)
  if (any(w <= 0)) {
    return(list(status = "INFEASIBLE",
      reason = sprintf("%d finite but nonpositive weights", sum(w <= 0)),
      units = u, weights = w, diagnostics = NULL))
  }
  if (max(abs(w[u$treated == 1L] - u$treated_base_weight_id[u$treated == 1L])) > 1e-8)
    fail_integrity("P4 treated weights changed after weighting stages.")
  post_mass <- tapply(w[u$treated == 1L], u$focal_deal_id[u$treated == 1L], sum)
  deal_equal <- max(abs(post_mass - target_mass) / target_mass) <= P4_DEAL_MASS_TOL
  if (!deal_equal) fail_integrity("P4 treated deal-total equality failed after weighting.")
  diag <- diagnose_fit(spec, u, w, fit, FULL_NUMERIC_COVARS, p4 = TRUE)
  conc_deal <- diag$concentration[diag$concentration$level == "future_control_deal", ]
  conc_firm <- diag$concentration[diag$concentration$level == "underlying_control_firm", ]
  reasons <- character(0)
  if (!isTRUE(diag$metrics$firm_converged)) reasons <- c(reasons, "firm stage did not converge")
  if (!isTRUE(diag$metrics$inv_converged)) reasons <- c(reasons, "inventor stage did not converge")
  if (diag$metrics$max_smd_constrained > ROBUST_MAX_SMD_CONSTRAINED)
    reasons <- c(reasons, sprintf("constrained max |SMD| %.4f > %.2f",
                                  diag$metrics$max_smd_constrained, ROBUST_MAX_SMD_CONSTRAINED))
  if (diag$metrics$max_smd_all > ROBUST_MAX_SMD_OMITTED)
    reasons <- c(reasons, sprintf("all original max |SMD| %.4f > %.2f",
                                  diag$metrics$max_smd_all, ROBUST_MAX_SMD_OMITTED))
  if (conc_deal$ess < ROBUST_MIN_ESS) reasons <- c(reasons, "future-control-deal ESS below 50")
  if (conc_firm$ess < ROBUST_MIN_ESS) reasons <- c(reasons, "underlying-control-firm ESS below 50")
  if (conc_deal$max_share > ROBUST_MAX_SHARE) reasons <- c(reasons, "future-control-deal max share above 10%")
  if (conc_firm$max_share > ROBUST_MAX_SHARE) reasons <- c(reasons, "underlying-control-firm max share above 10%")
  if (!isTRUE(diag$metrics$no_empty_stack)) reasons <- c(reasons, "empty control stack")
  if (diag$metrics$max_stack_mass_discrepancy > STACK_MASS_TOL) reasons <- c(reasons, "stack mass discrepancy above 1e-4")
  if (!deal_equal) reasons <- c(reasons, "treated deal-total equality failed")
  status <- if (length(reasons) == 0) "FEASIBLE" else "INFEASIBLE"
  if (status == "FEASIBLE") {
    out <- u[, c("codinv", "underlying_group_id", "stack", "treated", "final_weight",
                 "n_qualifying_inventors", "focal_deal_id", "real_control_deal_id",
                 "treated_base_weight_id")]
    duckdb::duckdb_register(con, "out_P4", out)
    dbExecute(con, sprintf("COPY (SELECT * FROM out_P4) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
                           gsub("\\\\", "/", P4_WEIGHTS_PARQUET)))
    duckdb::duckdb_unregister(con, "out_P4")
  }
  list(status = status, reason = if (status == "FEASIBLE") "all gates passed" else paste(reasons, collapse = "; "),
       units = u, weights = w, diagnostics = diag)
}

write_checkpoint_note <- function(design, feasibility, concentration, stack_mass, balance,
                                  unit_diff, p4_selftest_rows, g7_checks) {
  fmt <- function(x, digits = 3) ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "fg"))
  lines <- c(
    "# Main DiD v1 Robustness Design Checkpoint",
    "",
    sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    "",
    "## Scope",
    "",
    "This checkpoint implements Phase 1 only: robustness weights, balance diagnostics, feasibility decisions, and design notes. It does not build outcomes, open `patent_enriched`, run citation checks, or estimate treatment effects.",
    "",
    "P0 remains frozen at commit `99923f8`; Phase 1 never overwrites its weights, panel, estimates, or figures.",
    "",
    "## Specifications",
    "",
    paste(sprintf("- `%s`: %s.", ROBUSTNESS_SPECS$spec, ROBUSTNESS_SPECS$label), collapse = "\n"),
    "",
    "Reduced 4x4 covariates are firm `log_firm_inventor_count`, `log_patents_recent`, `share_small_molecule`, `share_biotech`; inventor `log_inventor_patent_stock`, `observed_inventor_career_age`, `observed_target_patent_tenure`, `target_exclusivity`.",
    "",
    "## Feasibility Decisions",
    ""
  )
  for (i in seq_len(nrow(feasibility))) {
    lines <- c(lines, sprintf("- `%s`: **%s**. %s", feasibility$spec[i],
                              feasibility$status[i], feasibility$reason[i]))
  }
  lines <- c(lines, "", "## Key Diagnostics", "")
  for (i in seq_len(nrow(design))) {
    lines <- c(lines, sprintf(
      "- `%s`: constrained max |SMD| %s; omitted/all max |SMD| %s; max stack-mass discrepancy %s; treated N %s; control N %s.",
      design$spec[i], fmt(design$max_smd_constrained[i]), fmt(design$max_smd_omitted[i]),
      fmt(design$max_stack_mass_discrepancy[i], 4), design$n_treated[i], design$n_control[i]))
  }
  lines <- c(lines, "", "## Control Concentration", "")
  for (i in seq_len(nrow(concentration))) {
    note <- ""
    if ("note" %in% names(concentration) && !is.na(concentration$note[i]) &&
        nzchar(concentration$note[i])) {
      note <- sprintf(" Not valid: %s.", concentration$note[i])
    }
    lines <- c(lines, sprintf("- `%s` %s: ESS %s; max share %s; top-five share %s.%s",
      concentration$spec[i], concentration$level[i], fmt(concentration$ess[i]),
      fmt(concentration$max_share[i]), fmt(concentration$top5_share[i]), note))
  }
  lines <- c(lines, "", "## Unit Comparisons", "")
  for (i in seq_len(nrow(unit_diff))) {
    lines <- c(lines, sprintf("- `%s` vs P0: shared units %s; only in spec %s; only in P0 %s.",
                              unit_diff$spec[i], unit_diff$shared_units[i],
                              unit_diff$only_in_spec[i], unit_diff$only_in_p0[i]))
  }
  lines <- c(lines, "", "## P4 Contract Self-Test", "")
  for (i in seq_len(nrow(p4_selftest_rows))) {
    lines <- c(lines, sprintf("- %s: %s (%s).", p4_selftest_rows$check[i],
                              ifelse(p4_selftest_rows$pass[i], "pass", "fail"),
                              p4_selftest_rows$detail[i]))
  }
  lines <- c(lines, "", "## g+7 Identity Checks", "")
  for (i in seq_len(nrow(g7_checks))) {
    lines <- c(lines, sprintf("- %s: pass.", g7_checks$check[i]))
  }
  lines <- c(lines, "", "## Mandatory Phase 2 Safeguards", "",
    "- Check duplicate `patent_enriched` rows for conflicting non-missing `fwd_cits5` values.",
    "- Verify the citation follow-up cutoff without treating the database maximum patent year as full certification.",
    "- Audit citation missingness and missing citation mass among patent-active rows by treatment status.",
    "- Recompute all original balance diagnostics on the restricted citation sample for each feasible specification.",
    "- Keep citation results provisional when raw citing-year histories remain unavailable.",
    "")
  writeLines(lines, ROBUSTNESS_NOTE, useBytes = TRUE)
}

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='10GB'")
dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", gsub("\\\\", "/", DUCKDB_TMP)))

design <- NULL
balance_all <- NULL
concentration_all <- NULL
stack_mass_all <- NULL
quantiles_all <- NULL
feasibility <- NULL
unit_diff <- NULL

banner("P4 synthetic self-test")
p4_st <- p4_selftest()
print(p4_st)
if (!all(p4_st$pass)) fail_integrity("P4 synthetic self-test failed.")

banner("Load primary units and P0 frozen roster")
treated <- load_treated_units(con)
p0 <- dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", gsub("\\\\", "/", P0_WEIGHTS_PARQUET)))
p0$codinv <- as.numeric(p0$codinv); p0$stack <- as.integer(p0$stack); p0$treated <- as.integer(p0$treated)
assert_unique_unit_keys(p0, "P0 frozen weights")
p0_key <- unit_key(p0)

p0_conc <- concentration_table(transform(p0, real_control_deal_id = NA_integer_), p0$final_weight, "P0")
p0_sm <- stack_mass_table(p0, p0$final_weight, "P0")
p0_bal_path <- file.path(AUDIT_DIR, "never_target_stage2_balance.csv")
p0_diag_path <- file.path(AUDIT_DIR, "never_target_stage2_diagnostics.csv")
p0_bal <- if (file.exists(p0_bal_path)) utils::read.csv(p0_bal_path, stringsAsFactors = FALSE) else data.frame()
p0_diag <- if (file.exists(p0_diag_path)) utils::read.csv(p0_diag_path, stringsAsFactors = FALSE) else data.frame()
if (nrow(p0_bal)) {
  p0_bal_out <- data.frame(spec = "P0", covariate = p0_bal$covariate,
    constrained = TRUE, smd_unweighted = p0_bal$smd_unweighted,
    smd_weighted = p0_bal$smd_final)
  balance_all <- append_rows(balance_all, p0_bal_out)
}
if (nrow(p0_diag)) {
  p0_metrics <- data.frame(spec = "P0",
    firm_converged = p0_diag$firm_converged[1], inv_converged = p0_diag$inv_converged[1],
    firm_meandiff = p0_diag$firm_meandiff[1], inv_meandiff = p0_diag$inv_meandiff[1],
    max_smd_constrained = p0_diag$max_smd_post[1], max_smd_omitted = NA_real_,
    max_smd_all = p0_diag$max_smd_post[1], no_empty_stack = TRUE,
    max_stack_mass_discrepancy = max(p0_sm$relative_discrepancy, na.rm = TRUE),
    n_treated = sum(p0$treated == 1L), n_control = sum(p0$treated == 0L), n_units = nrow(p0))
  design <- append_rows(design, p0_metrics)
  feasibility <- append_rows(feasibility, feasibility_row("P0", "FROZEN_PRIMARY", p0_metrics,
    "frozen primary benchmark; not reweighted"))
}
concentration_all <- append_rows(concentration_all, p0_conc)
stack_mass_all <- append_rows(stack_mass_all, p0_sm)
quantiles_all <- append_rows(quantiles_all, quantile_table(p0, p0$final_weight, "P0"))

banner("Load never-target donor roster and attach inventor covariates once")
nt_base <- load_never_target_units(con)
nt_cov <- compute_nt_inventor_covariates(con, nt_base)
nt_cov$modal_family[is.na(nt_cov$modal_family)] <- "other"

run_and_collect <- function(spec, res) {
  if (is.null(res$diagnostics)) {
    row <- data.frame(spec = spec, firm_converged = FALSE, inv_converged = FALSE,
      firm_meandiff = NA_real_, inv_meandiff = NA_real_, max_smd_constrained = NA_real_,
      max_smd_omitted = NA_real_, max_smd_all = NA_real_, no_empty_stack = NA,
      max_stack_mass_discrepancy = NA_real_,
      n_treated = if (!is.null(res$units)) sum(res$units$treated == 1L) else NA_integer_,
      n_control = if (!is.null(res$units)) sum(res$units$treated == 0L) else NA_integer_,
      n_units = if (!is.null(res$units)) nrow(res$units) else NA_integer_)
    design <<- append_rows(design, row)
    feasibility <<- append_rows(feasibility, feasibility_row(spec, "INFEASIBLE", row, res$reason))
    if (!is.null(res$units)) {
      k <- unit_key(res$units)
      unit_diff <<- append_rows(unit_diff, data.frame(spec = spec,
        shared_units = length(intersect(k, p0_key)),
        only_in_spec = length(setdiff(k, p0_key)),
        only_in_p0 = length(setdiff(p0_key, k))))
      concentration_all <<- append_rows(concentration_all, data.frame(
        spec = spec,
        level = "underlying_control_firm",
        n_entities = length(unique(res$units$underlying_group_id[res$units$treated == 0L])),
        ess = NA_real_,
        max_share = NA_real_,
        top5_share = NA_real_,
        note = res$reason,
        stringsAsFactors = FALSE))
    }
    return(invisible(NULL))
  }
  d <- res$diagnostics
  design <<- append_rows(design, d$metrics)
  balance_all <<- append_rows(balance_all, d$balance)
  concentration_all <<- append_rows(concentration_all, d$concentration)
  stack_mass_all <<- append_rows(stack_mass_all, d$stack_mass)
  quantiles_all <<- append_rows(quantiles_all, d$quantiles)
  feasibility <<- append_rows(feasibility, feasibility_row(spec, res$status, d$metrics, res$reason))
  k <- unit_key(res$units)
  unit_diff <<- append_rows(unit_diff, data.frame(spec = spec,
    shared_units = length(intersect(k, p0_key)),
    only_in_spec = length(setdiff(k, p0_key)),
    only_in_p0 = length(setdiff(p0_key, k))))
  invisible(NULL)
}

banner("P1 never-target reduced 4x4")
p1_control <- nt_cov
p1 <- prepare_units(treated[, c("codinv", "focal_deal_id", "underlying_group_id", "stack",
  "treated", "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
  "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  p1_control[, c("codinv", "focal_deal_id", "underlying_group_id", "stack",
    "treated", "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
    "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  c("underlying_group_id", "stack"))
p1 <- p1[unit_key(p1) %in% p0_key, , drop = FALSE]
if (length(setdiff(p0_key, unit_key(p1))) > 0L || length(setdiff(unit_key(p1), p0_key)) > 0L)
  fail_integrity("P1 cannot be aligned exactly to P0 units.")
res_p1 <- run_inventor_weighted("P1", p1, c("underlying_group_id", "stack"),
  FIRM_COVARS_REDUCED, INVENTOR_COVARS_REDUCED,
  constrained_covars = c(FIRM_COVARS_REDUCED, INVENTOR_COVARS_REDUCED),
  out_parquet = P1_WEIGHTS_PARQUET)
run_and_collect("P1", res_p1)

banner("P2 never-target acquirer-clean full covariates")
p2_control <- drop_acquirer_clean_cells(con, nt_cov)
p2 <- prepare_units(treated[, c("codinv", "focal_deal_id", "underlying_group_id", "stack",
  "treated", "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
  "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  p2_control[, c("codinv", "focal_deal_id", "underlying_group_id", "stack",
    "treated", "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
    "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  c("underlying_group_id", "stack"))
res_p2 <- run_inventor_weighted("P2", p2, c("underlying_group_id", "stack"),
  FIRM_COVARS, INV_COVARS, constrained_covars = FULL_NUMERIC_COVARS,
  out_parquet = P2_WEIGHTS_PARQUET, p2 = TRUE)
run_and_collect("P2", res_p2)

banner("P3/P4 g+7 design and clock checks")
g7 <- load_g7_units(con)
g7_checks <- validate_g7_clock(con, g7)
g7 <- prepare_units(g7[g7$treated == 1L, c("codinv", "focal_deal_id", "underlying_group_id",
  "stack", "treated", "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
  "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  g7[g7$treated == 0L, c("codinv", "focal_deal_id", "underlying_group_id",
    "stack", "treated", "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
    "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  c("focal_deal_id", "underlying_group_id", "stack", "arm"))

banner("P3 g+7 reduced 4x4 inventor-weighted")
res_p3 <- run_inventor_weighted("P3", g7, c("focal_deal_id", "underlying_group_id", "stack", "arm"),
  FIRM_COVARS_REDUCED, INVENTOR_COVARS_REDUCED,
  constrained_covars = c(FIRM_COVARS_REDUCED, INVENTOR_COVARS_REDUCED),
  out_parquet = P3_WEIGHTS_PARQUET)
run_and_collect("P3", res_p3)

banner("P4 g+7 proper deal-weighted")
res_p4 <- run_deal_weighted_p4(g7)
run_and_collect("P4", res_p4)

banner("Writing Phase 1 diagnostics and checkpoint note")
write_phase_csv(design, ROBUSTNESS_DESIGN_COMPARISON)
write_phase_csv(balance_all, ROBUSTNESS_BALANCE_ALL)
write_phase_csv(concentration_all, ROBUSTNESS_CONCENTRATION)
write_phase_csv(stack_mass_all, ROBUSTNESS_STACK_MASS)
write_phase_csv(quantiles_all, ROBUSTNESS_QUANTILES)
write_phase_csv(feasibility, ROBUSTNESS_FEASIBILITY)
write_checkpoint_note(design, feasibility, concentration_all, stack_mass_all, balance_all,
                      unit_diff, p4_st, g7_checks)

options(width = 220)
print(feasibility[, c("spec", "status", "reason")])
banner("11j Phase 1 DONE -- stop before outcome estimation")

# ============================================================================
# 11j_build_robustness_weights.R -- Main DiD v1 robustness Phase 1C
# ----------------------------------------------------------------------------
# Design-only checkpoint. Builds repaired robustness rosters/weights and writes
# diagnostics. Does not construct outcomes, open patent_enriched, run citation
# checks, or estimate treatment effects.
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))
source(file.path(BASE, "R", "11i_robustness_config.R"))
for (pkg in c("DBI", "duckdb", "WeightIt"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({ library(DBI); library(duckdb); library(WeightIt) })
set.seed(SEED)

banner("MAIN DiD v1 ROBUSTNESS -- PHASE 1C DESIGN REPAIR")

sql_path <- function(path) gsub("\\\\", "/", path)

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
cell_key <- function(df) paste(df$underlying_group_id, df$stack, sep = "|")

assert_unique_unit_keys <- function(df, spec) {
  if (anyDuplicated(df[, c("codinv", "stack", "treated")]))
    fail_integrity(sprintf("%s has duplicate codinv x stack x treated keys.", spec))
}

assert_finite_weights <- function(w, spec) {
  if (any(!is.finite(w))) fail_integrity(sprintf("%s produced nonfinite weights.", spec))
}

save_weights <- function(con, df, path, view = "weights_out") {
  duckdb::duckdb_register(con, view, df)
  on.exit(duckdb::duckdb_unregister(con, view), add = TRUE)
  dbExecute(con, sprintf(
    "COPY (SELECT * FROM %s) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
    view, sql_path(path)))
  invisible(path)
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

load_treated_units <- function(con) {
  q <- sprintf("SELECT codinv, focal_deal_id, analysis_target_group_id AS underlying_group_id,
      stack, qualifying_gap, modal_family, %s
    FROM read_parquet('%s') WHERE treated = 1",
    paste(c(FIRM_COVARS, INV_COVARS), collapse = ", "), sql_path(UNITS_PARQUET))
  treated <- dbGetQuery(con, q)
  treated$treated <- 1L
  treated$arm <- "treated"
  treated$real_control_deal_id <- NA_integer_
  treated$real_control_deal_year <- NA_integer_
  treated$codinv <- as.numeric(treated$codinv)
  treated$underlying_group_id <- as.numeric(treated$underlying_group_id)
  treated$stack <- as.integer(treated$stack)
  treated
}

load_never_target_units <- function(con) {
  nt <- dbGetQuery(con, sprintf("SELECT codinv, underlying_group_id, stack, qualifying_gap, %s,
      n_qualifying_inventors, ever_acquirer, acquirer_event_in_window
    FROM read_parquet('%s')",
    paste(FIRM_COVARS, collapse = ", "), sql_path(NT_UNITS_PARQUET)))
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
    paste(c(FIRM_COVARS, INV_COVARS), collapse = ", "), sql_path(UNITS_PARQUET))
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
  out <- merge(nt, ic_all, by.x = c("codinv", "stack", "underlying_group_id"),
               by.y = c("codinv", "g", "grp"), all.x = TRUE)
  out$modal_family[is.na(out$modal_family)] <- "other"
  out
}

target_exposures <- function(con) {
  dbGetQuery(con, "
    SELECT DISTINCT CAST(codinv AS DOUBLE) AS codinv,
           CAST(deal_year AS INTEGER) AS deal_year
    FROM target_cohort_own
    WHERE codinv IS NOT NULL AND deal_year IS NOT NULL")
}

build_h5_control_roster <- function(nt, target_exp, p0_weights) {
  section("P0H5 control-inventor contamination repair")
  keys <- unique(nt[, c("codinv", "stack")])
  m <- merge(keys, target_exp, by = "codinv")
  m$rel_year <- m$deal_year - m$stack
  old_hit <- m[m$rel_year >= CONTROL_CLEAN_LO & m$rel_year <= 3L, , drop = FALSE]
  if (nrow(old_hit) > 0)
    fail_integrity(sprintf("Existing never-target roster has %d competing exposures in g..g+3.", nrow(old_hit)))
  add_hit <- m[m$rel_year >= 4L & m$rel_year <= CONTROL_CLEAN_HI, , drop = FALSE]
  if (nrow(add_hit) == 0) {
    excluded <- data.frame(codinv = numeric(0), stack = integer(0),
                           earliest_competing_year = integer(0), rel_year = integer(0))
  } else {
    add_hit <- add_hit[order(add_hit$codinv, add_hit$stack, add_hit$rel_year, add_hit$deal_year), ]
    excluded <- add_hit[!duplicated(add_hit[, c("codinv", "stack")]), ]
    excluded <- excluded[, c("codinv", "stack", "deal_year", "rel_year")]
    names(excluded)[3] <- "earliest_competing_year"
  }
  ex_key <- paste(excluded$codinv, excluded$stack)
  nt_key <- paste(nt$codinv, nt$stack)
  out <- nt[!(nt_key %in% ex_key), , drop = FALSE]
  p0_ctl <- p0_weights[p0_weights$treated == 0L, , drop = FALSE]
  p0_ctl$key <- paste(p0_ctl$codinv, p0_ctl$stack)
  excluded_mass <- sum(p0_ctl$final_weight[p0_ctl$key %in% ex_key], na.rm = TRUE)
  by_rel <- if (nrow(excluded)) as.data.frame(table(rel_year = excluded$rel_year)) else
    data.frame(rel_year = integer(0), Freq = integer(0))
  by_stack <- if (nrow(excluded)) as.data.frame(table(stack = excluded$stack)) else
    data.frame(stack = integer(0), Freq = integer(0))
  list(
    units = out,
    excluded = excluded,
    diagnostics = data.frame(
      metric = c("existing_g_to_g3_hits", "additional_excluded_units_g4_g5",
                 "excluded_p0_control_weight_mass", "p0_control_units", "p0h5_control_units"),
      value = c(nrow(old_hit), nrow(excluded), excluded_mass, nrow(nt), nrow(out))
    ),
    by_rel = by_rel,
    by_stack = by_stack
  )
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

drop_acquirer_clean_cells <- function(con, control, p0h5_weighted) {
  section("P2 acquirer-clean exclusion on P0H5 roster")
  ev <- acquirer_events_predeal(con)
  cells <- unique(control[, c("underlying_group_id", "stack")])
  duckdb::duckdb_register(con, "robust_nt_cells", cells)
  duckdb::duckdb_register(con, "robust_acq_events", ev)
  on.exit({
    duckdb::duckdb_unregister(con, "robust_nt_cells")
    duckdb::duckdb_unregister(con, "robust_acq_events")
  }, add = TRUE)
  flagged <- dbGetQuery(con, sprintf("
    SELECT DISTINCT c.underlying_group_id, c.stack
    FROM robust_nt_cells c
    JOIN robust_acq_events e
      ON e.underlying_group_id = c.underlying_group_id
     AND e.deal_year BETWEEN c.stack + %d AND c.stack + %d",
    ACQUIRER_CLEAN_LO, ACQUIRER_CLEAN_HI))
  key_flag <- cell_key(flagged)
  key_control <- cell_key(control)
  missing_flagged <- setdiff(key_flag, unique(key_control))
  if (length(missing_flagged) > 0L)
    fail_integrity("P2 flagged cells are not present in the control roster.")
  keep <- !(key_control %in% key_flag)
  if (nrow(flagged) > 0L && sum(!keep) == 0L)
    fail_integrity("P2 flagged firm-stack cells but excluded zero control units.")
  weighted <- p0h5_weighted[p0h5_weighted$treated == 0L, , drop = FALSE]
  excluded_mass <- sum(weighted$final_weight[cell_key(weighted) %in% key_flag], na.rm = TRUE)
  list(
    units = control[keep, , drop = FALSE],
    flagged_cells = flagged,
    diagnostics = data.frame(
      metric = c("excluded_control_units", "excluded_firm_stack_cells",
                 "excluded_p0h5_weighted_mass", "remaining_control_units"),
      value = c(sum(!keep), nrow(flagged), excluded_mass, sum(keep))
    )
  )
}

validate_g7_clock <- function(con, g7) {
  ctl <- g7[g7$treated == 0L, , drop = FALSE]
  if (any(is.na(ctl$real_control_deal_id)))
    fail_integrity("g+7 controls have missing real_control_deal_id.")
  if (any((ctl$real_control_deal_year - ctl$stack) != CONTROL_LAG))
    fail_integrity("g+7 control clock violates real_control_deal_year - stack == 7.")
  if (any((ctl$stack + EVENT_HI) > (ctl$real_control_deal_year - 2L)))
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
  m <- merge(unique(ctl[, c("real_control_deal_id"), drop = FALSE]), spine,
             by = "real_control_deal_id", all.x = TRUE)
  if (any(is.na(m$n_years)) || any(m$n_years != 1L) || any(m$n_targets != 1L))
    fail_integrity("A real_control_deal_id does not map to exactly one deal year and future target identity.")
  data.frame(check = c("real_control_deal_year_minus_stack", "panel_end_buffer",
                       "unit_maps_one_real_control_deal", "deal_maps_one_year_target"),
             pass = TRUE)
}

balance_table <- function(units, weights, spec, constrained_covars) {
  do.call(rbind, lapply(FULL_NUMERIC_COVARS, function(v) {
    sw <- smd_weighted(units[[v]], units$treated, weights)
    data.frame(
      spec = spec,
      covariate = v,
      constrained = v %in% constrained_covars,
      smd_unweighted = smd_weighted(units[[v]], units$treated, rep(1, nrow(units))),
      smd_weighted = sw,
      abs_smd_weighted = abs(sw),
      exceeds_0_10 = abs(sw) > ROBUST_MAX_SMD_OMITTED,
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

positive_concentration <- function(units, weights, spec, p4 = FALSE) {
  ctl <- units$treated == 0L & weights > 0
  out <- NULL
  add_level <- function(level, id) {
    mass <- tapply(weights[ctl], id[ctl], sum)
    data.frame(spec = spec, level = level, n_entities = length(mass),
      ess = ess(as.numeric(mass)),
      max_share = if (length(mass)) max(mass) / sum(mass) else NA_real_,
      top5_share = if (length(mass)) sum(head(sort(mass, decreasing = TRUE), 5)) / sum(mass) else NA_real_,
      stringsAsFactors = FALSE)
  }
  out <- append_rows(out, add_level("underlying_control_firm", units$underlying_group_id))
  if (p4) out <- append_rows(out, add_level("future_control_deal", units$real_control_deal_id))
  out
}

quantile_table <- function(units, weights, spec) {
  q <- weight_quantile_diag(weights[units$treated == 0L & weights > 0])
  cbind(spec = spec, arm = "positive_control", q)
}

diagnose_fit <- function(spec, units, weights, fit, constrained_covars, p4 = FALSE) {
  assert_finite_weights(weights, spec)
  firm_mass <- fit$firm_data$firm_stage_mass
  if (is.null(firm_mass))
    firm_mass <- fit$firm_data$n_qualifying_inventors * fit$firm_data$firm_multiplier
  firm_md <- ebal_max_meandiff(model_matrix_cols(fit$firm_form, fit$firm_data),
                               fit$firm_data$treated, firm_mass)
  inv_md <- ebal_max_meandiff(model_matrix_cols(fit$inv_form, units), units$treated, weights)
  bal <- balance_table(units, weights, spec, constrained_covars)
  conc <- positive_concentration(units, weights, spec, p4 = p4)
  sm <- stack_mass_table(units, weights, spec)
  omitted_smd <- bal$abs_smd_weighted[!bal$constrained]
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
      max_smd_constrained = max(bal$abs_smd_weighted[bal$constrained], na.rm = TRUE),
      max_smd_omitted = if (length(omitted_smd)) max(omitted_smd) else NA_real_,
      max_smd_all = max(bal$abs_smd_weighted, na.rm = TRUE),
      no_empty_stack = all(sort(unique(units$stack[units$treated == 1L])) %in%
                             sort(unique(units$stack[units$treated == 0L & weights > 0]))),
      max_stack_mass_discrepancy = max(sm$relative_discrepancy, na.rm = TRUE),
      n_treated = sum(units$treated == 1L),
      n_control = sum(units$treated == 0L),
      n_units = nrow(units),
      stringsAsFactors = FALSE
    )
  )
}

feasibility_row <- function(spec, status, metrics, reason) {
  data.frame(spec = spec, status = status, feasible = identical(status, "FEASIBLE"),
             reason = reason, metrics, stringsAsFactors = FALSE)
}

gate_inventor <- function(metrics, conc, treated_ok, full_gate = FALSE) {
  reasons <- character(0)
  firm_conc <- conc[conc$level == "underlying_control_firm", ]
  if (!isTRUE(metrics$firm_converged)) reasons <- c(reasons, "firm stage did not converge")
  if (!isTRUE(metrics$inv_converged)) reasons <- c(reasons, "inventor stage did not converge")
  if (full_gate) {
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
  if (!isTRUE(metrics$no_empty_stack)) reasons <- c(reasons, "empty positive-control stack")
  if (metrics$max_stack_mass_discrepancy > STACK_MASS_TOL)
    reasons <- c(reasons, sprintf("stack mass discrepancy %.2e > %.1e",
                                  metrics$max_stack_mass_discrepancy, STACK_MASS_TOL))
  if (!treated_ok) reasons <- c(reasons, "treated weights not exactly one")
  if (length(reasons) == 0) "all gates passed" else paste(reasons, collapse = "; ")
}

run_inventor_weighted <- function(spec, units, firm_key_cols, firm_covars, inv_covars,
                                  constrained_covars, out_parquet, full_gate = FALSE,
                                  save_on_feasible = TRUE, diagnostic_path = NULL,
                                  collect_zero_diagnostics = FALSE,
                                  maxit = 30000L, reltol = 1e-10) {
  section(paste(spec, "two-stage inventor-weighted ebal"))
  fit <- tryCatch(two_stage_ebal(units, firm_key_cols, firm_covars, inv_covars,
                                 INV_FACTOR_COVARS, cont_covars = FULL_CONT_COVARS,
                                 maxit = maxit, reltol = reltol),
                  error = function(e) e)
  if (inherits(fit, "error")) {
    row <- data.frame(spec = spec, firm_converged = FALSE, inv_converged = FALSE,
      firm_meandiff = NA_real_, inv_meandiff = NA_real_, max_smd_constrained = NA_real_,
      max_smd_omitted = NA_real_, max_smd_all = NA_real_, no_empty_stack = NA,
      max_stack_mass_discrepancy = NA_real_, n_treated = sum(units$treated == 1L),
      n_control = sum(units$treated == 0L), n_units = nrow(units))
    return(list(status = "INFEASIBLE", reason = conditionMessage(fit),
                units = units, weights = NULL, diagnostics = NULL, metrics = row))
  }
  u <- fit$units
  w <- u$final_weight
  assert_finite_weights(w, spec)
  if (any(w < -1e-8))
    fail_integrity(sprintf("%s produced materially negative weights.", spec))
  if (!is.null(diagnostic_path)) {
    out <- u[, c("codinv", "underlying_group_id", "stack", "treated", "final_weight",
                 "n_qualifying_inventors")]
    if ("focal_deal_id" %in% names(u)) out$focal_deal_id <- u$focal_deal_id
    if ("real_control_deal_id" %in% names(u)) out$real_control_deal_id <- u$real_control_deal_id
    save_weights(con, out, diagnostic_path, paste0("diag_", spec))
  }
  treated_ok <- max(abs(w[u$treated == 1L] - 1)) < 1e-8
  if (!treated_ok) fail_integrity(sprintf("%s treated weights are not exactly one.", spec))
  diag <- diagnose_fit(spec, u, w, fit, constrained_covars)
  reason <- gate_inventor(diag$metrics, diag$concentration, treated_ok, full_gate = full_gate)
  status <- if (identical(reason, "all gates passed")) "FEASIBLE" else "INFEASIBLE"
  zero_diag <- NULL
  if (collect_zero_diagnostics) {
    ctl <- u$treated == 0L
    positive_ctl <- ctl & w > 0
    positive_by_stack <- aggregate(final_weight ~ stack, data.frame(stack = u$stack[positive_ctl],
      final_weight = w[positive_ctl]), length)
    names(positive_by_stack)[2] <- "positive_weight_controls"
    all_stacks <- data.frame(stack = sort(unique(u$stack)))
    positive_by_stack <- merge(all_stacks, positive_by_stack, by = "stack", all.x = TRUE)
    positive_by_stack$positive_weight_controls[is.na(positive_by_stack$positive_weight_controls)] <- 0
    zero_diag <- list(
      summary = data.frame(
        spec = spec,
        n_negative_weights = sum(ctl & w < -1e-8),
        n_zero_weights = sum(ctl & abs(w) <= 1e-12),
        n_below_near_zero = sum(ctl & w > 0 & w < NEAR_ZERO_WEIGHT),
        n_positive_weights = sum(positive_ctl),
        positive_weight_underlying_firms = length(unique(u$underlying_group_id[positive_ctl])),
        stacks_with_zero_positive_control_mass = sum(positive_by_stack$positive_weight_controls == 0),
        max_balance_discrepancy = diag$metrics$max_smd_all
      ),
      by_stack = cbind(spec = spec, positive_by_stack)
    )
    if (zero_diag$summary$n_zero_weights > 0)
      reason <- paste(reason, sprintf("%d zero/numerically zero weights", zero_diag$summary$n_zero_weights),
                      sep = ifelse(identical(reason, "all gates passed"), "", "; "))
    status <- if (identical(reason, "all gates passed")) "FEASIBLE" else "INFEASIBLE"
  }
  if (status == "FEASIBLE" && save_on_feasible) {
    out <- u[, c("codinv", "underlying_group_id", "stack", "treated", "final_weight",
                 "n_qualifying_inventors")]
    if ("focal_deal_id" %in% names(u)) out$focal_deal_id <- u$focal_deal_id
    if ("real_control_deal_id" %in% names(u)) out$real_control_deal_id <- u$real_control_deal_id
    save_weights(con, out, out_parquet, paste0("out_", spec))
  }
  list(status = status, reason = reason, units = u, weights = w,
       diagnostics = diag, zero_diag = zero_diag, metrics = diag$metrics)
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
                             firm_covars = "x", inv_covars = "z",
                             inv_factors = character(0), cont_covars = character(0),
                             maxit = 10000)
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

normalize_control_by_stack <- function(units, weights) {
  d <- data.frame(stack = units$stack, treated = units$treated, w = weights)
  mass <- aggregate(w ~ stack + treated, d, sum)
  wide <- reshape(mass, idvar = "stack", timevar = "treated", direction = "wide")
  names(wide) <- sub("w\\.0", "control_mass", names(wide))
  names(wide) <- sub("w\\.1", "treated_mass", names(wide))
  if (any(!is.finite(wide$control_mass)) || any(wide$control_mass <= 0))
    fail_integrity("Deal-weighted stack normalization has nonpositive control mass.")
  wide$scale_factor <- wide$treated_mass / wide$control_mass
  if (any(!is.finite(wide$scale_factor)) || any(wide$scale_factor <= 0))
    fail_integrity("Deal-weighted stack normalization scale factor is not positive finite.")
  out <- weights
  ctl <- units$treated == 0L
  out[ctl] <- weights[ctl] * wide$scale_factor[match(units$stack[ctl], wide$stack)]
  list(weights = out, scales = wide)
}

run_deal_weighted <- function(spec, units, out_parquet, firm_key_cols,
                              require_future_deal_concentration = FALSE,
                              expected_roster_key = NULL) {
  section(paste(spec, "deal-weighted two-stage ebal with within-stack normalization"))
  if (!is.null(expected_roster_key)) {
    k <- unit_key(units)
    if (length(setdiff(k, expected_roster_key)) > 0L ||
        length(setdiff(expected_roster_key, k)) > 0L)
      fail_integrity(sprintf("%s does not use exactly the expected roster.", spec))
  }
  treated <- units$treated == 1L
  deal_n <- table(units$focal_deal_id[treated])
  N_T <- sum(treated)
  D <- length(deal_n)
  units$treated_base_weight_id <- ifelse(treated,
    N_T / (D * as.numeric(deal_n[as.character(units$focal_deal_id)])), 1)
  target_mass <- N_T / D
  pre_mass <- tapply(units$treated_base_weight_id[treated], units$focal_deal_id[treated], sum)
  if (max(abs(pre_mass - target_mass) / target_mass) > P4_DEAL_MASS_TOL)
    fail_integrity(sprintf("%s treated_base_weight_id does not give equal treated deal totals.", spec))
  fit <- tryCatch(two_stage_deal_ebal(units, firm_key_cols,
                                      FIRM_COVARS, INV_COVARS, INV_FACTOR_COVARS,
                                      FULL_CONT_COVARS),
                  error = function(e) e)
  if (inherits(fit, "error")) {
    row <- data.frame(spec = spec, firm_converged = FALSE, inv_converged = FALSE,
      firm_meandiff = NA_real_, inv_meandiff = NA_real_, max_smd_constrained = NA_real_,
      max_smd_omitted = NA_real_, max_smd_all = NA_real_, no_empty_stack = NA,
      max_stack_mass_discrepancy = NA_real_, n_treated = sum(units$treated == 1L),
      n_control = sum(units$treated == 0L), n_units = nrow(units))
    return(list(status = "INFEASIBLE", reason = conditionMessage(fit),
                units = units, weights = NULL, diagnostics = NULL, metrics = row))
  }
  u <- fit$units
  w0 <- u$final_weight
  assert_finite_weights(w0, spec)
  if (any(w0 <= 0)) {
    row <- data.frame(spec = spec, firm_converged = FALSE, inv_converged = FALSE,
      firm_meandiff = NA_real_, inv_meandiff = NA_real_, max_smd_constrained = NA_real_,
      max_smd_omitted = NA_real_, max_smd_all = NA_real_, no_empty_stack = NA,
      max_stack_mass_discrepancy = NA_real_, n_treated = sum(u$treated == 1L),
      n_control = sum(u$treated == 0L), n_units = nrow(u))
    return(list(status = "INFEASIBLE",
      reason = sprintf("%d finite but nonpositive weights", sum(w0 <= 0)),
      units = u, weights = w0, diagnostics = NULL, metrics = row))
  }
  if (max(abs(w0[u$treated == 1L] - u$treated_base_weight_id[u$treated == 1L])) > 1e-8)
    fail_integrity(sprintf("%s treated weights changed before normalization.", spec))
  norm <- normalize_control_by_stack(u, w0)
  w <- norm$weights
  if (max(abs(w[u$treated == 1L] - u$treated_base_weight_id[u$treated == 1L])) > 1e-8)
    fail_integrity(sprintf("%s treated weights changed during normalization.", spec))
  post_mass <- tapply(w[u$treated == 1L], u$focal_deal_id[u$treated == 1L], sum)
  deal_equal <- max(abs(post_mass - target_mass) / target_mass) <= P4_DEAL_MASS_TOL
  if (!deal_equal) fail_integrity(sprintf("%s treated deal-total equality failed after normalization.", spec))
  diag <- diagnose_fit(spec, u, w, fit, FULL_NUMERIC_COVARS, p4 = require_future_deal_concentration)
  pre_diag <- diagnose_fit(paste0(spec, "_pre_norm"), u, w0, fit, FULL_NUMERIC_COVARS,
                           p4 = require_future_deal_concentration)
  conc_deal <- diag$concentration[diag$concentration$level == "future_control_deal", , drop = FALSE]
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
  if (require_future_deal_concentration && conc_deal$ess < ROBUST_MIN_ESS)
    reasons <- c(reasons, "future-control-deal ESS below 50")
  if (conc_firm$ess < ROBUST_MIN_ESS) reasons <- c(reasons, "underlying-control-firm ESS below 50")
  if (require_future_deal_concentration && conc_deal$max_share > ROBUST_MAX_SHARE)
    reasons <- c(reasons, "future-control-deal max share above 10%")
  if (conc_firm$max_share > ROBUST_MAX_SHARE) reasons <- c(reasons, "underlying-control-firm max share above 10%")
  if (!isTRUE(diag$metrics$no_empty_stack)) reasons <- c(reasons, "empty positive-control stack")
  if (diag$metrics$max_stack_mass_discrepancy > 1e-8) reasons <- c(reasons, "stack mass discrepancy above numerical precision")
  if (!is.null(expected_roster_key)) {
    k <- unit_key(u)
    if (length(setdiff(k, expected_roster_key)) > 0L ||
        length(setdiff(expected_roster_key, k)) > 0L)
      reasons <- c(reasons, "roster differs from expected roster")
  }
  status <- if (length(reasons) == 0) "FEASIBLE" else "INFEASIBLE"
  reason <- if (status == "FEASIBLE") "all post-normalization gates passed" else paste(reasons, collapse = "; ")
  if (status == "FEASIBLE") {
    keep_cols <- intersect(c("codinv", "underlying_group_id", "stack", "treated",
      "n_qualifying_inventors", "focal_deal_id", "real_control_deal_id",
      "treated_base_weight_id"), names(u))
    out <- u[, keep_cols, drop = FALSE]
    out$final_weight <- w
    save_weights(con, out, out_parquet, paste0("out_", spec))
  }
  list(status = status, reason = reason, units = u, weights = w,
       pre_weights = w0, diagnostics = diag, pre_diagnostics = pre_diag,
       scale_factors = transform(norm$scales,
         max_abs_scale_deviation = max(abs(norm$scales$scale_factor - 1))),
       metrics = diag$metrics)
}

add_result <- function(spec, res) {
  design <<- append_rows(design, res$metrics)
  feasibility <<- append_rows(feasibility, feasibility_row(spec, res$status, res$metrics, res$reason))
  if (!is.null(res$diagnostics)) {
    balance_all <<- append_rows(balance_all, res$diagnostics$balance)
    concentration_all <<- append_rows(concentration_all, res$diagnostics$concentration)
    stack_mass_all <<- append_rows(stack_mass_all, res$diagnostics$stack_mass)
    quantiles_all <<- append_rows(quantiles_all, res$diagnostics$quantiles)
  }
  if (!is.null(res$units)) {
    k <- unit_key(res$units)
    unit_diff <<- append_rows(unit_diff, data.frame(spec = spec,
      shared_with_p0 = length(intersect(k, p0_key)),
      only_in_spec_vs_p0 = length(setdiff(k, p0_key)),
      only_in_p0 = length(setdiff(p0_key, k)),
      shared_with_p0h5 = if (exists("p0h5_key")) length(intersect(k, p0h5_key)) else NA_integer_,
      only_in_spec_vs_p0h5 = if (exists("p0h5_key")) length(setdiff(k, p0h5_key)) else NA_integer_,
      only_in_p0h5 = if (exists("p0h5_key")) length(setdiff(p0h5_key, k)) else NA_integer_))
  }
}

write_checkpoint_note <- function() {
  fmt <- function(x, digits = 3) ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "fg"))
  md_cell <- function(x) gsub("\\|", "\\\\|", x)
  p1_omitted <- balance_all[balance_all$spec == "P1" & !balance_all$constrained, ]
  p1_omitted <- p1_omitted[order(-p1_omitted$abs_smd_weighted), ]
  p1_max <- if (nrow(p1_omitted)) p1_omitted[1, ] else NULL
  p4_pre <- design[design$spec == "P4_pre_norm", , drop = FALSE]
  p5_pre <- design[design$spec == "P5_pre_norm", , drop = FALSE]
  lines <- c(
    "# Main DiD v1 Robustness Design Checkpoint",
    "",
    sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    "",
    "## Scope",
    "",
    "This Phase 1C checkpoint repairs the P2 acquirer-clean exclusion, adds P5, and reruns design-only robustness diagnostics. It does not build outcomes, open `patent_enriched`, run citation checks, or estimate treatment effects.",
    "",
    "P0 remains the frozen legacy benchmark from commit `99923f8`; its never-target control-inventor contamination screening ended at g+3. P0H5 is the corrected candidate primary never-target design with control-inventor competing acquisitions excluded through g+5. P5 uses exactly the P0H5 roster but changes the estimand to a deal-weighted ATT.",
    "",
    "## Design Matrix",
    "",
    "| Control pool | Inventor-weighted ATT | Deal-weighted ATT |",
    "| --- | --- | --- |",
    "| Never-target | P0H5; P2 acquirer-clean restriction | P5 |",
    "| g+7 future-treated | P3 (infeasible) | P4 |",
    "",
    "## Final Design Decisions",
    "",
    "| Spec | Roster/estimand | Decision | Principal reason |",
    "| --- | --- | --- | --- |"
  )
  for (i in seq_len(nrow(feasibility))) {
    roster <- switch(feasibility$spec[i],
      P0 = "Frozen legacy benchmark",
      P0H5 = "Corrected never-target, inventor ATT",
      P1 = "Reduced numeric specification on P0H5",
      P2 = "No observed acquirer event g-1..g+5",
      P3 = "g+7, inventor ATT",
      P4 = "g+7, deal ATT",
      P5 = "Corrected never-target, deal ATT",
      feasibility$spec[i])
    lines <- c(lines, sprintf("| %s | %s | %s | %s |",
      md_cell(feasibility$spec[i]), md_cell(roster), md_cell(feasibility$status[i]),
      md_cell(feasibility$reason[i])))
  }
  lines <- c(lines, "", "## P0H5 Contamination Repair", "")
  for (i in seq_len(nrow(h5_diag))) {
    lines <- c(lines, sprintf("- %s: %s", h5_diag$metric[i], fmt(as.numeric(h5_diag$value[i]), 6)))
  }
  if (nrow(h5_by_rel)) {
    lines <- c(lines, sprintf("- Additional exclusions by relative year: %s.",
      paste(sprintf("g+%s=%s", h5_by_rel$rel_year, h5_by_rel$Freq), collapse = ", ")))
  }
  lines <- c(lines, "", "## P1 Omitted-Covariate Diagnostics", "")
  if (!is.null(p1_max)) {
    lines <- c(lines, sprintf(
      "The largest omitted weighted imbalance is `%s`, with weighted SMD %s.",
      p1_max$covariate, fmt(p1_max$smd_weighted, 4)))
  }
  if (nrow(p1_omitted)) {
    lines <- c(lines, "| Covariate | Unweighted SMD | Weighted SMD | Abs weighted SMD | Exceeds 0.10 |",
      "| --- | ---: | ---: | ---: | --- |")
    for (i in seq_len(nrow(p1_omitted))) {
      lines <- c(lines, sprintf("| %s | %s | %s | %s | %s |",
        p1_omitted$covariate[i], fmt(p1_omitted$smd_unweighted[i], 4),
        fmt(p1_omitted$smd_weighted[i], 4), fmt(p1_omitted$abs_smd_weighted[i], 4),
        p1_omitted$exceeds_0_10[i]))
    }
  }
  lines <- c(lines, "", "## P2 Acquirer-Clean Diagnostics", "")
  for (i in seq_len(nrow(p2_diag_extra))) {
    lines <- c(lines, sprintf("- %s: %s", p2_diag_extra$metric[i], fmt(as.numeric(p2_diag_extra$value[i]), 6)))
  }
  lines <- c(lines, "", "## P3 Positive-Weight Diagnostics", "")
  if (!is.null(p3_zero_summary)) {
    for (nm in names(p3_zero_summary)) {
      if (nm != "spec") lines <- c(lines, sprintf("- %s: %s", nm, fmt(as.numeric(p3_zero_summary[[nm]]), 6)))
    }
  }
  lines <- c(lines, "", "## P4 Normalization Diagnostics", "")
  if (nrow(p4_pre)) {
    lines <- c(lines, sprintf("- Pre-normalization max stack-mass discrepancy: %s.",
                              fmt(p4_pre$max_stack_mass_discrepancy[1], 6)))
  }
  if (!is.null(p4_scales)) {
    lines <- c(lines, sprintf("- Stack scale factors: min %s, max %s, max absolute deviation from one %s.",
      fmt(min(p4_scales$scale_factor), 6), fmt(max(p4_scales$scale_factor), 6),
      fmt(max(abs(p4_scales$scale_factor - 1)), 6)))
  }
  lines <- c(lines, "", "## P5 Deal-Weighted Never-Target Diagnostics", "")
  if (nrow(p5_pre)) {
    lines <- c(lines, sprintf("- Pre-normalization max stack-mass discrepancy: %s.",
                              fmt(p5_pre$max_stack_mass_discrepancy[1], 6)))
  }
  if (!is.null(p5_scales)) {
    lines <- c(lines, sprintf("- Stack scale factors: min %s, max %s, max absolute deviation from one %s.",
      fmt(min(p5_scales$scale_factor), 6), fmt(max(p5_scales$scale_factor), 6),
      fmt(max(abs(p5_scales$scale_factor - 1)), 6)))
    lines <- c(lines, "- P5 uses exactly the P0H5 analysis-unit roster; only the treated estimand and weights change.")
  }
  lines <- c(lines, "", "## g+7 Sample Count Reconciliation", "",
    sprintf("- Authoritative current `main_did_v1_units.parquet` control count: %s.", g7_count_current),
    "- The older `10,630` count appears in `main_did_v1_first_results.md` and is a stale memo count from an earlier cleanliness/artifact state.",
    sprintf("- The Phase 1C runner uses the current derived artifact and records %s g+7 controls for P3/P4.", g7_count_current),
    "",
    "## Core Diagnostics",
    "")
  for (i in seq_len(nrow(design))) {
    lines <- c(lines, sprintf(
      "- `%s`: max |SMD| all %s; constrained %s; omitted %s; max stack-mass discrepancy %s; treated N %s; control N %s.",
      design$spec[i], fmt(design$max_smd_all[i]), fmt(design$max_smd_constrained[i]),
      fmt(design$max_smd_omitted[i]), fmt(design$max_stack_mass_discrepancy[i], 6),
      design$n_treated[i], design$n_control[i]))
  }
  lines <- c(lines, "", "## Control Concentration", "")
  for (i in seq_len(nrow(concentration_all))) {
    lines <- c(lines, sprintf("- `%s` %s: ESS %s; max share %s; top-five share %s.",
      concentration_all$spec[i], concentration_all$level[i], fmt(concentration_all$ess[i]),
      fmt(concentration_all$max_share[i]), fmt(concentration_all$top5_share[i])))
  }
  lines <- c(lines, "", "## Unit Comparisons", "")
  for (i in seq_len(nrow(unit_diff))) {
    lines <- c(lines, sprintf(
      "- `%s`: shared with P0 %s; only in spec vs P0 %s; only in P0 %s; shared with P0H5 %s; only in spec vs P0H5 %s; only in P0H5 %s.",
      unit_diff$spec[i], unit_diff$shared_with_p0[i], unit_diff$only_in_spec_vs_p0[i],
      unit_diff$only_in_p0[i], unit_diff$shared_with_p0h5[i],
      unit_diff$only_in_spec_vs_p0h5[i], unit_diff$only_in_p0h5[i]))
  }
  lines <- c(lines, "", "## Deal-Weighted Contract Self-Test", "")
  for (i in seq_len(nrow(p4_st))) {
    lines <- c(lines, sprintf("- %s: %s (%s).", p4_st$check[i],
                              ifelse(p4_st$pass[i], "pass", "fail"), p4_st$detail[i]))
  }
  lines <- c(lines, "", "## g+7 Identity Checks", "")
  for (i in seq_len(nrow(g7_checks))) lines <- c(lines, sprintf("- %s: pass.", g7_checks$check[i]))
  lines <- c(lines, "", "## Mandatory Phase 2 Safeguards", "",
    "- Check duplicate `patent_enriched` rows for conflicting non-missing `fwd_cits5` values.",
    "- Verify the citation follow-up cutoff without treating the database maximum patent year as full certification.",
    "- Audit citation missingness and missing citation mass among patent-active rows by treatment status.",
    "- Recompute all original balance diagnostics on the restricted citation sample for each feasible specification.",
    "- Keep citation results provisional when raw citing-year histories remain unavailable.",
    "")
  writeLines(lines, ROBUSTNESS_NOTE, useBytes = TRUE)
}

# Behavior-preserving guard: the nt2010 build sources this file for its weighting
# helpers only (option set), without re-running the frozen P0-P5 build or touching
# any frozen output. Default (option unset) = full execution, unchanged.
if (isTRUE(getOption("main_did_v1.source_functions_only", FALSE))) {
  message("11j sourced functions-only (main_did_v1.source_functions_only=TRUE); ",
          "skipping frozen P0-P5 execution.")
} else {

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='10GB'")
dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sql_path(DUCKDB_TMP)))

design <- NULL
balance_all <- NULL
concentration_all <- NULL
stack_mass_all <- NULL
quantiles_all <- NULL
feasibility <- NULL
unit_diff <- NULL
p3_zero_summary <- NULL
p4_scales <- NULL
p5_scales <- NULL
p2_diag_extra <- data.frame(metric = character(0), value = numeric(0))

banner("Deal-weighted synthetic self-test")
p4_st <- p4_selftest()
print(p4_st)
if (!all(p4_st$pass)) fail_integrity("Deal-weighted synthetic self-test failed.")

banner("Load frozen P0 and base rosters")
treated <- load_treated_units(con)
p0 <- dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", sql_path(P0_WEIGHTS_PARQUET)))
p0$codinv <- as.numeric(p0$codinv)
p0$stack <- as.integer(p0$stack)
p0$treated <- as.integer(p0$treated)
assert_unique_unit_keys(p0, "P0 frozen weights")
p0_key <- unit_key(p0)

p0_conc <- positive_concentration(transform(p0, real_control_deal_id = NA_integer_), p0$final_weight, "P0")
p0_sm <- stack_mass_table(p0, p0$final_weight, "P0")
p0_diag_path <- file.path(AUDIT_DIR, "never_target_stage2_diagnostics.csv")
p0_diag <- if (file.exists(p0_diag_path)) utils::read.csv(p0_diag_path, stringsAsFactors = FALSE) else data.frame()
p0_metrics <- data.frame(spec = "P0",
  firm_converged = if (nrow(p0_diag)) p0_diag$firm_converged[1] else NA,
  inv_converged = if (nrow(p0_diag)) p0_diag$inv_converged[1] else NA,
  firm_meandiff = if (nrow(p0_diag)) p0_diag$firm_meandiff[1] else NA_real_,
  inv_meandiff = if (nrow(p0_diag)) p0_diag$inv_meandiff[1] else NA_real_,
  max_smd_constrained = if (nrow(p0_diag)) p0_diag$max_smd_post[1] else NA_real_,
  max_smd_omitted = NA_real_,
  max_smd_all = if (nrow(p0_diag)) p0_diag$max_smd_post[1] else NA_real_,
  no_empty_stack = TRUE,
  max_stack_mass_discrepancy = max(p0_sm$relative_discrepancy, na.rm = TRUE),
  n_treated = sum(p0$treated == 1L), n_control = sum(p0$treated == 0L), n_units = nrow(p0))
design <- append_rows(design, p0_metrics)
feasibility <- append_rows(feasibility,
  feasibility_row("P0", "FROZEN", p0_metrics, "legacy benchmark; control cleanliness originally through g+3"))
concentration_all <- append_rows(concentration_all, p0_conc)
stack_mass_all <- append_rows(stack_mass_all, p0_sm)
quantiles_all <- append_rows(quantiles_all, quantile_table(p0, p0$final_weight, "P0"))

nt_base <- load_never_target_units(con)
nt_cov <- compute_nt_inventor_covariates(con, nt_base)
target_exp <- target_exposures(con)
h5 <- build_h5_control_roster(nt_cov, target_exp, p0)
h5_control <- h5$units
h5_diag <- h5$diagnostics
h5_by_rel <- h5$by_rel
h5_by_stack <- h5$by_stack

banner("P0H5 corrected never-target full covariates")
p0h5_units_pre <- prepare_units(
  treated[, c("codinv", "focal_deal_id", "underlying_group_id", "stack", "treated",
              "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
              "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  h5_control[, c("codinv", "focal_deal_id", "underlying_group_id", "stack", "treated",
                 "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
                 "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  c("underlying_group_id", "stack"))
res_p0h5 <- run_inventor_weighted("P0H5", p0h5_units_pre, c("underlying_group_id", "stack"),
  FIRM_COVARS, INV_COVARS, constrained_covars = FULL_NUMERIC_COVARS,
  out_parquet = P0H5_WEIGHTS_PARQUET, full_gate = TRUE)
add_result("P0H5", res_p0h5)
p0h5_key <- unit_key(res_p0h5$units)
if (!identical(res_p0h5$status, "FEASIBLE")) {
  write_phase_csv(design, ROBUSTNESS_DESIGN_COMPARISON)
  write_phase_csv(balance_all, ROBUSTNESS_BALANCE_ALL)
  write_phase_csv(concentration_all, ROBUSTNESS_CONCENTRATION)
  write_phase_csv(stack_mass_all, ROBUSTNESS_STACK_MASS)
  write_phase_csv(quantiles_all, ROBUSTNESS_QUANTILES)
  write_phase_csv(feasibility, ROBUSTNESS_FEASIBILITY)
  write_checkpoint_note()
  stop("P0H5 is infeasible; stopping before P1-P5 as requested.", call. = FALSE)
}

banner("P1 reduced numeric covariates on P0H5 units")
p1_units <- p0h5_units_pre[unit_key(p0h5_units_pre) %in% p0h5_key, , drop = FALSE]
if (length(setdiff(p0h5_key, unit_key(p1_units))) > 0L ||
    length(setdiff(unit_key(p1_units), p0h5_key)) > 0L)
  fail_integrity("P1 does not use exactly P0H5 units.")
res_p1 <- run_inventor_weighted("P1", p1_units, c("underlying_group_id", "stack"),
  FIRM_COVARS_REDUCED, INVENTOR_COVARS_REDUCED,
  constrained_covars = c(FIRM_COVARS_REDUCED, INVENTOR_COVARS_REDUCED),
  out_parquet = P1_WEIGHTS_PARQUET)
add_result("P1", res_p1)

banner("P2 acquirer-clean on P0H5")
p2_drop <- drop_acquirer_clean_cells(con, h5_control, res_p0h5$units)
p2_diag_extra <- p2_drop$diagnostics
p2_units <- prepare_units(
  treated[, c("codinv", "focal_deal_id", "underlying_group_id", "stack", "treated",
              "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
              "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  p2_drop$units[, c("codinv", "focal_deal_id", "underlying_group_id", "stack", "treated",
                    "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
                    "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  c("underlying_group_id", "stack"))
res_p2 <- run_inventor_weighted("P2", p2_units, c("underlying_group_id", "stack"),
  FIRM_COVARS, INV_COVARS, constrained_covars = FULL_NUMERIC_COVARS,
  out_parquet = P2_WEIGHTS_PARQUET, full_gate = TRUE)
add_result("P2", res_p2)

banner("P5 corrected never-target deal-weighted normalized diagnostics")
p5_units <- p0h5_units_pre[unit_key(p0h5_units_pre) %in% p0h5_key, , drop = FALSE]
if (length(setdiff(p0h5_key, unit_key(p5_units))) > 0L ||
    length(setdiff(unit_key(p5_units), p0h5_key)) > 0L)
  fail_integrity("P5 does not use exactly P0H5 units.")
res_p5 <- run_deal_weighted("P5", p5_units, P5_WEIGHTS_PARQUET,
  firm_key_cols = c("focal_deal_id", "underlying_group_id", "stack", "arm"),
  require_future_deal_concentration = FALSE,
  expected_roster_key = p0h5_key)
p5_scales <- res_p5$scale_factors
if (!is.null(res_p5$pre_diagnostics)) {
  pre <- res_p5$pre_diagnostics
  design <- append_rows(design, pre$metrics)
  balance_all <- append_rows(balance_all, pre$balance)
  concentration_all <- append_rows(concentration_all, pre$concentration)
  stack_mass_all <- append_rows(stack_mass_all, pre$stack_mass)
}
if (!is.null(p5_scales))
  write_phase_csv(p5_scales, file.path(RESULTS_DIR, "main_robustness_p5_stack_scale_factors.csv"))
add_result("P5", res_p5)

banner("P3/P4 g+7 design and clock checks")
g7_raw <- load_g7_units(con)
g7_count_current <- sum(g7_raw$treated == 0L)
g7_checks <- validate_g7_clock(con, g7_raw)
g7 <- prepare_units(
  g7_raw[g7_raw$treated == 1L, c("codinv", "focal_deal_id", "underlying_group_id",
    "stack", "treated", "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
    "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  g7_raw[g7_raw$treated == 0L, c("codinv", "focal_deal_id", "underlying_group_id",
    "stack", "treated", "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
    "real_control_deal_year", FIRM_COVARS, INV_COVARS)],
  c("focal_deal_id", "underlying_group_id", "stack", "arm"))

banner("P3 g+7 reduced numeric inventor-weighted diagnostics")
res_p3 <- run_inventor_weighted("P3", g7, c("focal_deal_id", "underlying_group_id", "stack", "arm"),
  FIRM_COVARS_REDUCED, INVENTOR_COVARS_REDUCED,
  constrained_covars = c(FIRM_COVARS_REDUCED, INVENTOR_COVARS_REDUCED),
  out_parquet = P3_WEIGHTS_PARQUET, diagnostic_path = P3_DIAGNOSTIC_WEIGHTS_PARQUET,
  collect_zero_diagnostics = TRUE)
if (!is.null(res_p3$zero_diag)) {
  p3_zero_summary <- res_p3$zero_diag$summary
  write_phase_csv(res_p3$zero_diag$by_stack,
    file.path(RESULTS_DIR, "main_robustness_p3_positive_controls_by_stack.csv"))
  write_phase_csv(p3_zero_summary,
    file.path(RESULTS_DIR, "main_robustness_p3_weight_pathology.csv"))
}
add_result("P3", res_p3)

banner("P4 g+7 deal-weighted normalized diagnostics")
res_p4 <- run_deal_weighted("P4", g7, P4_WEIGHTS_PARQUET,
  firm_key_cols = c("focal_deal_id", "underlying_group_id", "stack", "arm"),
  require_future_deal_concentration = TRUE)
p4_scales <- res_p4$scale_factors
if (!is.null(res_p4$pre_diagnostics)) {
  pre <- res_p4$pre_diagnostics
  design <- append_rows(design, pre$metrics)
  balance_all <- append_rows(balance_all, pre$balance)
  concentration_all <- append_rows(concentration_all, pre$concentration)
  stack_mass_all <- append_rows(stack_mass_all, pre$stack_mass)
}
if (!is.null(p4_scales))
  write_phase_csv(p4_scales, file.path(RESULTS_DIR, "main_robustness_p4_stack_scale_factors.csv"))
add_result("P4", res_p4)

banner("Writing Phase 1C diagnostics and checkpoint note")
write_phase_csv(design, ROBUSTNESS_DESIGN_COMPARISON)
write_phase_csv(balance_all, ROBUSTNESS_BALANCE_ALL)
write_phase_csv(concentration_all, ROBUSTNESS_CONCENTRATION)
write_phase_csv(stack_mass_all, ROBUSTNESS_STACK_MASS)
write_phase_csv(quantiles_all, ROBUSTNESS_QUANTILES)
write_phase_csv(feasibility, ROBUSTNESS_FEASIBILITY)
write_phase_csv(h5_diag, file.path(RESULTS_DIR, "main_robustness_h5_exclusion_summary.csv"))
write_phase_csv(h5_by_rel, file.path(RESULTS_DIR, "main_robustness_h5_exclusions_by_relative_year.csv"))
write_phase_csv(h5_by_stack, file.path(RESULTS_DIR, "main_robustness_h5_exclusions_by_stack.csv"))
write_phase_csv(unit_diff, file.path(RESULTS_DIR, "main_robustness_unit_overlap.csv"))
write_checkpoint_note()

options(width = 220)
print(feasibility[, c("spec", "status", "reason")])
banner("11j Phase 1C DONE -- stop before outcome estimation")

}  # end behavior-preserving execution guard (functions-only sourcing skips the above)

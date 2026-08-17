# ============================================================================
# 11o_build_nt2010_weights.R -- nt2010 P0H5 + P5 weights and design diagnostics
# ----------------------------------------------------------------------------
# Package 2. Builds P0H5 (inventor-weighted) and P5 (deal-weighted) entropy
# weights on EXACTLY the same combined nt2010 roster, for the full 1994-2010
# horizon and for the 1994-2008 common-cohort comparison. Design-only: NO
# outcomes, NO treatment-effect estimation.
#
# Weighting machinery is reused verbatim from 11j via the behavior-preserving
# functions-only guard (getOption("main_did_v1.source_functions_only")), so the
# nt2010 estimand construction is identical to the frozen design. Writes ONLY to
# versioned nt2010 paths; never touches frozen weights/outputs.
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
options(main_did_v1.source_functions_only = TRUE)
source(file.path(BASE, "R", "11j_build_robustness_weights.R"))   # config + helpers only
options(main_did_v1.source_functions_only = NULL)
set.seed(SEED)

# nt2010 tightens the ebal optimiser (NOT a feasibility threshold): the larger
# expanded problem needs a tighter convergence tolerance to satisfy the unchanged
# 1e-4 stack-mass gate. Verified: brings P0H5_nt2010 stack-mass 1.29e-4 -> 9.97e-6.
NT2010_EBAL_MAXIT  <- 200000L
NT2010_EBAL_RELTOL <- 1e-12

nt_res_path <- function(name) paste0(NT2010_RESULTS_PREFIX, "_", name)
nt_write    <- function(df, name) { utils::write.csv(df, nt_res_path(name), row.names = FALSE, na = "");
                                    message("  wrote ", nt_res_path(name)) }

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='10GB'"); dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sql_path(DUCKDB_TMP)))

banner("NT2010 WEIGHTS -- P0H5 + P5 (1994-2010 and 1994-2008 common cohort)")

# ---------------------------------------------------------------------------
# Load combined roster; split arms
# ---------------------------------------------------------------------------
roster <- dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')",
                                  sql_path(NT2010_ANALYSIS_UNITS_PARQUET)))
roster$codinv <- as.numeric(roster$codinv)
roster$stack <- as.integer(roster$stack)
roster$treated <- as.integer(roster$treated)
roster$underlying_group_id <- as.numeric(roster$underlying_group_id)
roster$focal_deal_id <- as.integer(roster$focal_deal_id)
message(sprintf("Roster: %d rows (treated=%d control=%d), stacks [%d,%d]",
        nrow(roster), sum(roster$treated == 1L), sum(roster$treated == 0L),
        min(roster$stack), max(roster$stack)))

roster_cols <- c("codinv", "focal_deal_id", "underlying_group_id", "stack", "treated",
                 "arm", "qualifying_gap", "modal_family", "real_control_deal_id",
                 "real_control_deal_year", FIRM_COVARS, INV_COVARS)

# ---------------------------------------------------------------------------
# Extra diagnostics not in diagnose_fit: era + per-cohort weighted balance
# ---------------------------------------------------------------------------
era_balance <- function(units, weights, spec, eras) {
  cont <- FULL_CONT_COVARS
  do.call(rbind, lapply(eras, function(er) {
    idx <- units$stack >= er[1] & units$stack <= er[2]
    if (sum(units$treated[idx] == 1L) == 0 || sum(units$treated[idx] == 0L) == 0) return(NULL)
    s <- sapply(cont, function(v) abs(smd_weighted(units[[v]][idx], units$treated[idx], weights[idx])))
    data.frame(spec = spec, era = paste(er, collapse = "-"),
               n_treated = sum(units$treated[idx] == 1L),
               n_control_pos = sum(units$treated[idx] == 0L & weights[idx] > 0),
               max_abs_smd = max(s), median_abs_smd = stats::median(s))
  }))
}
cohort_balance <- function(units, weights, spec) {
  cont <- FULL_CONT_COVARS
  do.call(rbind, lapply(sort(unique(units$stack)), function(g) {
    idx <- units$stack == g
    if (sum(units$treated[idx] == 1L) == 0 || sum(units$treated[idx] == 0L) == 0) return(NULL)
    s <- sapply(cont, function(v) abs(smd_weighted(units[[v]][idx], units$treated[idx], weights[idx])))
    data.frame(spec = spec, cohort = g,
               n_treated = sum(units$treated[idx] == 1L),
               n_control_pos = sum(units$treated[idx] == 0L & weights[idx] > 0),
               max_abs_smd = max(s), median_abs_smd = stats::median(s))
  }))
}

# ---------------------------------------------------------------------------
# One P0H5+P5 pass on a roster subset. Returns diagnostics accumulators.
# ---------------------------------------------------------------------------
run_pair <- function(roster_sub, tag, p0h5_path, p5_path, eras) {
  banner(sprintf("[%s] P0H5 (inventor-weighted) then P5 (deal-weighted)", tag))
  treated_df <- roster_sub[roster_sub$treated == 1L, roster_cols, drop = FALSE]
  control_df <- roster_sub[roster_sub$treated == 0L, roster_cols, drop = FALSE]

  # --- P0H5 ---
  p0h5_units <- prepare_units(treated_df, control_df, c("underlying_group_id", "stack"))
  res_p0h5 <- run_inventor_weighted(paste0("P0H5_", tag), p0h5_units,
    c("underlying_group_id", "stack"), FIRM_COVARS, INV_COVARS,
    constrained_covars = FULL_NUMERIC_COVARS, out_parquet = p0h5_path, full_gate = TRUE,
    maxit = NT2010_EBAL_MAXIT, reltol = NT2010_EBAL_RELTOL)
  p0h5_key <- unit_key(res_p0h5$units)
  message(sprintf("[%s] P0H5: status=%s | %s", tag, res_p0h5$status, res_p0h5$reason))

  # --- P5 (exactly the P0H5 roster) ---
  p5_units <- p0h5_units[unit_key(p0h5_units) %in% p0h5_key, , drop = FALSE]
  if (length(setdiff(p0h5_key, unit_key(p5_units))) > 0L ||
      length(setdiff(unit_key(p5_units), p0h5_key)) > 0L)
    fail_integrity(sprintf("[%s] P5 does not use exactly the P0H5 roster.", tag))
  res_p5 <- run_deal_weighted(paste0("P5_", tag), p5_units, p5_path,
    firm_key_cols = c("focal_deal_id", "underlying_group_id", "stack", "arm"),
    require_future_deal_concentration = FALSE, expected_roster_key = p0h5_key)
  message(sprintf("[%s] P5: status=%s | %s", tag, res_p5$status, res_p5$reason))

  # accumulate diagnostics
  bal <- rbind(res_p0h5$diagnostics$balance, res_p5$diagnostics$balance)
  conc <- rbind(res_p0h5$diagnostics$concentration, res_p5$diagnostics$concentration)
  sm  <- rbind(res_p0h5$diagnostics$stack_mass, res_p5$diagnostics$stack_mass)
  qn  <- rbind(res_p0h5$diagnostics$quantiles, res_p5$diagnostics$quantiles)
  met <- rbind(res_p0h5$metrics, res_p5$metrics)
  feas <- rbind(
    feasibility_row(paste0("P0H5_", tag), res_p0h5$status, res_p0h5$metrics, res_p0h5$reason),
    feasibility_row(paste0("P5_", tag), res_p5$status, res_p5$metrics, res_p5$reason))
  # era + cohort balance on the P0H5 fit (primary inventor design)
  eb <- era_balance(res_p0h5$units, res_p0h5$weights, paste0("P0H5_", tag), eras)
  cb <- cohort_balance(res_p0h5$units, res_p0h5$weights, paste0("P0H5_", tag))
  # P5 deal-weighted era/cohort too (deal design)
  eb5 <- era_balance(res_p5$units, res_p5$weights, paste0("P5_", tag), eras)
  cb5 <- cohort_balance(res_p5$units, res_p5$weights, paste0("P5_", tag))
  list(balance = bal, concentration = conc, stack_mass = sm, quantiles = qn,
       metrics = met, feasibility = feas,
       era = rbind(eb, eb5), cohort = rbind(cb, cb5),
       p5_scales = res_p5$scale_factors,
       p0h5_status = res_p0h5$status, p5_status = res_p5$status)
}

# ===========================================================================
# Full horizon 1994-2010
# ===========================================================================
full <- run_pair(roster, "nt2010", P0H5_NT2010_WEIGHTS_PARQUET, P5_NT2010_WEIGHTS_PARQUET,
                 BALANCE_ERAS_NEVER_TARGET)

# ===========================================================================
# Common cohort 1994-2008 (same roster, filtered)
# ===========================================================================
roster_cc <- roster[roster$stack <= CC_STACK_HI, , drop = FALSE]
message(sprintf("Common-cohort subset: %d rows, stacks [%d,%d]",
        nrow(roster_cc), min(roster_cc$stack), max(roster_cc$stack)))
cc <- run_pair(roster_cc, "cc9408", P0H5_CC9408_WEIGHTS_PARQUET, P5_CC9408_WEIGHTS_PARQUET,
               BALANCE_ERAS_G7)

# ===========================================================================
# Write versioned diagnostics
# ===========================================================================
banner("Writing nt2010 design diagnostics")
nt_write(rbind(full$feasibility, cc$feasibility)[, c("spec","status","feasible","reason",
  "firm_converged","inv_converged","max_smd_constrained","max_smd_omitted","max_smd_all",
  "max_stack_mass_discrepancy","n_treated","n_control","n_units")],
  "feasibility_decisions.csv")
nt_write(rbind(full$balance, cc$balance), "balance_all_covariates.csv")
nt_write(rbind(full$concentration, cc$concentration), "weight_concentration.csv")
nt_write(rbind(full$stack_mass, cc$stack_mass), "stack_mass.csv")
nt_write(rbind(full$quantiles, cc$quantiles), "weighted_quantiles.csv")
nt_write(rbind(full$metrics, cc$metrics), "design_comparison.csv")
nt_write(rbind(full$era, cc$era), "era_balance.csv")
nt_write(rbind(full$cohort, cc$cohort), "cohort_balance.csv")
if (!is.null(full$p5_scales)) nt_write(full$p5_scales, "p5_nt2010_stack_scale_factors.csv")
if (!is.null(cc$p5_scales))   nt_write(cc$p5_scales,   "p5_cc9408_stack_scale_factors.csv")

# treated mass by cohort (from stack_mass, treated rows)
tm <- rbind(full$stack_mass, cc$stack_mass)
tm <- tm[, c("spec", "stack", "treated_mass", "control_mass", "relative_discrepancy")]
nt_write(tm, "treated_mass_by_cohort.csv")

options(width = 220)
cat("\n== feasibility summary ==\n")
print(rbind(full$feasibility, cc$feasibility)[, c("spec", "status", "reason")])
banner("11o DONE -- nt2010 P0H5/P5 weights + diagnostics; no outcomes, no estimation")

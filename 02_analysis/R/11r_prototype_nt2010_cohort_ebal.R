# ============================================================================
# 11r_prototype_nt2010_cohort_ebal.R -- Package 2B.0
# ----------------------------------------------------------------------------
# PROTOTYPE: P0H5 cohort-specific two-stage entropy balancing for cohort 2009
# ONLY. Solves the same two-stage hierarchy (firm then inventor) WITHIN the 2009
# cohort, omitting factor(stack) (constant). Isolated implementation -- the shared
# two_stage_ebal() is NOT modified, so the frozen global design stays reproducible.
#
# Design-only. No sample/cleanliness/covariate/threshold change. No outcomes, no
# citation work, no DiD. Writes only versioned 2B.0 diagnostics + a clearly
# labelled DIAGNOSTIC weight parquet (never a production path).
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))   # banner, ebal_max_meandiff, model_matrix_cols, ess, standardize_continuous, smd_weighted, weight_quantile_diag
source(file.path(BASE, "R", "11i_robustness_config.R"))
for (pkg in c("DBI", "duckdb", "WeightIt"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({ library(DBI); library(duckdb); library(WeightIt) })
set.seed(SEED)

COHORT <- 2009L
MAXIT  <- 200000L
RELTOL <- 1e-12
sqlp   <- function(p) gsub("\\\\", "/", p)
apath  <- function(name) paste0(NT2010_AUDIT_PREFIX, "_", name)
fail_infeasible <- function(msg) { message("[2B.0 INFEASIBLE] ", msg); PROTO_STATUS <<- "INFEASIBLE";
  PROTO_REASON <<- c(PROTO_REASON, msg) }
PROTO_STATUS <- "FEASIBLE"; PROTO_REASON <- character(0)

# per-stage resource logging
res_log <- list()
stage_time <- function(label, expr) {
  gc(reset = TRUE); t0 <- Sys.time()
  val <- force(expr)
  el <- as.numeric(Sys.time() - t0, units = "secs")
  mm <- sum(gc()[, "max used"] * c(56, 8)) / 1e6
  res_log[[label]] <<- data.frame(stage = label, elapsed_s = el, peak_mem_mb = mm)
  message(sprintf("  [%s] %.1fs, ~%.0f MB", label, el, mm))
  val
}

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='6GB'"); dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sqlp(DUCKDB_TMP)))

banner(sprintf("2B.0 PROTOTYPE -- P0H5 cohort-specific ebal, cohort %d only", COHORT))

# ===========================================================================
# 1. Load ONLY the 2009 cohort (project required columns in DuckDB)
# ===========================================================================
units <- stage_time("roster_load", {
  sel <- paste(c("codinv", "focal_deal_id", "underlying_group_id", "stack", "treated",
                 "arm", "qualifying_gap", "modal_family", FIRM_COVARS, INV_COVARS), collapse = ", ")
  u <- dbGetQuery(con, sprintf("SELECT %s FROM read_parquet('%s') WHERE stack = %d",
                               sel, sqlp(NT2010_ANALYSIS_UNITS_PARQUET), COHORT))
  u$codinv <- as.numeric(u$codinv); u$stack <- as.integer(u$stack)
  u$treated <- as.integer(u$treated); u$underlying_group_id <- as.numeric(u$underlying_group_id)
  # n_qualifying per (underlying_group_id, stack) cell -- identical to global prepare_units
  cell <- paste(u$underlying_group_id, u$stack, sep = "|")
  u$n_qualifying_inventors <- as.integer(table(cell)[cell])
  # factors exactly as the global design (droplevels handled later per stage)
  u$qualifying_gap_cat <- factor(pmin(u$qualifying_gap, 3L), levels = 0:3,
                                 labels = c("gap0", "gap1", "gap2", "gap3plus"))
  u$modal_family <- factor(u$modal_family, levels = TECH_FAMILIES)
  miss <- rowSums(is.na(u[, c(FIRM_COVARS, INV_COVARS)])) > 0
  if (any(miss)) { message("  dropping ", sum(miss), " covariate-missing units (as global)."); u <- u[!miss, ] }
  u
})
message(sprintf("Loaded 2009: %d units (treated=%d control=%d), %d control firms",
        nrow(units), sum(units$treated == 1L), sum(units$treated == 0L),
        length(unique(units$underlying_group_id[units$treated == 0L]))))

# existing GLOBAL P0H5 weights, restricted to 2009 (for side-by-side + key check)
glob <- dbGetQuery(con, sprintf(
  "SELECT codinv, underlying_group_id, stack, treated, final_weight, n_qualifying_inventors
   FROM read_parquet('%s') WHERE stack = %d", sqlp(P0H5_NT2010_WEIGHTS_PARQUET), COHORT))
glob$codinv <- as.numeric(glob$codinv); glob$treated <- as.integer(glob$treated)

# identical roster keys/counts
k_new <- paste(units$codinv, units$treated); k_old <- paste(glob$codinv, glob$treated)
keys_identical <- setequal(k_new, k_old) && length(k_new) == length(k_old)
message(sprintf("Roster key match vs global-2009: identical=%s (new=%d old=%d)",
                keys_identical, length(k_new), length(k_old)))
if (!keys_identical) fail_infeasible("2009 roster keys differ from the global P0H5 2009 slice.")

# ===========================================================================
# 2. Structural / support column audit (remove ONLY mechanical redundancy)
# ===========================================================================
banner("Structural column audit")
removed <- data.frame(stage = character(0), column = character(0), reason = character(0))
num_covars <- FULL_NUMERIC_COVARS
sd_all <- sapply(num_covars, function(v) stats::sd(units[[v]]))
drop_num <- names(sd_all)[!is.finite(sd_all) | sd_all == 0]         # constant across BOTH arms
for (v in drop_num) removed <- rbind(removed, data.frame(stage = "numeric", column = v,
  reason = "zero variance across both arms (no balance restriction)"))
firm_covars <- setdiff(FIRM_COVARS, drop_num)
inv_covars  <- setdiff(INV_COVARS,  drop_num)
cont_covars <- setdiff(FULL_CONT_COVARS, drop_num)

# factors: drop empty levels; exclude a factor with <2 realised levels
inv_factors <- c()
for (f in INV_FACTOR_COVARS) {
  units[[f]] <- droplevels(units[[f]])
  if (nlevels(units[[f]]) < 2L) {
    removed <- rbind(removed, data.frame(stage = "factor", column = f,
      reason = sprintf("only %d realised level(s) in cohort (no balance restriction)", nlevels(units[[f]]))))
  } else inv_factors <- c(inv_factors, f)
}
# factor-level support: a realised treated level with no control observation is unsupportable
for (f in inv_factors) {
  tl <- table(units[[f]][units$treated == 1L]); cl <- table(units[[f]][units$treated == 0L])
  bad <- names(tl)[tl > 0 & (is.na(cl[names(tl)]) | cl[names(tl)] == 0)]
  for (lv in bad) fail_infeasible(sprintf("factor %s level '%s' present in treated but absent in controls (no support).", f, lv))
}
# numeric support: treated mean must lie within the control value range (ATT convex-hull necessity)
for (v in c(firm_covars, inv_covars)) {
  tm <- mean(units[[v]][units$treated == 1L]); cr <- range(units[[v]][units$treated == 0L])
  if (tm < cr[1] - 1e-9 || tm > cr[2] + 1e-9)
    fail_infeasible(sprintf("treated mean of %s (%.4g) outside control range [%.4g, %.4g] (no support).", v, tm, cr[1], cr[2]))
}
write.csv(removed, apath("2b0_structural_removed_columns.csv"), row.names = FALSE)
message(sprintf("Removed %d mechanically-redundant column(s); firm=%d inv=%d factors=%s",
                nrow(removed), length(firm_covars), length(inv_covars), paste(inv_factors, collapse = ",")))
if (identical(PROTO_STATUS, "INFEASIBLE")) {
  write.csv(data.frame(status = PROTO_STATUS, reason = PROTO_REASON), apath("2b0_status.csv"), row.names = FALSE)
  stop("[2B.0] Infeasible on support before estimation; see 2b0_status.csv", call. = FALSE)
}

# ===========================================================================
# 3. Isolated cohort two-stage ebal (mirrors two_stage_ebal WITHOUT factor(stack))
# ===========================================================================
cohort_two_stage_ebal <- function(units, firm_key_cols, firm_covars, inv_covars, inv_factors,
                                  cont_covars, maxit, reltol) {
  for (v in intersect(cont_covars, c(firm_covars, inv_covars)))
    units[[v]] <- standardize_continuous(units[[v]])
  units$.fk <- do.call(paste, c(units[firm_key_cols], sep = "|"))
  firm_data <- unique(units[, c(".fk", firm_key_cols, "treated", "stack", firm_covars, "n_qualifying_inventors")])
  stopifnot(!anyDuplicated(firm_data$.fk))
  firm_form <- stats::reformulate(firm_covars, response = "treated")            # NO factor(stack)
  W_firm <- WeightIt::weightit(firm_form, data = firm_data, method = "ebal", estimand = "ATT",
                               s.weights = firm_data$n_qualifying_inventors, maxit = maxit, reltol = reltol)
  firm_data$firm_multiplier <- as.numeric(W_firm$weights)
  units$firm_multiplier <- firm_data$firm_multiplier[match(units$.fk, firm_data$.fk)]
  units$inventor_base_weight <- units$firm_multiplier
  inv_form <- stats::reformulate(c(firm_covars, inv_covars, inv_factors), response = "treated")  # NO factor(stack)
  W_inv <- WeightIt::weightit(inv_form, data = units, method = "ebal", estimand = "ATT",
                              base.weights = units$inventor_base_weight, maxit = maxit, reltol = reltol)
  units$final_weight <- as.numeric(W_inv$weights)
  list(units = units, firm_data = firm_data, W_firm = W_firm, W_inv = W_inv,
       firm_form = firm_form, inv_form = inv_form)
}

fit <- stage_time("firm+inventor_balance", {
  cohort_two_stage_ebal(units, c("underlying_group_id", "stack"),
                        firm_covars, inv_covars, inv_factors, cont_covars, MAXIT, RELTOL)
})
u <- fit$units; w <- u$final_weight

# ===========================================================================
# 4. Diagnostics + gates (side-by-side old global vs new cohort-specific)
# ===========================================================================
diag_out <- stage_time("diagnostics", {
  # full-spec pooled SD per covariate (from the Package-2A audit; full-spec constant)
  cb <- utils::read.csv(apath("2a_conditional_balance.csv"), stringsAsFactors = FALSE)
  cb <- cb[cb$spec == "P0H5_nt2010", ]
  pooled_sd <- tapply(cb$pooled_full_sd, cb$covariate, function(x) x[1])

  wm <- function(x, ww) sum(ww * x) / sum(ww)
  wvar <- function(x, ww) { m <- wm(x, ww); sum(ww * (x - m)^2) / sum(ww) }
  balance_rows <- function(units, ww, label) {
    tt <- units$treated == 1L; cc <- units$treated == 0L
    do.call(rbind, lapply(FULL_NUMERIC_COVARS, function(v) {
      mt <- wm(units[[v]][tt], ww[tt]); mc <- wm(units[[v]][cc], ww[cc])
      sdt <- sqrt(wvar(units[[v]][tt], ww[tt]))
      raw <- mt - mc
      data.frame(weights = label, covariate = v, treated_wmean = mt, control_wmean = mc,
        raw_diff = raw, smd_treated_sd = if (is.finite(sdt) && sdt > 0) raw / sdt else NA_real_,
        denom_collapse = !(is.finite(sdt) && sdt > 0),
        smd_fullpooled = raw / pooled_sd[v], constrained = v %in% c(firm_covars, inv_covars),
        stringsAsFactors = FALSE)
    }))
  }
  # align global weights to the same unit order (u and the raw `units` share row order)
  gw <- glob$final_weight[match(paste(u$codinv, u$treated), paste(glob$codinv, glob$treated))]
  # IMPORTANT: balance on the RAW covariates (`units`); `u`=fit$units has standardized
  # continuous covars (mutated inside the ebal). Balancing standardized means to 0
  # implies raw means balanced too, so the NEW raw SMDs are ~0; the OLD raw SMDs then
  # match the Package-2A scale for a like-for-like comparison.
  bal_new <- balance_rows(units, w, "cohort_specific_2009")
  bal_old <- balance_rows(units, gw, "global_pooled_2009")
  bal <- rbind(bal_old, bal_new)

  # firm/inventor raw model-matrix max mean diff (convergence, collapse-robust)
  firm_mass <- fit$firm_data$n_qualifying_inventors * fit$firm_data$firm_multiplier
  firm_md <- ebal_max_meandiff(model_matrix_cols(fit$firm_form, fit$firm_data), fit$firm_data$treated, firm_mass)
  inv_md  <- ebal_max_meandiff(model_matrix_cols(fit$inv_form, u), u$treated, w)

  # concentration / ESS (control positive weights)
  cwt <- w[u$treated == 0L]; cfirm <- u$underlying_group_id[u$treated == 0L]
  pos <- cwt > 0
  firm_mass_ctl <- tapply(cwt[pos], cfirm[pos], sum)
  fm_tot <- sum(firm_mass_ctl); fm_sorted <- sort(as.numeric(firm_mass_ctl), decreasing = TRUE)
  inv_ess <- ess(cwt[pos]); firm_ess <- ess(as.numeric(firm_mass_ctl))
  max_share <- fm_sorted[1] / fm_tot; top5_share <- sum(head(fm_sorted, 5)) / fm_tot

  constrained_pooled_smd <- abs(bal_new$smd_fullpooled[bal_new$constrained])
  treated_mass <- sum(w[u$treated == 1L]); control_mass <- sum(cwt)
  mass_disc <- abs(control_mass - treated_mass) / treated_mass

  gates <- data.frame(
    gate = c("treated_weights_equal_one", "weights_finite_nonneg",
             "firm_stage_raw_meandiff_le_1e-4", "inv_stage_raw_meandiff_le_1e-4",
             "mass_discrepancy_le_STACK_MASS_TOL", "max_fullpooled_smd_constrained_le_0.05",
             "firm_ess_ge_50", "max_firm_share_le_0.10"),
    value = c(max(abs(w[u$treated == 1L] - 1)), as.numeric(all(is.finite(w) & w >= -1e-12)),
              firm_md, inv_md, mass_disc, max(constrained_pooled_smd), firm_ess, max_share),
    threshold = c(1e-8, 1, EBAL_CONSTRAINT_TOL, 1e-4, STACK_MASS_TOL, ROBUST_MAX_SMD_CONSTRAINED, ROBUST_MIN_ESS, ROBUST_MAX_SHARE),
    pass = c(max(abs(w[u$treated == 1L] - 1)) < 1e-8, all(is.finite(w) & w >= -1e-12),
             firm_md <= EBAL_CONSTRAINT_TOL, inv_md <= 1e-4, mass_disc <= STACK_MASS_TOL,
             max(constrained_pooled_smd) <= ROBUST_MAX_SMD_CONSTRAINED,
             firm_ess >= ROBUST_MIN_ESS, max_share <= ROBUST_MAX_SHARE),
    stringsAsFactors = FALSE)

  quant <- weight_quantile_diag(cwt[pos])
  support <- data.frame(
    metric = c("treated_inventors", "treated_mass", "control_mass",
               "control_pos_inventors", "control_pos_firms",
               "control_inventor_ess", "control_firm_ess", "max_firm_share", "top5_firm_share"),
    value = c(sum(u$treated == 1L), treated_mass, control_mass, sum(pos), length(firm_mass_ctl),
              inv_ess, firm_ess, max_share, top5_share))
  conv <- data.frame(stage = c("firm", "inventor"),
    weightit_converged = c(isTRUE(fit$W_firm$info$converged), isTRUE(fit$W_inv$info$converged)),
    raw_meandiff = c(firm_md, inv_md))
  list(bal = bal, gates = gates, support = support, quant = quant, conv = conv,
       final = u[, c("codinv", "underlying_group_id", "stack", "treated", "final_weight", "n_qualifying_inventors")])
})

# ---- persist versioned diagnostics + labelled DIAGNOSTIC weight parquet ----
write.csv(diag_out$bal,     apath("2b0_balance_old_vs_new.csv"), row.names = FALSE)
write.csv(diag_out$gates,   apath("2b0_gates.csv"), row.names = FALSE)
write.csv(diag_out$support, apath("2b0_support.csv"), row.names = FALSE)
write.csv(diag_out$quant,   apath("2b0_weight_quantiles.csv"), row.names = FALSE)
write.csv(diag_out$conv,    apath("2b0_solver_convergence.csv"), row.names = FALSE)
write.csv(do.call(rbind, res_log), apath("2b0_runtime_resource_log.csv"), row.names = FALSE)

proto_parq <- file.path(DERIVED_PAR, "main_did_v1_nt2010_p0h5_cohort2009_PROTOTYPE_weights.parquet")
duckdb::duckdb_register(con, "proto_out", diag_out$final)
dbExecute(con, sprintf("COPY (SELECT * FROM proto_out) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", sqlp(proto_parq)))
duckdb::duckdb_unregister(con, "proto_out")

PROTO_STATUS <- if (all(diag_out$gates$pass)) "PASS" else "FAIL"
write.csv(data.frame(status = PROTO_STATUS,
  reason = if (PROTO_STATUS == "PASS") "all gates passed"
           else paste(diag_out$gates$gate[!diag_out$gates$pass], collapse = "; ")),
  apath("2b0_status.csv"), row.names = FALSE)

banner("2B.0 PROTOTYPE RESULT")
print(diag_out$gates)
message("\nOld (global-pooled) vs New (cohort-specific) constrained max |full-pooled SMD|:")
message(sprintf("  OLD: %.4f | NEW: %.4f",
  max(abs(diag_out$bal$smd_fullpooled[diag_out$bal$weights == "global_pooled_2009" &
    diag_out$bal$constrained])),
  max(abs(diag_out$bal$smd_fullpooled[diag_out$bal$weights == "cohort_specific_2009" &
    diag_out$bal$constrained]))))
message(sprintf("STATUS: %s", PROTO_STATUS))
banner("11r DONE -- 2B.0 prototype (cohort 2009 only); no outcomes, no DiD")

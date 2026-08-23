# ============================================================================
# 11t_prototype_nt2010_era_ebal.R -- Package 2B.2
# ----------------------------------------------------------------------------
# PROTOTYPE: uniform ERA-level P0H5 entropy balancing for the pre-specified
# never-target era 1994-1999 (6 cohorts). Balances covariate moments across the
# era WITH factor(stack) in both stages (so treated/control mass is preserved per
# cohort), retaining each cohort's treated-inventor mass. Validates conditional
# balance/concentration INSIDE every constituent cohort.
#
# Era-level balancing == the shared two_stage_ebal (which already includes
# factor(stack)) applied to the era subset -- so the shared solver is reused
# UNCHANGED; no pooled implementation is modified. Design-only: no outcomes,
# citations, annual states, or DiD. Writes only a labelled diagnostic parquet +
# versioned 2B.2 CSVs. Never touches a production weight file.
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "archive", "main_did_v1", "11a_main_design_config.R"))
source(file.path(BASE, "R", "archive", "main_did_v1", "11_main_design_utils.R"))   # two_stage_ebal (shared, unchanged), banner, ebal_max_meandiff, ...
source(file.path(BASE, "R", "archive", "main_did_v1", "11i_robustness_config.R"))
for (pkg in c("DBI", "duckdb", "WeightIt"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({ library(DBI); library(duckdb); library(WeightIt) })
set.seed(SEED)

ERA <- c(1994L, 1999L)
ERA_COHORTS <- ERA[1]:ERA[2]
MAXIT  <- 200000L
RELTOL <- 1e-12
sqlp  <- function(p) gsub("\\\\", "/", p)
apath <- function(name) paste0(NT2010_AUDIT_PREFIX, "_", name)
res_log <- list()
stage_time <- function(label, expr) {
  gc(reset = TRUE); t0 <- Sys.time(); val <- force(expr)
  el <- as.numeric(Sys.time() - t0, units = "secs"); mm <- sum(gc()[, "max used"] * c(56, 8)) / 1e6
  res_log[[label]] <<- data.frame(stage = label, elapsed_s = el, peak_mem_mb = mm)
  message(sprintf("  [%s] %.1fs ~%.0fMB", label, el, mm)); val
}

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='6GB'"); dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sqlp(DUCKDB_TMP)))

banner("2B.2 -- ERA-LEVEL P0H5 PROTOTYPE (1994-1999)")

# full-spec pooled SD per covariate (Package 2A; read-only)
cb2a <- utils::read.csv(apath("2a_conditional_balance.csv"), stringsAsFactors = FALSE)
cb2a <- cb2a[cb2a$spec == "P0H5_nt2010", ]
POOLED_SD <- tapply(cb2a$pooled_full_sd, cb2a$covariate, function(x) x[1])
# 2A worst full-pooled cohort SMD per cohort (all 14 numeric covars are constrained in P0H5)
cb2a_coh <- cb2a[cb2a$level == "cohort", ]
a2_worst <- tapply(abs(cb2a_coh$smd_fullpooled), as.character(cb2a_coh$group), max)

# ===========================================================================
# CHEAP SUPPORT MAP (all 17 cohorts; NO weighting solve)
# ===========================================================================
banner("Cheap support map (descriptive; no cohort solves)")
tfc <- dbGetQuery(con, sprintf(   # distinct treated firm cells + covariates
  "SELECT DISTINCT stack, underlying_group_id, %s FROM read_parquet('%s') WHERE treated=1",
  paste(FIRM_COVARS, collapse = ", "), sqlp(NT2010_ANALYSIS_UNITS_PARQUET)))
tinv <- dbGetQuery(con, sprintf(
  "SELECT stack, COUNT(*) treated_inventors, COUNT(DISTINCT focal_deal_id) treated_deals
   FROM read_parquet('%s') WHERE treated=1 GROUP BY stack", sqlp(NT2010_ANALYSIS_UNITS_PARQUET)))
crange <- dbGetQuery(con, sprintf(
  "SELECT stack, COUNT(*) control_inventors, COUNT(DISTINCT underlying_group_id) control_firms, %s
   FROM read_parquet('%s') WHERE treated=0 GROUP BY stack",
  paste(sprintf("MIN(%1$s) min_%1$s, MAX(%1$s) max_%1$s", c(FIRM_COVARS, INV_COVARS)), collapse = ", "),
  sqlp(NT2010_ANALYSIS_UNITS_PARQUET)))
tmean <- dbGetQuery(con, sprintf(
  "SELECT stack, %s FROM read_parquet('%s') WHERE treated=1 GROUP BY stack",
  paste(sprintf("AVG(%1$s) tm_%1$s", c(FIRM_COVARS, INV_COVARS)), collapse = ", "),
  sqlp(NT2010_ANALYSIS_UNITS_PARQUET)))

support_map <- do.call(rbind, lapply(sort(unique(tfc$stack)), function(g) {
  cells <- tfc[tfc$stack == g, FIRM_COVARS, drop = FALSE]
  mm <- stats::model.matrix(stats::reformulate(FIRM_COVARS), data = tfc[tfc$stack == g, ])
  rk <- qr(mm)$rank
  cr <- crange[crange$stack == g, ]; tm <- tmean[tmean$stack == g, ]
  # treated numeric means within control ranges?
  in_range <- all(sapply(c(FIRM_COVARS, INV_COVARS), function(v)
    tm[[paste0("tm_", v)]] >= cr[[paste0("min_", v)]] - 1e-9 &&
    tm[[paste0("tm_", v)]] <= cr[[paste0("max_", v)]] + 1e-9))
  data.frame(cohort = g,
    treated_inventors = tinv$treated_inventors[tinv$stack == g],
    treated_deals = tinv$treated_deals[tinv$stack == g],
    treated_firm_cells = nrow(cells),
    control_inventors = cr$control_inventors, control_firms = cr$control_firms,
    firm_mm_ncol = ncol(mm), firm_mm_rank = rk, firm_rank_deficient = rk < ncol(mm),
    treated_means_in_control_range = in_range,
    a2_worst_fullpooled_smd = as.numeric(a2_worst[as.character(g)]))
}))
write.csv(support_map, apath("2b2_support_map.csv"), row.names = FALSE)
print(support_map[, c("cohort","treated_deals","treated_firm_cells","firm_mm_ncol","firm_mm_rank",
                      "firm_rank_deficient","a2_worst_fullpooled_smd")])

# ===========================================================================
# ERA SOLVE (1994-1999): shared two_stage_ebal WITH factor(stack)
# ===========================================================================
units <- stage_time("era_load", {
  sel <- paste(c("codinv", "focal_deal_id", "underlying_group_id", "stack", "treated",
                 "arm", "qualifying_gap", "modal_family", FIRM_COVARS, INV_COVARS), collapse = ", ")
  u <- dbGetQuery(con, sprintf("SELECT %s FROM read_parquet('%s') WHERE stack BETWEEN %d AND %d",
                               sel, sqlp(NT2010_ANALYSIS_UNITS_PARQUET), ERA[1], ERA[2]))
  u$codinv <- as.numeric(u$codinv); u$stack <- as.integer(u$stack)
  u$treated <- as.integer(u$treated); u$underlying_group_id <- as.numeric(u$underlying_group_id)
  u$focal_deal_id <- as.integer(u$focal_deal_id)
  if (any(rowSums(is.na(u[, c(FIRM_COVARS, INV_COVARS)])) > 0)) stop("[2B.2] covariate-missing rows in era.", call. = FALSE)
  cell <- paste(u$underlying_group_id, u$stack, sep = "|")
  u$n_qualifying_inventors <- as.integer(table(cell)[cell])
  u$qualifying_gap_cat <- factor(pmin(u$qualifying_gap, 3L), levels = 0:3, labels = c("gap0","gap1","gap2","gap3plus"))
  u$modal_family <- factor(u$modal_family, levels = TECH_FAMILIES)
  u
})
message(sprintf("Era 1994-1999: %d units (treated=%d control=%d), cohorts=%s",
        nrow(units), sum(units$treated == 1L), sum(units$treated == 0L),
        paste(sort(unique(units$stack)), collapse = ",")))

# structural / support audit (verbatim 2B.0/2B.1 rules), factor droplevels
structural_audit <- function(units) {
  removed <- data.frame(stage = character(0), column = character(0), reason = character(0)); reasons <- character(0)
  sd_all <- sapply(FULL_NUMERIC_COVARS, function(v) stats::sd(units[[v]]))
  drop_num <- names(sd_all)[!is.finite(sd_all) | sd_all == 0]
  for (v in drop_num) removed <- rbind(removed, data.frame(stage = "numeric", column = v,
    reason = "zero variance across both arms"))
  firm_covars <- setdiff(FIRM_COVARS, drop_num); inv_covars <- setdiff(INV_COVARS, drop_num)
  cont_covars <- setdiff(FULL_CONT_COVARS, drop_num); inv_factors <- c()
  for (f in INV_FACTOR_COVARS) {
    units[[f]] <- droplevels(units[[f]])
    if (nlevels(units[[f]]) < 2L) removed <- rbind(removed, data.frame(stage = "factor", column = f,
      reason = sprintf("only %d realised level(s)", nlevels(units[[f]])))) else inv_factors <- c(inv_factors, f)
  }
  for (f in inv_factors) {  # factor-level support: treated level with control support
    tl <- table(units[[f]][units$treated == 1L]); cl <- table(units[[f]][units$treated == 0L])
    bad <- names(tl)[tl > 0 & (is.na(cl[names(tl)]) | cl[names(tl)] == 0)]
    for (lv in bad) reasons <- c(reasons, sprintf("factor %s level '%s' unsupported", f, lv))
  }
  list(units = units, removed = removed, firm_covars = firm_covars, inv_covars = inv_covars,
       cont_covars = cont_covars, inv_factors = inv_factors, support_reasons = reasons)
}
sa <- structural_audit(units); units <- sa$units
write.csv(if (nrow(sa$removed)) cbind(era = "1994-1999", sa$removed) else
  data.frame(era = "1994-1999", stage = NA, column = NA, reason = "none removed"),
  apath("2b2_structural_removed_columns.csv"), row.names = FALSE)
if (length(sa$support_reasons) > 0) {
  write.csv(data.frame(era = "1994-1999", reason = sa$support_reasons), apath("2b2_support_failure.csv"), row.names = FALSE)
  stop(sprintf("[2B.2] era has unsupported treated moments: %s", paste(sa$support_reasons, collapse = "; ")), call. = FALSE)
}
constrained <- c(sa$firm_covars, sa$inv_covars)

fit <- stage_time("firm+inventor_balance", {
  two_stage_ebal(units, c("underlying_group_id", "stack"), sa$firm_covars, sa$inv_covars,
                 sa$inv_factors, sa$cont_covars, maxit = MAXIT, reltol = RELTOL)  # includes factor(stack)
})
u <- fit$units; w <- u$final_weight

# ===========================================================================
# DIAGNOSTICS: era-level gates + within-cohort validation
# ===========================================================================
diag_res <- stage_time("diagnostics", {
  wm <- function(x, ww) sum(ww * x) / sum(ww)
  wvar <- function(x, ww) { m <- wm(x, ww); sum(ww * (x - m)^2) / sum(ww) }
  # balance on RAW covars (units); u == fit$units has standardized cont covars
  balance_rows <- function(cohorts, level, glab) {
    idx <- units$stack %in% cohorts; tt <- idx & units$treated == 1L; cc <- idx & units$treated == 0L
    do.call(rbind, lapply(FULL_NUMERIC_COVARS, function(v) {
      mt <- wm(units[[v]][tt], w[tt]); mc <- wm(units[[v]][cc], w[cc]); sdt <- sqrt(wvar(units[[v]][tt], w[tt]))
      raw <- mt - mc
      data.frame(level = level, group = glab, covariate = v, raw_diff = raw,
        smd_treated_sd = if (is.finite(sdt) && sdt > 0) raw / sdt else NA_real_,
        denom_collapse = !(is.finite(sdt) && sdt > 0),
        smd_fullpooled = raw / POOLED_SD[v], constrained = v %in% constrained, stringsAsFactors = FALSE)
    }))
  }
  conc <- function(cohorts) {
    idx <- units$stack %in% cohorts & units$treated == 0L & w > 0
    fm <- tapply(w[idx], units$underlying_group_id[idx], sum); tot <- sum(fm); s <- sort(as.numeric(fm), TRUE)
    list(firm_ess = if (tot > 0) tot^2 / sum(fm^2) else 0, n_firms = length(fm),
         max_share = s[1] / tot, top5 = sum(head(s, 5)) / tot,
         pos_inv = sum(idx), inv_ess = { ww <- w[idx]; sum(ww)^2 / sum(ww^2) })
  }
  # era-level
  firm_md <- ebal_max_meandiff(model_matrix_cols(fit$firm_form, fit$firm_data), fit$firm_data$treated,
    fit$firm_data$n_qualifying_inventors * fit$firm_data$firm_multiplier)
  inv_md <- ebal_max_meandiff(model_matrix_cols(fit$inv_form, u), u$treated, w)
  bal_era <- balance_rows(ERA_COHORTS, "era", "1994-1999")
  ce <- conc(ERA_COHORTS)
  # per-cohort mass discrepancy (factor(stack) should preserve each)
  massd <- sapply(ERA_COHORTS, function(g) {
    tm <- sum(w[units$stack == g & units$treated == 1L]); cm <- sum(w[units$stack == g & units$treated == 0L])
    abs(cm - tm) / tm })
  era_constr_max <- max(abs(bal_era$smd_fullpooled[bal_era$constrained]))
  era_gates <- data.frame(scope = "era", gate = c("treated_w_eq_1","finite_nonneg","firm_raw_meandiff",
    "inv_raw_meandiff","era_constrained_max_fullpooled_smd","per_cohort_mass_discrepancy","firm_ess","max_firm_share"),
    value = c(max(abs(w[u$treated == 1L] - 1)), as.numeric(all(is.finite(w) & w >= -1e-12)), firm_md, inv_md,
              era_constr_max, max(massd), ce$firm_ess, ce$max_share),
    threshold = c(1e-8, 1, EBAL_CONSTRAINT_TOL, 1e-4, ROBUST_MAX_SMD_CONSTRAINED, STACK_MASS_TOL, ROBUST_MIN_ESS, ROBUST_MAX_SHARE))
  era_gates$pass <- c(max(abs(w[u$treated == 1L] - 1)) < 1e-8, all(is.finite(w) & w >= -1e-12),
    firm_md <= EBAL_CONSTRAINT_TOL, inv_md <= 1e-4, era_constr_max <= ROBUST_MAX_SMD_CONSTRAINED,
    max(massd) <= STACK_MASS_TOL, ce$firm_ess >= ROBUST_MIN_ESS, ce$max_share <= ROBUST_MAX_SHARE)

  # within-cohort validation
  wc_bal <- do.call(rbind, lapply(ERA_COHORTS, function(g) cbind(cohort = g, balance_rows(g, "cohort", as.character(g)))))
  wc <- do.call(rbind, lapply(ERA_COHORTS, function(g) {
    b <- balance_rows(g, "cohort", as.character(g)); cc <- conc(g)
    tm <- sum(w[units$stack == g & units$treated == 1L]); cm <- sum(w[units$stack == g & units$treated == 0L])
    cmax <- max(abs(b$smd_fullpooled[b$constrained]))
    data.frame(cohort = g, constrained_max_fullpooled_smd = cmax, firm_ess = cc$firm_ess,
      max_firm_share = cc$max_share, top5_firm_share = cc$top5, control_pos_inventors = cc$pos_inv,
      control_pos_firms = cc$n_firms, treated_mass = tm, control_mass = cm,
      mass_discrepancy = abs(cm - tm) / tm,
      pass_smd = cmax <= ROBUST_MAX_SMD_CONSTRAINED, pass_ess = cc$firm_ess >= ROBUST_MIN_ESS,
      pass_share = cc$max_share <= ROBUST_MAX_SHARE, pass_mass = abs(cm - tm) / tm <= STACK_MASS_TOL)
  }))
  wc$pass_all <- wc$pass_smd & wc$pass_ess & wc$pass_share & wc$pass_mass
  conv <- data.frame(stage = c("firm","inventor"),
    weightit_converged = c(isTRUE(fit$W_firm$info$converged), isTRUE(fit$W_inv$info$converged)),
    raw_meandiff = c(firm_md, inv_md))
  wq <- weight_quantile_diag(w[u$treated == 0L & w > 0])
  list(era_gates = era_gates, bal_era = bal_era, wc = wc, wc_bal = wc_bal, conv = conv, wq = wq,
       final = u[, c("codinv","underlying_group_id","stack","treated","final_weight","n_qualifying_inventors","focal_deal_id")])
})

# ===========================================================================
# COMPARISON: old global vs cohort-specific (1994,1995) vs era
# ===========================================================================
# old-global within-cohort constrained max full-pooled (from 2A)
old_wc <- tapply(abs(cb2a_coh$smd_fullpooled), cb2a_coh$group, max)
# cohort-specific 1994/1995 firm ESS (1994 from shard; 1995 from FAILED gates)
cs_rows <- data.frame(cohort = integer(0), source = character(0), constrained_max_fullpooled_smd = numeric(0), firm_ess = numeric(0))
sh94 <- file.path(P0H5_COHORT_EBAL_SHARD_DIR, "cohort_1994.parquet")
if (file.exists(sh94)) {
  fm <- dbGetQuery(con, sprintf("SELECT underlying_group_id, SUM(final_weight) m FROM read_parquet('%s') WHERE treated=0 AND final_weight>0 GROUP BY underlying_group_id", sqlp(sh94)))
  tot <- sum(fm$m); cs_rows <- rbind(cs_rows, data.frame(cohort = 1994L, source = "cohort_specific",
    constrained_max_fullpooled_smd = NA_real_, firm_ess = tot^2 / sum(fm$m^2)))
}
f95 <- apath("2b1_cohort_1995_FAILED_gates.csv")
if (file.exists(f95)) { g95 <- utils::read.csv(f95); cs_rows <- rbind(cs_rows, data.frame(cohort = 1995L,
  source = "cohort_specific", constrained_max_fullpooled_smd = g95$value[g95$gate == "max_fullpooled_smd_constrained"],
  firm_ess = g95$value[g95$gate == "firm_ess"])) }
comparison <- rbind(
  data.frame(cohort = ERA_COHORTS, source = "old_global",
    constrained_max_fullpooled_smd = as.numeric(old_wc[as.character(ERA_COHORTS)]), firm_ess = NA_real_),
  cs_rows,
  data.frame(cohort = diag_res$wc$cohort, source = "era_1994_1999",
    constrained_max_fullpooled_smd = diag_res$wc$constrained_max_fullpooled_smd, firm_ess = diag_res$wc$firm_ess))
comparison <- comparison[order(comparison$cohort, comparison$source), ]

# ===========================================================================
# WRITE diagnostics + labelled diagnostic parquet
# ===========================================================================
proto_parq <- file.path(DERIVED_PAR, "main_did_v1_nt2010_p0h5_era9499_PROTOTYPE_weights.parquet")
duckdb::duckdb_register(con, "era_out", diag_res$final)
dbExecute(con, sprintf("COPY (SELECT * FROM era_out) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", sqlp(proto_parq)))
duckdb::duckdb_unregister(con, "era_out")

write.csv(diag_res$era_gates, apath("2b2_era_gates.csv"), row.names = FALSE)
write.csv(diag_res$wc, apath("2b2_within_cohort_gates.csv"), row.names = FALSE)
write.csv(diag_res$wc_bal, apath("2b2_within_cohort_balance.csv"), row.names = FALSE)
write.csv(diag_res$bal_era, apath("2b2_era_balance.csv"), row.names = FALSE)
write.csv(diag_res$conv, apath("2b2_solver_convergence.csv"), row.names = FALSE)
write.csv(cbind(scope = "era_control", diag_res$wq), apath("2b2_weight_quantiles.csv"), row.names = FALSE)
write.csv(comparison, apath("2b2_comparison_old_vs_cohort_vs_era.csv"), row.names = FALSE)
write.csv(do.call(rbind, res_log), apath("2b2_runtime_resource_log.csv"), row.names = FALSE)

era_pass <- all(diag_res$era_gates$pass)
wc_pass <- all(diag_res$wc$pass_all)
STATUS <- if (era_pass && wc_pass) "PASS" else "FAIL"
write.csv(data.frame(status = STATUS, era_gates_pass = era_pass, within_cohort_pass = wc_pass,
  n_cohorts = length(ERA_COHORTS), failing_cohorts = paste(diag_res$wc$cohort[!diag_res$wc$pass_all], collapse = ",")),
  apath("2b2_status.csv"), row.names = FALSE)

banner("2B.2 RESULT")
print(diag_res$era_gates[, c("gate","value","threshold","pass")])
cat("\nWithin-cohort gates (1994-1999):\n")
print(diag_res$wc[, c("cohort","constrained_max_fullpooled_smd","firm_ess","max_firm_share","mass_discrepancy","pass_all")])
message(sprintf("\nSTATUS: %s (era_gates=%s, within_cohort=%s)", STATUS, era_pass, wc_pass))
banner("11t DONE -- 2B.2 era prototype (1994-1999); no outcomes, no DiD")

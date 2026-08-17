# ============================================================================
# 11s_build_nt2010_cohort_ebal_weights.R -- Package 2B.1
# ----------------------------------------------------------------------------
# Production-candidate P0H5 weights via the VALIDATED Package-2B.0 cohort-specific
# two-stage entropy balancing, applied SEQUENTIALLY to all 17 cohorts (1994-2010).
# Restartable (verified per-cohort shards), memory-bounded (one cohort at a time),
# assembled via DuckDB. Preserves the inventor-weighted ATT: cohort g contributes
# its treated-inventor mass; cohorts are NEVER normalised to equal/unit mass.
#
# The shared pooled two_stage_ebal() is NOT modified. `cohort_two_stage_ebal` here
# is the verbatim 11r implementation; equivalence is proven by requiring the 2009
# shard to reproduce the saved Package-2B.0 gates. Design-only: NO outcomes, NO
# citation work, NO annual states, NO DiD. Writes only versioned 2B.1 paths.
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

COHORTS <- STACK_LO:STACK_HI_NEVER_TARGET      # 1994:2010
CC_HI   <- STACK_HI_G7                          # 2008
MAXIT   <- 200000L
RELTOL  <- 1e-12
sqlp  <- function(p) gsub("\\\\", "/", p)
apath <- function(name) paste0(NT2010_AUDIT_PREFIX, "_", name)
dir.create(P0H5_COHORT_EBAL_SHARD_DIR, recursive = TRUE, showWarnings = FALSE)
SHARD_COLS <- c("codinv", "underlying_group_id", "stack", "treated", "final_weight",
                "n_qualifying_inventors", "focal_deal_id", "real_control_deal_id")

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='6GB'"); dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sqlp(DUCKDB_TMP)))

banner("2B.1 -- SEQUENTIAL COHORT-SPECIFIC P0H5 (1994-2010)")

# full-spec pooled SD per covariate (from Package 2A; read-only)
cb2a <- utils::read.csv(apath("2a_conditional_balance.csv"), stringsAsFactors = FALSE)
cb2a <- cb2a[cb2a$spec == "P0H5_nt2010", ]
POOLED_SD <- tapply(cb2a$pooled_full_sd, cb2a$covariate, function(x) x[1])

# ---------------------------------------------------------------------------
# VERBATIM Package-2B.0 cohort solver (no factor(stack); shared solver untouched)
# ---------------------------------------------------------------------------
cohort_two_stage_ebal <- function(units, firm_key_cols, firm_covars, inv_covars, inv_factors,
                                  cont_covars, maxit, reltol) {
  for (v in intersect(cont_covars, c(firm_covars, inv_covars)))
    units[[v]] <- standardize_continuous(units[[v]])
  units$.fk <- do.call(paste, c(units[firm_key_cols], sep = "|"))
  firm_data <- unique(units[, c(".fk", firm_key_cols, "treated", "stack", firm_covars, "n_qualifying_inventors")])
  stopifnot(!anyDuplicated(firm_data$.fk))
  firm_form <- stats::reformulate(firm_covars, response = "treated")
  W_firm <- WeightIt::weightit(firm_form, data = firm_data, method = "ebal", estimand = "ATT",
                               s.weights = firm_data$n_qualifying_inventors, maxit = maxit, reltol = reltol)
  firm_data$firm_multiplier <- as.numeric(W_firm$weights)
  units$firm_multiplier <- firm_data$firm_multiplier[match(units$.fk, firm_data$.fk)]
  units$inventor_base_weight <- units$firm_multiplier
  inv_form <- stats::reformulate(c(firm_covars, inv_covars, inv_factors), response = "treated")
  W_inv <- WeightIt::weightit(inv_form, data = units, method = "ebal", estimand = "ATT",
                              base.weights = units$inventor_base_weight, maxit = maxit, reltol = reltol)
  units$final_weight <- as.numeric(W_inv$weights)
  list(units = units, firm_data = firm_data, W_firm = W_firm, W_inv = W_inv,
       firm_form = firm_form, inv_form = inv_form)
}

# structural + support audit (verbatim 2B.0 rules)
structural_audit <- function(units) {
  removed <- data.frame(stage = character(0), column = character(0), reason = character(0))
  reasons <- character(0)
  sd_all <- sapply(FULL_NUMERIC_COVARS, function(v) stats::sd(units[[v]]))
  drop_num <- names(sd_all)[!is.finite(sd_all) | sd_all == 0]
  for (v in drop_num) removed <- rbind(removed, data.frame(stage = "numeric", column = v,
    reason = "zero variance across both arms (no balance restriction)"))
  firm_covars <- setdiff(FIRM_COVARS, drop_num)
  inv_covars  <- setdiff(INV_COVARS,  drop_num)
  cont_covars <- setdiff(FULL_CONT_COVARS, drop_num)
  inv_factors <- c()
  for (f in INV_FACTOR_COVARS) {
    units[[f]] <- droplevels(units[[f]])
    if (nlevels(units[[f]]) < 2L) removed <- rbind(removed, data.frame(stage = "factor", column = f,
      reason = sprintf("only %d realised level(s) (no balance restriction)", nlevels(units[[f]]))))
    else inv_factors <- c(inv_factors, f)
  }
  for (f in inv_factors) {
    tl <- table(units[[f]][units$treated == 1L]); cl <- table(units[[f]][units$treated == 0L])
    bad <- names(tl)[tl > 0 & (is.na(cl[names(tl)]) | cl[names(tl)] == 0)]
    for (lv in bad) reasons <- c(reasons, sprintf("factor %s level '%s' in treated but no control support", f, lv))
  }
  for (v in c(firm_covars, inv_covars)) {
    tm <- mean(units[[v]][units$treated == 1L]); cr <- range(units[[v]][units$treated == 0L])
    if (tm < cr[1] - 1e-9 || tm > cr[2] + 1e-9)
      reasons <- c(reasons, sprintf("treated mean of %s (%.4g) outside control range [%.4g,%.4g]", v, tm, cr[1], cr[2]))
  }
  list(units = units, removed = removed, firm_covars = firm_covars, inv_covars = inv_covars,
       cont_covars = cont_covars, inv_factors = inv_factors, support_reasons = reasons)
}

# per-cohort weighted sufficient statistics (centered on cohort-arm mean; stable)
cohort_suff <- function(units, w) {
  arm_list <- list(); cov_list <- list(); g <- units$stack[1]
  for (arm in c(0L, 1L)) {
    idx <- units$treated == arm; ww <- w[idx]
    arm_list[[length(arm_list) + 1L]] <- data.frame(cohort = g, treated = arm,
      sum_w = sum(ww), sum_w2 = sum(ww^2), n = sum(idx), n_pos = sum(ww > 0))
    for (v in FULL_NUMERIC_COVARS) {
      x <- units[[v]][idx]; m <- sum(ww * x) / sum(ww)
      cov_list[[length(cov_list) + 1L]] <- data.frame(cohort = g, treated = arm,
        covariate = v, sw = sum(ww * x), cSS = sum(ww * (x - m)^2))
    }
  }
  list(arm = do.call(rbind, arm_list), cov = do.call(rbind, cov_list))
}

# parallel-axis pooled moments for a covariate over a group of cohorts (both arms)
pooled_moment <- function(arm_ss, cov_ss, cohorts, cov) {
  out <- lapply(c(1L, 0L), function(arm) {
    a <- arm_ss[arm_ss$cohort %in% cohorts & arm_ss$treated == arm, ]
    c <- cov_ss[cov_ss$cohort %in% cohorts & cov_ss$treated == arm & cov_ss$covariate == cov, ]
    c <- merge(c, a[, c("cohort", "sum_w")], by = "cohort")
    sw <- sum(c$sum_w); m <- sum(c$sw) / sw
    mcoh <- c$sw / c$sum_w
    v <- sum(c$cSS + c$sum_w * (mcoh - m)^2) / sw
    list(mean = m, var = max(v, 0), sw = sw)
  })
  list(mt = out[[1]]$mean, mc = out[[2]]$mean, vt = out[[1]]$var, vc = out[[2]]$var,
       sw_t = out[[1]]$sw, sw_c = out[[2]]$sw)
}
balance_group <- function(arm_ss, cov_ss, cohorts, level, glab, constrained) {
  do.call(rbind, lapply(FULL_NUMERIC_COVARS, function(cov) {
    m <- pooled_moment(arm_ss, cov_ss, cohorts, cov)
    sdt <- sqrt(m$vt); raw <- m$mt - m$mc
    data.frame(level = level, group = glab, covariate = cov,
      treated_wmean = m$mt, control_wmean = m$mc, raw_diff = raw,
      smd_treated_sd = if (is.finite(sdt) && sdt > 0) raw / sdt else NA_real_,
      denom_collapse = !(is.finite(sdt) && sdt > 0),
      smd_fullpooled = raw / POOLED_SD[cov], constrained = cov %in% constrained,
      stringsAsFactors = FALSE)
  }))
}
ess_of <- function(x) { x <- x[is.finite(x) & x > 0]; if (!length(x)) 0 else sum(x)^2 / sum(x^2) }

# ===========================================================================
# SEQUENTIAL PER-COHORT SOLVE (restartable)
# ===========================================================================
res_log <- list(); gates_all <- list(); support_all <- list(); removed_all <- list()
conv_all <- list(); arm_ss_all <- list(); cov_ss_all <- list(); constrained_by_cohort <- list()
overall_t0 <- Sys.time(); max_mem <- 0

for (g in COHORTS) {
  banner(sprintf("Cohort %d", g))
  shard <- file.path(P0H5_COHORT_EBAL_SHARD_DIR, sprintf("cohort_%d.parquet", g))
  meta_path <- apath(sprintf("2b1_cohort_meta_%d.csv", g))
  gc(reset = TRUE); ct0 <- Sys.time()

  # ---- restart reuse (only after verifying the shard) ----
  reuse <- FALSE
  if (file.exists(shard) && file.exists(meta_path)) {
    meta <- utils::read.csv(meta_path, stringsAsFactors = FALSE)
    sh <- dbGetQuery(con, sprintf("SELECT COUNT(*) n, MIN(stack) lo, MAX(stack) hi,
      SUM(treated) nt, COUNT(DISTINCT CAST(codinv AS VARCHAR)||'|'||CAST(treated AS VARCHAR)) nk
      FROM read_parquet('%s')", sqlp(shard)))
    rr <- dbGetQuery(con, sprintf("SELECT COUNT(*) n, SUM(treated) nt FROM read_parquet('%s') WHERE stack=%d",
      sqlp(NT2010_ANALYSIS_UNITS_PARQUET), g))
    ok <- isTRUE(meta$cohort == g) && isTRUE(meta$maxit == MAXIT) && isTRUE(meta$reltol == RELTOL) &&
          isTRUE(meta$input_path == basename(NT2010_ANALYSIS_UNITS_PARQUET)) &&
          isTRUE(meta$all_gates_pass) && sh$lo == g && sh$hi == g && sh$n == sh$nk &&
          sh$n == rr$n && sh$nt == rr$nt
    if (ok) { message("  verified shard present -> reuse."); reuse <- TRUE
    } else message("  shard present but unverifiable -> re-solving.")
  }

  if (!reuse) {
    # ---- load cohort (project required cols) ----
    sel <- paste(c("codinv", "focal_deal_id", "underlying_group_id", "stack", "treated",
                   "arm", "qualifying_gap", "modal_family", FIRM_COVARS, INV_COVARS), collapse = ", ")
    units <- dbGetQuery(con, sprintf("SELECT %s FROM read_parquet('%s') WHERE stack=%d",
                                     sel, sqlp(NT2010_ANALYSIS_UNITS_PARQUET), g))
    units$codinv <- as.numeric(units$codinv); units$stack <- as.integer(units$stack)
    units$treated <- as.integer(units$treated); units$underlying_group_id <- as.numeric(units$underlying_group_id)
    units$focal_deal_id <- as.integer(units$focal_deal_id)
    # key uniqueness + missingness gates
    if (anyDuplicated(units[, c("codinv", "stack", "treated")])) stop(sprintf("[2B.1] cohort %d duplicate keys.", g), call. = FALSE)
    if (any(rowSums(is.na(units[, c(FIRM_COVARS, INV_COVARS)])) > 0)) stop(sprintf("[2B.1] cohort %d has covariate-missing rows.", g), call. = FALSE)
    cell <- paste(units$underlying_group_id, units$stack, sep = "|")
    units$n_qualifying_inventors <- as.integer(table(cell)[cell])
    units$qualifying_gap_cat <- factor(pmin(units$qualifying_gap, 3L), levels = 0:3,
                                       labels = c("gap0", "gap1", "gap2", "gap3plus"))
    units$modal_family <- factor(units$modal_family, levels = TECH_FAMILIES)
    el_load <- as.numeric(Sys.time() - ct0, units = "secs"); mem_load <- sum(gc()[, "max used"] * c(56, 8)) / 1e6
    message(sprintf("  loaded %d units (treated=%d control=%d) | %.1fs ~%.0fMB",
                    nrow(units), sum(units$treated == 1L), sum(units$treated == 0L), el_load, mem_load))

    # ---- structural/support audit ----
    sa <- structural_audit(units); units <- sa$units
    if (nrow(sa$removed) > 0) removed_all[[as.character(g)]] <- cbind(cohort = g, sa$removed)
    if (length(sa$support_reasons) > 0) {
      write.csv(data.frame(cohort = g, reason = sa$support_reasons), apath(sprintf("2b1_cohort_%d_support_failure.csv", g)), row.names = FALSE)
      stop(sprintf("[2B.1] cohort %d has unsupported treated moments: %s", g, paste(sa$support_reasons, collapse = "; ")), call. = FALSE)
    }
    constrained <- c(sa$firm_covars, sa$inv_covars)
    constrained_by_cohort[[as.character(g)]] <- constrained

    # ---- solve (firm + inventor) ----
    tb0 <- Sys.time()
    fit <- cohort_two_stage_ebal(units, c("underlying_group_id", "stack"),
                                 sa$firm_covars, sa$inv_covars, sa$inv_factors, sa$cont_covars, MAXIT, RELTOL)
    u <- fit$units; w <- u$final_weight
    el_bal <- as.numeric(Sys.time() - tb0, units = "secs"); mem_bal <- sum(gc()[, "max used"] * c(56, 8)) / 1e6
    message(sprintf("  balanced | %.1fs ~%.0fMB", el_bal, mem_bal))

    # ---- gates + diagnostics (balance on RAW covars in `units`) ----
    ss <- cohort_suff(units, w)                       # centered sufficient stats for this cohort
    bal_new <- balance_group(ss$arm, ss$cov, g, "cohort", as.character(g), constrained)
    firm_md <- ebal_max_meandiff(model_matrix_cols(fit$firm_form, fit$firm_data), fit$firm_data$treated,
                                 fit$firm_data$n_qualifying_inventors * fit$firm_data$firm_multiplier)
    inv_md  <- ebal_max_meandiff(model_matrix_cols(fit$inv_form, u), u$treated, w)
    cwt <- w[u$treated == 0L]; cfirm <- u$underlying_group_id[u$treated == 0L]; pos <- cwt > 0
    firm_mass <- tapply(cwt[pos], cfirm[pos], sum); fmt <- sum(firm_mass); fms <- sort(as.numeric(firm_mass), decreasing = TRUE)
    firm_ess <- ess_of(as.numeric(firm_mass)); inv_ess <- ess_of(cwt[pos])
    max_share <- fms[1] / fmt; top5 <- sum(head(fms, 5)) / fmt
    treated_mass <- sum(w[u$treated == 1L]); control_mass <- sum(cwt)
    mass_disc <- abs(control_mass - treated_mass) / treated_mass
    cpsmd <- abs(bal_new$smd_fullpooled[bal_new$constrained])

    gates <- data.frame(cohort = g,
      gate = c("treated_w_eq_1", "finite_nonneg", "firm_raw_meandiff", "inv_raw_meandiff",
               "mass_discrepancy", "max_fullpooled_smd_constrained", "firm_ess", "max_firm_share",
               "pos_controls_and_firms_present"),
      value = c(max(abs(w[u$treated == 1L] - 1)), as.numeric(all(is.finite(w) & w >= -1e-12)),
                firm_md, inv_md, mass_disc, max(cpsmd), firm_ess, max_share, as.numeric(sum(pos) > 0 && length(firm_mass) > 0)),
      threshold = c(1e-8, 1, EBAL_CONSTRAINT_TOL, 1e-4, STACK_MASS_TOL, ROBUST_MAX_SMD_CONSTRAINED, ROBUST_MIN_ESS, ROBUST_MAX_SHARE, 1),
      stringsAsFactors = FALSE)
    gates$pass <- c(max(abs(w[u$treated == 1L] - 1)) < 1e-8, all(is.finite(w) & w >= -1e-12),
                    firm_md <= EBAL_CONSTRAINT_TOL, inv_md <= 1e-4, mass_disc <= STACK_MASS_TOL,
                    max(cpsmd) <= ROBUST_MAX_SMD_CONSTRAINED, firm_ess >= ROBUST_MIN_ESS,
                    max_share <= ROBUST_MAX_SHARE, sum(pos) > 0 && length(firm_mass) > 0)
    conv <- data.frame(cohort = g, stage = c("firm", "inventor"),
      weightit_converged = c(isTRUE(fit$W_firm$info$converged), isTRUE(fit$W_inv$info$converged)),
      raw_meandiff = c(firm_md, inv_md))
    support <- data.frame(cohort = g, treated_inventors = sum(u$treated == 1L), treated_mass = treated_mass,
      control_mass = control_mass, control_pos_inventors = sum(pos), control_pos_firms = length(firm_mass),
      control_inventor_ess = inv_ess, control_firm_ess = firm_ess, max_firm_share = max_share, top5_firm_share = top5,
      n_removed_columns = nrow(sa$removed))

    if (!all(gates$pass)) {
      write.csv(gates, apath(sprintf("2b1_cohort_%d_FAILED_gates.csv", g)), row.names = FALSE)
      write.csv(bal_new, apath(sprintf("2b1_cohort_%d_FAILED_balance.csv", g)), row.names = FALSE)
      stop(sprintf("[2B.1] cohort %d FAILED gates: %s. No assembly.", g,
                   paste(gates$gate[!gates$pass], collapse = "; ")), call. = FALSE)
    }

    # ---- write verified shard + meta ----
    out <- u[, intersect(SHARD_COLS, names(u))]
    out$real_control_deal_id <- NA_integer_
    out <- out[, SHARD_COLS]
    duckdb::duckdb_register(con, "shard_out", out)
    dbExecute(con, sprintf("COPY (SELECT * FROM shard_out) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", sqlp(shard)))
    duckdb::duckdb_unregister(con, "shard_out")
    utils::write.csv(data.frame(cohort = g, maxit = MAXIT, reltol = RELTOL,
      input_path = basename(NT2010_ANALYSIS_UNITS_PARQUET), all_gates_pass = all(gates$pass),
      n_units = nrow(out), n_treated = sum(out$treated), n_removed = nrow(sa$removed),
      firm_covars = paste(sa$firm_covars, collapse = "|"), inv_covars = paste(sa$inv_covars, collapse = "|"),
      inv_factors = paste(sa$inv_factors, collapse = "|")), meta_path, row.names = FALSE)

    gates_all[[as.character(g)]] <- gates; support_all[[as.character(g)]] <- support
    conv_all[[as.character(g)]] <- conv; arm_ss_all[[as.character(g)]] <- ss$arm; cov_ss_all[[as.character(g)]] <- ss$cov
    res_log[[as.character(g)]] <- data.frame(cohort = g, load_s = el_load, balance_s = el_bal,
      peak_mem_mb = max(mem_load, mem_bal))
    max_mem <- max(max_mem, mem_load, mem_bal)
    rm(units, u, w, fit, out, ss, firm_mass); gc()
  }
}

# assemble accumulators; if any cohort was reused, recompute its sufficient stats from the shard is unnecessary
# because verification below is on the ASSEMBLED files. Gate/balance detail exists per solved cohort.
gates_df <- do.call(rbind, gates_all); support_df <- do.call(rbind, support_all)
conv_df <- do.call(rbind, conv_all); removed_df <- do.call(rbind, removed_all)
if (length(gates_all) < length(COHORTS))
  message(sprintf("NOTE: %d cohort(s) reused from verified shards; per-cohort balance detail is from solved cohorts only.",
                  length(COHORTS) - length(gates_all)))
if (length(gates_all) > 0 && !all(gates_df$pass)) stop("[2B.1] a solved cohort failed gates; not assembling.", call. = FALSE)

# ===========================================================================
# ASSEMBLE full + cc9408 from shards (DuckDB; no 4.5M collect)
# ===========================================================================
banner("Assembling full (1994-2010) and cc9408 (1994-2008) from shards")
shard_glob <- sqlp(file.path(P0H5_COHORT_EBAL_SHARD_DIR, "cohort_*.parquet"))
dbExecute(con, sprintf("COPY (SELECT * FROM read_parquet('%s')) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
                       shard_glob, sqlp(P0H5_COHORT_EBAL_WEIGHTS_PARQUET)))
dbExecute(con, sprintf("COPY (SELECT * FROM read_parquet('%s') WHERE stack <= %d) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
                       sqlp(P0H5_COHORT_EBAL_WEIGHTS_PARQUET), CC_HI, sqlp(P0H5_COHORT_EBAL_CC9408_WEIGHTS_PARQUET)))

verify_membership <- function(wp, exp_treated, exp_control, exp_rows, exp_deals, exp_cohorts, lo, hi) {
  fw <- sqlp(wp); rp <- sqlp(NT2010_ANALYSIS_UNITS_PARQUET)
  s <- dbGetQuery(con, sprintf("SELECT COUNT(*) n, SUM(treated) nt, SUM(1-treated) nc,
    COUNT(DISTINCT stack) nk, MIN(stack) lo, MAX(stack) hi,
    COUNT(DISTINCT CAST(codinv AS VARCHAR)||'|'||CAST(stack AS VARCHAR)||'|'||CAST(treated AS VARCHAR)) uk
    FROM read_parquet('%s')", fw))
  # anti-joins vs roster restricted to [lo,hi]
  miss <- dbGetQuery(con, sprintf("SELECT COUNT(*) n FROM (
      SELECT codinv,stack,treated FROM read_parquet('%s') WHERE stack BETWEEN %d AND %d
      EXCEPT SELECT codinv,stack,treated FROM read_parquet('%s'))", rp, lo, hi, fw))$n
  extra <- dbGetQuery(con, sprintf("SELECT COUNT(*) n FROM (
      SELECT codinv,stack,treated FROM read_parquet('%s')
      EXCEPT SELECT codinv,stack,treated FROM read_parquet('%s') WHERE stack BETWEEN %d AND %d)", fw, rp, lo, hi))$n
  deals <- dbGetQuery(con, sprintf("SELECT COUNT(DISTINCT focal_deal_id) d FROM read_parquet('%s') WHERE treated=1", fw))$d
  data.frame(file = basename(wp), rows = s$n, treated = s$nt, control = s$nc, unique_keys = s$uk,
    cohorts = s$nk, min_stack = s$lo, max_stack = s$hi, treated_deals = deals,
    missing_vs_roster = miss, extra_vs_roster = extra,
    rows_ok = s$n == exp_rows, treated_ok = s$nt == exp_treated, control_ok = s$nc == exp_control,
    deals_ok = deals == exp_deals, cohorts_ok = s$nk == exp_cohorts, unique_ok = s$uk == s$n,
    keyset_ok = miss == 0 && extra == 0)
}
mem_full <- verify_membership(P0H5_COHORT_EBAL_WEIGHTS_PARQUET, 27746, 4473727, 4501473, 336, 17, STACK_LO, STACK_HI_NEVER_TARGET)
mem_cc   <- verify_membership(P0H5_COHORT_EBAL_CC9408_WEIGHTS_PARQUET, 25524, 3717896, 3743420, 290, 15, STACK_LO, CC_HI)
membership <- rbind(mem_full, mem_cc)
write.csv(membership, apath("2b1_membership_verification.csv"), row.names = FALSE)
print(t(membership))

# cc9408 is EXACTLY the <=2008 subset of the full shards
cc_subset_ok <- dbGetQuery(con, sprintf("SELECT
  (SELECT COUNT(*) FROM (SELECT * FROM read_parquet('%s') WHERE stack<=%d
     EXCEPT SELECT * FROM read_parquet('%s'))) a,
  (SELECT COUNT(*) FROM (SELECT * FROM read_parquet('%s')
     EXCEPT SELECT * FROM read_parquet('%s') WHERE stack<=%d)) b",
  sqlp(P0H5_COHORT_EBAL_WEIGHTS_PARQUET), CC_HI, sqlp(P0H5_COHORT_EBAL_CC9408_WEIGHTS_PARQUET),
  sqlp(P0H5_COHORT_EBAL_CC9408_WEIGHTS_PARQUET), sqlp(P0H5_COHORT_EBAL_WEIGHTS_PARQUET), CC_HI))
cc_exact <- cc_subset_ok$a == 0 && cc_subset_ok$b == 0

# ===========================================================================
# COMBINED-DESIGN BALANCE / SUPPORT (parallel-axis pooling of cohort suff-stats)
# ===========================================================================
if (length(arm_ss_all) == length(COHORTS)) {
  banner("Combined-design balance & support")
  arm_ss <- do.call(rbind, arm_ss_all); cov_ss <- do.call(rbind, cov_ss_all)
  constrained_union <- unique(unlist(constrained_by_cohort))
  eras <- BALANCE_ERAS_NEVER_TARGET
  bal_cohort <- do.call(rbind, lapply(COHORTS, function(g)
    cbind(spec = "P0H5_cohort_ebal", balance_group(arm_ss, cov_ss, g, "cohort", as.character(g), constrained_union))))
  bal_era <- do.call(rbind, lapply(eras, function(er) {
    cohs <- COHORTS[COHORTS >= er[1] & COHORTS <= er[2]]
    cbind(spec = "P0H5_cohort_ebal", balance_group(arm_ss, cov_ss, cohs, "era", paste(er, collapse = "-"), constrained_union)) }))
  bal_global <- cbind(spec = "P0H5_cohort_ebal", balance_group(arm_ss, cov_ss, COHORTS, "full", "all", constrained_union))
  balance_combined <- rbind(bal_global, bal_era, bal_cohort)
  write.csv(balance_combined, apath("2b1_combined_balance.csv"), row.names = FALSE)

  # global/era firm ESS + concentration + stack mass from the assembled parquet (one grouped scan)
  fm <- dbGetQuery(con, sprintf("SELECT stack AS cohort, underlying_group_id, SUM(final_weight) firm_mass
    FROM read_parquet('%s') WHERE treated=0 AND final_weight>0 GROUP BY stack, underlying_group_id",
    sqlp(P0H5_COHORT_EBAL_WEIGHTS_PARQUET)))
  sm <- dbGetQuery(con, sprintf("SELECT stack AS cohort, treated, SUM(final_weight) mass,
    SUM(final_weight*final_weight) mass2, SUM(CASE WHEN final_weight>0 THEN 1 ELSE 0 END) n_pos
    FROM read_parquet('%s') GROUP BY stack, treated", sqlp(P0H5_COHORT_EBAL_WEIGHTS_PARQUET)))
  conc_group <- function(cohs, level, glab) {
    f <- fm[fm$cohort %in% cohs, ]; agg <- tapply(f$firm_mass, f$underlying_group_id, sum)
    tot <- sum(agg); s <- sort(as.numeric(agg), decreasing = TRUE)
    tc <- sm[sm$cohort %in% cohs & sm$treated == 0L, ]; ti <- sm[sm$cohort %in% cohs & sm$treated == 1L, ]
    data.frame(spec = "P0H5_cohort_ebal", level = level, group = glab,
      treated_mass = sum(ti$mass), control_mass = sum(tc$mass),
      control_pos_inventors = sum(tc$n_pos), control_pos_firms = length(agg),
      control_inventor_ess = sum(tc$mass)^2 / sum(tc$mass2), control_firm_ess = ess_of(as.numeric(agg)),
      max_firm_share = s[1] / tot, top5_firm_share = sum(head(s, 5)) / tot,
      mass_discrepancy = abs(sum(tc$mass) - sum(ti$mass)) / sum(ti$mass))
  }
  support_combined <- rbind(
    conc_group(COHORTS, "full", "all"),
    do.call(rbind, lapply(eras, function(er) conc_group(COHORTS[COHORTS >= er[1] & COHORTS <= er[2]], "era", paste(er, collapse = "-")))),
    do.call(rbind, lapply(COHORTS, function(g) conc_group(g, "cohort", as.character(g)))))
  write.csv(support_combined, apath("2b1_combined_support.csv"), row.names = FALSE)
  # weight quantiles (control positive) global
  wq <- dbGetQuery(con, sprintf("SELECT final_weight FROM read_parquet('%s') WHERE treated=0 AND final_weight>0",
    sqlp(P0H5_COHORT_EBAL_WEIGHTS_PARQUET)))$final_weight
  write.csv(cbind(scope = "global_control", weight_quantile_diag(wq)), apath("2b1_weight_quantiles.csv"), row.names = FALSE)
  # treated mass by cohort
  tmc <- sm[sm$treated == 1L, c("cohort", "mass", "n_pos")]; names(tmc) <- c("cohort", "treated_mass", "treated_pos")
  write.csv(tmc, apath("2b1_treated_mass_by_cohort.csv"), row.names = FALSE)

  # ---- old-vs-new global comparison (do NOT modify old file) ----
  old_arm <- dbGetQuery(con, sprintf("SELECT stack cohort, treated, SUM(final_weight) sum_w FROM read_parquet('%s') GROUP BY stack, treated", sqlp(P0H5_NT2010_WEIGHTS_PARQUET)))
  new_max <- max(abs(bal_global$smd_fullpooled[bal_global$constrained]))
  old_cb <- cb2a  # 2A already has the OLD global-design per-cohort; global full-pooled max:
  old_cohort_max <- max(abs(cb2a$smd_fullpooled[cb2a$level == "cohort" & cb2a$constrained]), na.rm = TRUE)
  cmp <- data.frame(metric = c("new_global_constrained_max_fullpooled_smd",
                               "old_global_worst_cohort_constrained_fullpooled_smd"),
                    value = c(new_max, old_cohort_max))
  write.csv(cmp, apath("2b1_old_vs_new_summary.csv"), row.names = FALSE)

  # algebraic checks
  alg <- data.frame(
    check = c("total_treated_mass_full_eq_27746", "total_treated_mass_cc_eq_25524",
              "cohort_treated_mass_eq_ntreated", "control_mass_matches_treated_all_cohorts",
              "cc_is_exact_subset_of_full", "global_constrained_max_fullpooled_le_0.05"),
    value = c(sum(tmc$treated_mass), sum(tmc$treated_mass[tmc$cohort <= CC_HI]),
              as.numeric(all(abs(tmc$treated_mass - tmc$treated_pos) < 1e-6)),
              as.numeric(all(support_combined$mass_discrepancy[support_combined$level == "cohort"] <= STACK_MASS_TOL)),
              as.numeric(cc_exact), new_max),
    pass = c(abs(sum(tmc$treated_mass) - 27746) < 1e-6, abs(sum(tmc$treated_mass[tmc$cohort <= CC_HI]) - 25524) < 1e-6,
             all(abs(tmc$treated_mass - tmc$treated_pos) < 1e-6),
             all(support_combined$mass_discrepancy[support_combined$level == "cohort"] <= STACK_MASS_TOL),
             cc_exact, new_max <= ROBUST_MAX_SMD_CONSTRAINED))
  write.csv(alg, apath("2b1_algebraic_checks.csv"), row.names = FALSE)
  print(alg)
} else {
  message("Combined balance from suff-stats skipped (reused shards lack in-memory suff-stats); membership + assembled-parquet scans still verify the design.")
}

# per-cohort diagnostics + runtime
if (length(gates_all)) write.csv(gates_df, apath("2b1_cohort_gates.csv"), row.names = FALSE)
if (length(support_all)) write.csv(support_df, apath("2b1_cohort_support.csv"), row.names = FALSE)
if (length(conv_all)) write.csv(conv_df, apath("2b1_solver_convergence.csv"), row.names = FALSE)
if (length(removed_all)) write.csv(removed_df, apath("2b1_structural_removed_columns.csv"), row.names = FALSE)
total_el <- as.numeric(Sys.time() - overall_t0, units = "mins")
write.csv(rbind(do.call(rbind, res_log),
  data.frame(cohort = NA, load_s = NA, balance_s = NA, peak_mem_mb = max_mem)),
  apath("2b1_runtime_resource_log.csv"), row.names = FALSE)

status <- if (all(membership$rows_ok & membership$treated_ok & membership$control_ok &
                  membership$deals_ok & membership$cohorts_ok & membership$unique_ok &
                  membership$keyset_ok) && cc_exact) "PASS" else "FAIL"
write.csv(data.frame(status = status, total_minutes = total_el, max_mem_mb = max_mem,
  n_cohorts_solved = length(gates_all), n_cohorts_reused = length(COHORTS) - length(gates_all)),
  apath("2b1_status.csv"), row.names = FALSE)

banner(sprintf("11s DONE -- 2B.1 status=%s | total %.1f min, max ~%.0f MB", status, total_el, max_mem))

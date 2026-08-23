# ============================================================================
# 11u_prototype_nt2010_approx_cohort_ebal.R -- Package 2B.3
# ----------------------------------------------------------------------------
# PROTOTYPE: APPROXIMATE within-cohort P0H5 entropy balancing (WeightIt tols +
# solver="FISTA"), on cohorts 1995 and 1996 only. Instead of forcing covariate
# differences to ~0 (which concentrates control weight), find the most diffuse
# ebal weights that keep every constrained full-pooled |SMD| within the accepted
# 0.05 criterion. Isolated; the shared two_stage_ebal() is NOT used/modified.
# Public WeightIt::weightit() interface only (no internals). Design-only: no
# outcomes/citations/annual-states/DiD. Writes only labelled diagnostic parquets
# + versioned 2B.3 CSVs. No production path; no 2B.0-2B.2 output overwritten.
#
# tols translation (WeightIt 1.7.0 ebal/ATT, verified from source):
#   constraint enforced == |treated-SD SMD[j]| <= tols[j]  (nonbinary; scale-inv)
#                       == |raw mean diff[j]|   <= tols[j]  (binary; sds=1)
#   intercept + factor dummies kept EXACT (tols=0).
#   want raw_diff[j] <= 0.05 * pooled_sd[j]  =>
#     nonbinary: tols[j] = 0.05 * pooled_sd[j] / sd_treated_raw[j]
#     binary:    tols[j] = 0.05 * pooled_sd[j]
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "archive", "main_did_v1", "11a_main_design_config.R"))
source(file.path(BASE, "R", "archive", "main_did_v1", "11_main_design_utils.R"))   # banner, ess, weight_quantile_diag (no two_stage_ebal use)
source(file.path(BASE, "R", "archive", "main_did_v1", "11i_robustness_config.R"))
for (pkg in c("DBI", "duckdb", "WeightIt"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({ library(DBI); library(duckdb); library(WeightIt) })
set.seed(SEED)

PROTO_COHORTS <- c(1995L, 1996L)
SMD_TARGET <- ROBUST_MAX_SMD_CONSTRAINED   # 0.05
MAXIT  <- 200000L
RELTOL <- 1e-10                            # WeightIt numerical default (optimizer-accuracy, not a balance threshold)
sqlp  <- function(p) gsub("\\\\", "/", p)
apath <- function(name) paste0(NT2010_AUDIT_PREFIX, "_", name)

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='6GB'"); dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sqlp(DUCKDB_TMP)))

banner("2B.3 -- APPROXIMATE within-cohort P0H5 ebal (FISTA), cohorts 1995 & 1996")

cb2a <- utils::read.csv(apath("2a_conditional_balance.csv"), stringsAsFactors = FALSE)
cb2a <- cb2a[cb2a$spec == "P0H5_nt2010", ]
POOLED_SD <- tapply(cb2a$pooled_full_sd, cb2a$covariate, function(x) x[1])

wmean <- function(x, w) sum(w * x) / sum(w)
wsd   <- function(x, w) { m <- wmean(x, w); sqrt(sum(w * (x - m)^2) / sum(w)) }
is_bin <- function(x) length(unique(x[!is.na(x)])) <= 2L

# Build a FULL-RANK numeric design (numeric covars + expanded factor dummies) so
# WeightIt drops nothing; return X, per-column info, and any collinear drops.
build_design <- function(data, numeric_covars, factor_covars) {
  form <- stats::reformulate(c(numeric_covars, factor_covars))
  mm <- stats::model.matrix(form, data = data)
  X <- mm[, colnames(mm) != "(Intercept)", drop = FALSE]
  colnames(X) <- make.names(colnames(X), unique = TRUE)
  is_numcov <- colnames(X) %in% numeric_covars
  # iteratively drop collinear columns (keep earlier columns) so cbind(1,X) is full rank
  dropped <- character(0)
  repeat {
    q <- qr(cbind(`(Intercept)` = 1, X))
    if (q$rank == ncol(X) + 1L) break
    keep <- q$pivot[seq_len(q$rank)]
    keepX <- setdiff(keep, 1L) - 1L        # indices into X (excluding intercept pivot)
    dropped <- c(dropped, setdiff(colnames(X), colnames(X)[keepX]))
    X <- X[, sort(keepX), drop = FALSE]; is_numcov <- colnames(X) %in% numeric_covars
  }
  list(X = X, is_numcov = is_numcov, dropped = dropped)
}

# Construct tols aligned to design columns + a transparent mapping table.
make_tols <- function(des, treated, s.weights, stage) {
  X <- des$X; tols <- numeric(ncol(X)); map <- list()
  for (j in seq_len(ncol(X))) {
    col <- colnames(X)[j]; x <- X[, j]; is_factor_dummy <- !des$is_numcov[j]
    binary <- is_bin(x)
    sdt <- wsd(x[treated == 1L], s.weights[treated == 1L])
    if (is_factor_dummy) {
      orig <- "factor_dummy"; psd <- NA_real_; desired <- 0; tj <- 0; implied <- 0        # exact
    } else {
      orig <- col; psd <- as.numeric(POOLED_SD[col]); desired <- SMD_TARGET * psd
      if (binary) { tj <- desired; implied <- tj }                                          # raw allowance
      else if (is.finite(sdt) && sdt > 0) { tj <- desired / sdt; implied <- tj * sdt }      # treated-SD SMD bound
      else { tj <- 0; desired <- 0; implied <- 0 }                                          # zero treated SD -> exact+flag
    }
    tols[j] <- tj
    map[[j]] <- data.frame(stage = stage, original_covariate = orig, mm_column = col,
      type = if (is_factor_dummy) "factor_dummy" else if (binary) "binary" else "continuous",
      treated_sd = sdt, fixed_pooled_sd = psd, desired_raw_tol = desired,
      weightit_tols = tj, implied_raw_tol = implied,
      zero_treated_sd_exact = !is_factor_dummy && !binary && !(is.finite(sdt) && sdt > 0))
  }
  list(tols = tols, map = do.call(rbind, map))
}

approx_weightit <- function(data, des, tols, s.weights, base.weights = NULL) {
  f <- stats::reformulate(colnames(des$X), response = "treated")
  d <- data.frame(treated = data$treated, des$X, check.names = FALSE)
  args <- list(f, data = d, method = "ebal", estimand = "ATT", s.weights = s.weights,
               tols = tols, solver = "FISTA", maxit = MAXIT, reltol = RELTOL)
  if (!is.null(base.weights)) args$base.weights <- base.weights
  do.call(WeightIt::weightit, args)
}

# ---- balance / concentration on final weights (raw covars) ----
balance_final <- function(units, w, constrained) {
  tt <- units$treated == 1L; cc <- units$treated == 0L
  do.call(rbind, lapply(FULL_NUMERIC_COVARS, function(v) {
    mt <- wmean(units[[v]][tt], w[tt]); mc <- wmean(units[[v]][cc], w[cc]); sdt <- wsd(units[[v]][tt], w[tt])
    raw <- mt - mc
    data.frame(covariate = v, raw_diff = raw,
      smd_treated_sd = if (is.finite(sdt) && sdt > 0) raw / sdt else NA_real_,
      denom_collapse = !(is.finite(sdt) && sdt > 0),
      smd_fullpooled = raw / POOLED_SD[v], constrained = v %in% constrained, stringsAsFactors = FALSE)
  }))
}
conc_final <- function(units, w) {
  idx <- units$treated == 0L & w > 0; fm <- tapply(w[idx], units$underlying_group_id[idx], sum)
  tot <- sum(fm); s <- sort(as.numeric(fm), TRUE)
  list(firm_ess = ess(as.numeric(fm)), inv_ess = ess(w[idx]), n_firms = length(fm), n_inv = sum(idx),
       max_share = s[1] / tot, top5 = sum(head(s, 5)) / tot)
}

# structural audit (numeric zero-variance across both arms + factor <2 levels + factor support)
structural_audit <- function(units) {
  removed <- data.frame(stage = character(0), column = character(0), reason = character(0)); reasons <- character(0)
  sd_all <- sapply(FULL_NUMERIC_COVARS, function(v) stats::sd(units[[v]]))
  drop_num <- names(sd_all)[!is.finite(sd_all) | sd_all == 0]
  for (v in drop_num) removed <- rbind(removed, data.frame(stage = "numeric", column = v, reason = "constant both arms"))
  firm_covars <- setdiff(FIRM_COVARS, drop_num); inv_covars <- setdiff(INV_COVARS, drop_num); inv_factors <- c()
  for (f in INV_FACTOR_COVARS) {
    if (any(is.na(units[[f]]))) reasons <- c(reasons, sprintf("factor %s has NA/out-of-level values", f))
    units[[f]] <- droplevels(units[[f]])
    if (nlevels(units[[f]]) < 2L) removed <- rbind(removed, data.frame(stage = "factor", column = f,
      reason = sprintf("only %d level(s)", nlevels(units[[f]])))) else inv_factors <- c(inv_factors, f)
  }
  for (f in inv_factors) { tl <- table(units[[f]][units$treated == 1L]); cl <- table(units[[f]][units$treated == 0L])
    for (lv in names(tl)[tl > 0 & (is.na(cl[names(tl)]) | cl[names(tl)] == 0)])
      reasons <- c(reasons, sprintf("factor %s level '%s' no control support", f, lv)) }
  list(units = units, removed = removed, firm_covars = firm_covars, inv_covars = inv_covars, inv_factors = inv_factors,
       support_reasons = reasons)
}

res_log <- list(); all_gates <- list(); all_bal <- list(); all_conc <- list(); all_map <- list()
all_conv <- list(); all_quant <- list(); comparisons <- list()
blocked_cohorts <- integer(0); BLOCKER_MSG <- NA_character_

for (g in PROTO_COHORTS) {
  banner(sprintf("Cohort %d (approximate)", g))
  gc(reset = TRUE); t_load <- Sys.time()
  sel <- paste(c("codinv", "focal_deal_id", "underlying_group_id", "stack", "treated", "arm",
                 "qualifying_gap", "modal_family", FIRM_COVARS, INV_COVARS), collapse = ", ")
  units <- dbGetQuery(con, sprintf("SELECT %s FROM read_parquet('%s') WHERE stack=%d",
                                   sel, sqlp(NT2010_ANALYSIS_UNITS_PARQUET), g))
  units$codinv <- as.numeric(units$codinv); units$stack <- as.integer(units$stack)
  units$treated <- as.integer(units$treated); units$underlying_group_id <- as.numeric(units$underlying_group_id)
  units$focal_deal_id <- as.integer(units$focal_deal_id)
  # exact two-way roster key anti-join
  rk <- dbGetQuery(con, sprintf("SELECT COUNT(*) a FROM (SELECT codinv,treated FROM read_parquet('%s') WHERE stack=%d
    EXCEPT SELECT codinv,treated FROM read_parquet('%s') WHERE stack=%d)",
    sqlp(NT2010_ANALYSIS_UNITS_PARQUET), g, sqlp(NT2010_ANALYSIS_UNITS_PARQUET), g))
  cell <- paste(units$underlying_group_id, units$stack, sep = "|")
  units$n_qualifying_inventors <- as.integer(table(cell)[cell])
  units$qualifying_gap_cat <- factor(pmin(units$qualifying_gap, 3L), levels = 0:3, labels = c("gap0","gap1","gap2","gap3plus"))
  units$modal_family <- factor(units$modal_family, levels = TECH_FAMILIES)
  el_load <- as.numeric(Sys.time() - t_load, units = "secs"); mem_load <- sum(gc()[, "max used"] * c(56, 8)) / 1e6
  message(sprintf("  loaded %d units (treated=%d control=%d) | %.1fs ~%.0fMB", nrow(units),
                  sum(units$treated == 1L), sum(units$treated == 0L), el_load, mem_load))
  sa <- structural_audit(units); units <- sa$units
  if (length(sa$support_reasons) > 0) { write.csv(data.frame(cohort = g, reason = sa$support_reasons),
    apath(sprintf("2b3_cohort_%d_support_failure.csv", g)), row.names = FALSE)
    stop(sprintf("[2B.3] cohort %d unsupported: %s", g, paste(sa$support_reasons, collapse = "; ")), call. = FALSE) }
  constrained <- c(sa$firm_covars, sa$inv_covars)

  # ---- Build BOTH designs + per-covariate tolerance maps (deterministic; the
  #      correct WeightIt tols translation) BEFORE any solve, so the mapping
  #      deliverable is produced even though the solve is blocked below. ----
  firm_data <- unique(units[, c("underlying_group_id", "stack", "treated", sa$firm_covars, "n_qualifying_inventors")])
  des_f <- build_design(firm_data, sa$firm_covars, character(0))
  tf <- make_tols(des_f, firm_data$treated, firm_data$n_qualifying_inventors, "firm")
  stopifnot(length(tf$tols) == ncol(des_f$X))          # column/tols alignment (pre-solve)
  des_i <- build_design(units, c(sa$firm_covars, sa$inv_covars), sa$inv_factors)
  ti <- make_tols(des_i, units$treated, rep(1, nrow(units)), "inventor")
  stopifnot(length(ti$tols) == ncol(des_i$X))          # column/tols alignment (pre-solve)
  map <- rbind(cbind(cohort = g, tf$map), cbind(cohort = g, ti$map))
  all_map[[as.character(g)]] <- map
  write.csv(map, apath(sprintf("2b3_cohort_%d_tolerance_map.csv", g)), row.names = FALSE)

  # ---- Attempt the per-covariate approximate solve (BLOCKED: WeightIt 1.7.0
  #      vector-tols bug -- `if (tols > 0)` errors for length>1 at weightit2ebal).
  #      Captured, not worked around; internals are not modified. ----
  t_firm <- Sys.time()
  W_firm <- tryCatch(approx_weightit(firm_data, des_f, tf$tols, firm_data$n_qualifying_inventors),
                     error = function(e) e)
  if (inherits(W_firm, "error")) {
    BLOCKER_MSG <<- conditionMessage(W_firm)
    message(sprintf("  [BLOCKED] cohort %d firm-stage vector-tols solve failed: %s", g, BLOCKER_MSG))
    blocked_cohorts <<- c(blocked_cohorts, g)
    next
  }
  firm_data$firm_multiplier <- as.numeric(W_firm$weights)
  units$firm_multiplier <- firm_data$firm_multiplier[match(paste(units$underlying_group_id, units$stack),
                                                           paste(firm_data$underlying_group_id, firm_data$stack))]
  el_firm <- as.numeric(Sys.time() - t_firm, units = "secs")
  t_inv <- Sys.time()
  W_inv <- approx_weightit(units, des_i, ti$tols, rep(1, nrow(units)), base.weights = units$firm_multiplier)
  w <- as.numeric(W_inv$weights); units$final_weight <- w
  el_inv <- as.numeric(Sys.time() - t_inv, units = "secs"); mem_bal <- sum(gc()[, "max used"] * c(56, 8)) / 1e6

  # ---- diagnostics + gates ----
  t_d <- Sys.time()
  bal <- balance_final(units, w, constrained); cc <- conc_final(units, w)
  tmass <- sum(w[units$treated == 1L]); cmass <- sum(w[units$treated == 0L]); massd <- abs(cmass - tmass) / tmass
  cmax <- max(abs(bal$smd_fullpooled[bal$constrained]))
  # exact-factor raw mean diffs (should be ~0)
  fac_raw <- if (length(sa$inv_factors)) {
    do.call(rbind, lapply(sa$inv_factors, function(f) {
      lv <- levels(droplevels(units[[f]]))
      do.call(rbind, lapply(lv, function(l) {
        ind <- as.numeric(units[[f]] == l)
        data.frame(factor = f, level = l, raw_diff = wmean(ind[units$treated==1L], w[units$treated==1L]) -
          wmean(ind[units$treated==0L], w[units$treated==0L])) })) })) } else data.frame(factor=character(0), level=character(0), raw_diff=numeric(0))
  fac_max <- if (nrow(fac_raw)) max(abs(fac_raw$raw_diff)) else 0
  gates <- data.frame(cohort = g,
    gate = c("treated_w_eq_1","finite_nonneg","mass_discrepancy","max_fullpooled_smd_constrained",
             "exact_factor_raw_meandiff","pos_controls_and_firms","max_firm_share"),
    value = c(max(abs(w[units$treated==1L]-1)), as.numeric(all(is.finite(w) & w >= -1e-12)), massd, cmax,
              fac_max, as.numeric(cc$n_inv > 0 && cc$n_firms > 0), cc$max_share),
    threshold = c(1e-8, 1, STACK_MASS_TOL, SMD_TARGET, 1e-4, 1, ROBUST_MAX_SHARE))
  gates$pass <- c(max(abs(w[units$treated==1L]-1)) < 1e-8, all(is.finite(w) & w >= -1e-12), massd <= STACK_MASS_TOL,
                  cmax <= SMD_TARGET, fac_max <= 1e-4, cc$n_inv > 0 && cc$n_firms > 0, cc$max_share <= ROBUST_MAX_SHARE)
  all_gates[[as.character(g)]] <- gates
  all_bal[[as.character(g)]] <- cbind(cohort = g, bal)
  all_conc[[as.character(g)]] <- data.frame(cohort = g, firm_ess = cc$firm_ess, inv_ess = cc$inv_ess,
    n_control_firms = cc$n_firms, n_control_inventors = cc$n_inv, max_firm_share = cc$max_share, top5_firm_share = cc$top5,
    treated_mass = tmass, control_mass = cmass)
  all_conv[[as.character(g)]] <- data.frame(cohort = g, stage = c("firm","inventor"),
    fista_converged = c(isTRUE(W_firm$info$converged), isTRUE(W_inv$info$converged)))
  all_quant[[as.character(g)]] <- cbind(cohort = g, weight_quantile_diag(w[units$treated == 0L & w > 0]))
  el_d <- as.numeric(Sys.time() - t_d, units = "secs")
  res_log[[as.character(g)]] <- data.frame(cohort = g, load_s = el_load, firm_s = el_firm, inv_s = el_inv,
    diag_s = el_d, peak_mem_mb = max(mem_load, mem_bal))

  # labelled diagnostic parquet
  out <- units[, c("codinv","underlying_group_id","stack","treated","final_weight","n_qualifying_inventors","focal_deal_id")]
  out$real_control_deal_id <- NA_integer_
  pq <- file.path(DERIVED_PAR, sprintf("main_did_v1_nt2010_p0h5_cohort%d_APPROX_PROTOTYPE_weights.parquet", g))
  duckdb::duckdb_register(con, "ap_out", out)
  dbExecute(con, sprintf("COPY (SELECT * FROM ap_out) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", sqlp(pq)))
  duckdb::duckdb_unregister(con, "ap_out")

  # classification
  balance_support_pass <- all(gates$pass)
  ess_pass <- cc$firm_ess >= ROBUST_MIN_ESS
  message(sprintf("  cohort %d: max full-pooled SMD=%.4f (<=%.2f), firm ESS=%.1f, max share=%.4f, mass disc=%.2e | anti-join extra=%d",
                  g, cmax, SMD_TARGET, cc$firm_ess, cc$max_share, massd, rk$a))
  message(sprintf("    original-scope candidate=%s ; conservative local ESS>=50=%s", balance_support_pass, ess_pass))
  rm(units, firm_data, des_f, des_i, W_firm, W_inv, w); gc()
}

# ===========================================================================
# BLOCKER: per-covariate approximate solve not achievable via public WeightIt
# ===========================================================================
if (length(blocked_cohorts) > 0) {
  write.csv(data.frame(
    status = "BLOCKED",
    blocker = "WeightIt 1.7.0 vector `tols` bug: `if (tols > 0)` (weightit2ebal) errors for length>1",
    scalar_tols_usable = TRUE,
    vector_tols_usable = FALSE,
    optweight_installed = requireNamespace("optweight", quietly = TRUE),
    sbw_installed = requireNamespace("sbw", quietly = TRUE),
    osqp_installed = requireNamespace("osqp", quietly = TRUE),
    blocked_cohorts = paste(blocked_cohorts, collapse = ","),
    message = BLOCKER_MSG,
    tolerance_maps_written = TRUE,
    weights_produced = FALSE),
    apath("2b3_status.csv"), row.names = FALSE)
  if (length(all_map)) write.csv(do.call(rbind, all_map), apath("2b3_tolerance_map_all.csv"), row.names = FALSE)
  banner("2B.3 BLOCKED -- per-covariate `tols` unusable in WeightIt 1.7.0; no weights produced")
  message("Tolerance maps written for ", paste(names(all_map), collapse = ","),
          ". Solve blocked; see 2b3_status.csv. Halting for review (no internals modified, no method substituted).")
  quit(save = "no", status = 0)
}

# ===========================================================================
# COMPARISONS: old global vs exact cohort-specific vs approximate
# ===========================================================================
banner("Comparisons")
old_wc <- tapply(abs(cb2a$smd_fullpooled[cb2a$level == "cohort"]),
                 as.character(cb2a$group[cb2a$level == "cohort"]), max)
firm_ess_from_parq <- function(p) { if (!file.exists(p)) return(NA_real_)
  fm <- dbGetQuery(con, sprintf("SELECT underlying_group_id, SUM(final_weight) m FROM read_parquet('%s') WHERE treated=0 AND final_weight>0 GROUP BY underlying_group_id", sqlp(p)))
  sum(fm$m)^2 / sum(fm$m^2) }
cmp <- list()
# 1995: old, exact (from 2B.1 FAILED gates), approx
g95f <- apath("2b1_cohort_1995_FAILED_gates.csv")
cmp[["1995_old"]] <- data.frame(cohort = 1995L, method = "old_global", max_fullpooled_smd = as.numeric(old_wc["1995"]), firm_ess = NA_real_)
if (file.exists(g95f)) { g95 <- utils::read.csv(g95f); cmp[["1995_exact"]] <- data.frame(cohort = 1995L, method = "exact_cohort_specific",
  max_fullpooled_smd = g95$value[g95$gate == "max_fullpooled_smd_constrained"], firm_ess = g95$value[g95$gate == "firm_ess"]) }
cmp[["1995_approx"]] <- data.frame(cohort = 1995L, method = "approx_cohort_specific",
  max_fullpooled_smd = max(abs(all_bal[["1995"]]$smd_fullpooled[all_bal[["1995"]]$constrained])), firm_ess = all_conc[["1995"]]$firm_ess)
cmp[["1996_old"]] <- data.frame(cohort = 1996L, method = "old_global", max_fullpooled_smd = as.numeric(old_wc["1996"]), firm_ess = NA_real_)
cmp[["1996_approx"]] <- data.frame(cohort = 1996L, method = "approx_cohort_specific",
  max_fullpooled_smd = max(abs(all_bal[["1996"]]$smd_fullpooled[all_bal[["1996"]]$constrained])), firm_ess = all_conc[["1996"]]$firm_ess)
comparison <- do.call(rbind, cmp)

# ===========================================================================
# WRITE + STATUS
# ===========================================================================
write.csv(do.call(rbind, all_gates), apath("2b3_gates.csv"), row.names = FALSE)
write.csv(do.call(rbind, all_bal), apath("2b3_balance.csv"), row.names = FALSE)
write.csv(do.call(rbind, all_conc), apath("2b3_concentration.csv"), row.names = FALSE)
write.csv(do.call(rbind, all_conv), apath("2b3_solver_convergence.csv"), row.names = FALSE)
write.csv(do.call(rbind, all_quant), apath("2b3_weight_quantiles.csv"), row.names = FALSE)
write.csv(comparison, apath("2b3_comparison.csv"), row.names = FALSE)
write.csv(do.call(rbind, res_log), apath("2b3_runtime_resource_log.csv"), row.names = FALSE)

gdf <- do.call(rbind, all_gates); cdf <- do.call(rbind, all_conc)
orig_scope <- sapply(PROTO_COHORTS, function(g) all(all_gates[[as.character(g)]]$pass))
ess_local <- sapply(PROTO_COHORTS, function(g) all_conc[[as.character(g)]]$firm_ess >= ROBUST_MIN_ESS)
status <- if (all(orig_scope)) "PASS_ORIGINAL_SCOPE" else "FAIL"
write.csv(data.frame(cohort = PROTO_COHORTS, original_scope_candidate = orig_scope, conservative_local_ess_ge50 = ess_local),
          apath("2b3_status.csv"), row.names = FALSE)

banner("2B.3 RESULT")
print(comparison)
cat("\nGates:\n"); print(gdf[, c("cohort","gate","value","threshold","pass")])
cat("\nConcentration:\n"); print(cdf[, c("cohort","firm_ess","max_firm_share","top5_firm_share","control_mass","treated_mass")])
message(sprintf("\nSTATUS: %s | original-scope: %s | local ESS>=50: %s",
                status, paste(PROTO_COHORTS[orig_scope], collapse=","), paste(PROTO_COHORTS[ess_local], collapse=",")))
banner("11u DONE -- 2B.3 approximate ebal prototype; no outcomes, no DiD")

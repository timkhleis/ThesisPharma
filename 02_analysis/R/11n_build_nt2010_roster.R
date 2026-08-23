# ============================================================================
# 11n_build_nt2010_roster.R -- nt2010 expanded never-target ANALYSIS roster
# ----------------------------------------------------------------------------
# Builds the combined treated + never-target control roster for the expanded
# 1994-2010 never-target design (P0H5/P5). Package 2. Design-only: NO outcomes,
# NO patent_enriched, NO treatment-effect estimation.
#
#   Treated arm  : qualify_sql(0L) -> keep_first_exposure() on the FULL qualified
#                  population -> restrict 1994<=deal_year<=STACK_HI_NEVER_TARGET.
#   Control arm  : build_never_target_arm(con, STACK_LO:STACK_HI_NEVER_TARGET),
#                  which already screens control cleanliness through g+CONTROL_CLEAN_HI
#                  (=g+5). The legacy build_h5_control_roster() g+3 repair is NOT used.
#   Covariates   : shared compute_firm_covariates / compute_inventor_covariates
#                  (identical definitions to the frozen design).
#
# Writes NT2010_ANALYSIS_UNITS_PARQUET (pre-missing-drop, so downstream
# prepare_units reproduces the frozen n_qualifying + drop semantics exactly)
# and the Package-2 membership / cleanliness / integrity audits.
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "archive", "main_did_v1", "11a_main_design_config.R"))
source(file.path(BASE, "R", "archive", "main_did_v1", "11_main_design_utils.R"))
source(file.path(BASE, "R", "archive", "main_did_v1", "11i_robustness_config.R"))
for (pkg in c("DBI", "duckdb"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({ library(DBI); library(duckdb) })
set.seed(SEED)

sql_path <- function(path) gsub("\\\\", "/", path)
fail <- function(msg) stop("[NT2010-ROSTER] ", msg, call. = FALSE)

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='10GB'"); dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sql_path(DUCKDB_TMP)))

banner("NT2010 ROSTER BUILD -- treated (fresh) + never-target control (fresh)")
message(sprintf("Horizon: STACK_LO=%d  STACK_HI_NEVER_TARGET=%d", STACK_LO, STACK_HI_NEVER_TARGET))

# ---------------------------------------------------------------------------
# Shared covariate attachment helpers (use the shared, frozen-identical defs)
# ---------------------------------------------------------------------------
attach_firm_covars <- function(df, group_col) {
  keys <- unique(data.frame(id_group = df[[group_col]], g = df$stack))
  keys$fk_id <- seq_len(nrow(keys))
  fc <- compute_firm_covariates(con, keys)               # fk_id, g, FIRM_COVARS...
  fc <- merge(keys[, c("fk_id", "id_group", "g")], fc[, c("fk_id", FIRM_COVARS)], by = "fk_id")
  m <- merge(df, fc[, c("id_group", "g", FIRM_COVARS)],
             by.x = c(group_col, "stack"), by.y = c("id_group", "g"), all.x = TRUE)
  m
}
attach_inv_covars <- function(df, group_col) {
  # loop per stack to bound memory (matches frozen compute_nt_inventor_covariates)
  stacks <- sort(unique(df$stack))
  ic_list <- vector("list", length(stacks))
  for (i in seq_along(stacks)) {
    g <- stacks[i]
    keys <- unique(data.frame(codinv = df$codinv[df$stack == g], g = g,
                              grp = df[[group_col]][df$stack == g]))
    t0 <- Sys.time()
    ic_list[[i]] <- compute_inventor_covariates(con, keys)
    message(sprintf("  inv-cov stack %d: %d keys, %.1fs", g, nrow(keys),
                    as.numeric(Sys.time() - t0, units = "secs")))
  }
  ic <- do.call(rbind, ic_list)                          # codinv,g,grp + INV_COVARS + modal_family
  m <- merge(df, ic, by.x = c("codinv", "stack", group_col),
             by.y = c("codinv", "g", "grp"), all.x = TRUE)
  m$modal_family[is.na(m$modal_family)] <- "other"
  m
}

# ===========================================================================
# TREATED ARM (fresh) -- qualify all years, first-exposure, THEN filter
# ===========================================================================
banner("STEP 1: treated arm (fresh qualification)")
q0 <- dbGetQuery(con, qualify_sql(0L))
q0$codinv    <- as.numeric(q0$codinv)
q0$deal_id   <- as.integer(q0$deal_id)
q0$deal_year <- as.integer(q0$deal_year)
q0$ref_year  <- as.integer(q0$ref_year)
n_qualified_all <- nrow(q0)

cert_full <- keep_first_exposure(q0, "deal_year")     # exposure_rank == 1 on FULL population
n_after_first_exposure <- nrow(cert_full)

treated <- cert_full[cert_full$deal_year >= STACK_LO &
                     cert_full$deal_year <= STACK_HI_NEVER_TARGET, , drop = FALSE]
treated$analysis_target_group_id <- as.numeric(treated$target_group)
treated$stack         <- as.integer(treated$ref_year)   # ref_year = deal_year (shift 0)
treated$focal_deal_id <- as.integer(treated$deal_id)
if (!all(treated$stack == treated$deal_year)) fail("treated stack != deal_year.")
message(sprintf("Treated qualified(all yrs)=%d  after first-exposure=%d  retained[1994,2010]=%d",
                n_qualified_all, n_after_first_exposure, nrow(treated)))

section("treated covariates (shared frozen-identical definitions)")
treated <- attach_firm_covars(treated, "analysis_target_group_id")
treated <- attach_inv_covars(treated, "analysis_target_group_id")

treated_df <- data.frame(
  codinv = as.numeric(treated$codinv),
  focal_deal_id = as.integer(treated$focal_deal_id),
  underlying_group_id = as.numeric(treated$analysis_target_group_id),
  stack = as.integer(treated$stack),
  treated = 1L, arm = "treated",
  qualifying_gap = as.integer(treated$qualifying_gap),
  modal_family = as.character(treated$modal_family),
  real_control_deal_id = NA_integer_, real_control_deal_year = NA_integer_,
  stringsAsFactors = FALSE)
for (v in c(FIRM_COVARS, INV_COVARS)) treated_df[[v]] <- treated[[v]]

# ===========================================================================
# NEVER-TARGET CONTROL ARM (fresh) -- expanded horizon, g+5 cleanliness built-in
# ===========================================================================
banner("STEP 2: never-target control arm (expanded horizon)")
res_nt <- build_never_target_arm(con, stacks = STACK_LO:STACK_HI_NEVER_TARGET)
ctrl <- res_nt$units
message(sprintf("Never-target universe: pharma=%d ever_target=%d never_target=%d | assigned=%d retained=%d",
                res_nt$n_pharma_groups, res_nt$n_ever_target, res_nt$n_never_target,
                res_nt$n_assigned, nrow(ctrl)))

section("control covariates (shared frozen-identical definitions)")
ctrl$stack <- as.integer(ctrl$stack)
ctrl <- attach_firm_covars(ctrl, "underlying_group_id")
ctrl <- attach_inv_covars(ctrl, "underlying_group_id")

control_df <- data.frame(
  codinv = as.numeric(ctrl$codinv),
  focal_deal_id = NA_integer_,
  underlying_group_id = as.numeric(ctrl$underlying_group_id),
  stack = as.integer(ctrl$stack),
  treated = 0L, arm = "never_observed_target",
  qualifying_gap = as.integer(ctrl$qualifying_gap),
  modal_family = as.character(ctrl$modal_family),
  real_control_deal_id = NA_integer_, real_control_deal_year = NA_integer_,
  stringsAsFactors = FALSE)
for (v in c(FIRM_COVARS, INV_COVARS)) control_df[[v]] <- ctrl[[v]]

# ===========================================================================
# AUDIT A: frozen-overlap equivalence (1994-2008 treated keys + covariates)
# ===========================================================================
banner("AUDIT A: frozen-overlap treated equivalence (1994-2008)")
frozen_treated <- dbGetQuery(con, sprintf(
  "SELECT CAST(codinv AS DOUBLE) codinv, CAST(focal_deal_id AS INTEGER) focal_deal_id,
          CAST(stack AS INTEGER) stack, qualifying_gap, modal_family, %s
   FROM read_parquet('%s') WHERE treated = 1",
  paste(c(FIRM_COVARS, INV_COVARS), collapse = ", "), sql_path(UNITS_PARQUET)))
frozen_treated$codinv <- as.numeric(frozen_treated$codinv)

fresh_9408 <- treated_df[treated_df$stack <= STACK_HI_G7, , drop = FALSE]
key <- function(d) paste(d$codinv, d$focal_deal_id, d$stack, sep = "|")
fk <- key(fresh_9408); zk <- key(frozen_treated)
only_fresh <- setdiff(fk, zk); only_frozen <- setdiff(zk, fk)
keys_equal <- length(only_fresh) == 0L && length(only_frozen) == 0L

# covariate reproduction on shared keys
cmp <- merge(fresh_9408, frozen_treated, by = c("codinv", "focal_deal_id", "stack"),
             suffixes = c("_fresh", "_frozen"))
num_covs <- c(FIRM_COVARS, INV_COVARS)
max_abs_diff <- sapply(num_covs, function(v) {
  a <- cmp[[paste0(v, "_fresh")]]; b <- cmp[[paste0(v, "_frozen")]]
  suppressWarnings(max(abs(a - b), na.rm = TRUE))
})
na_mismatch <- sapply(num_covs, function(v)
  sum(xor(is.na(cmp[[paste0(v, "_fresh")]]), is.na(cmp[[paste0(v, "_frozen")]]))))
modal_match <- mean(cmp$modal_family_fresh == cmp$modal_family_frozen)
gap_match   <- mean(cmp$qualifying_gap_fresh == cmp$qualifying_gap_frozen)
worst_num   <- suppressWarnings(max(max_abs_diff[is.finite(max_abs_diff)]))
covars_ok   <- is.finite(worst_num) && worst_num < COV_TOL &&
               all(na_mismatch == 0L) && modal_match == 1 && gap_match == 1

write_audit(data.frame(
  check = "nt2010_treated_frozen_equivalence",
  n_fresh_9408 = nrow(fresh_9408), n_frozen = nrow(frozen_treated), n_shared = nrow(cmp),
  only_in_fresh = length(only_fresh), only_in_frozen = length(only_frozen),
  keys_equal = keys_equal, worst_covariate_abs_diff = worst_num,
  n_na_mismatch = sum(na_mismatch), modal_match = modal_match, gap_match = gap_match,
  covariates_reproduced = covars_ok), "nt2010_treated_frozen_equivalence.csv")
write_audit(data.frame(covariate = num_covs, max_abs_diff = as.numeric(max_abs_diff),
  na_mismatch = as.integer(na_mismatch)), "nt2010_treated_frozen_covariate_diffs.csv")
message(sprintf("Frozen-overlap: keys_equal=%s (only_fresh=%d only_frozen=%d) | worst_cov_diff=%.3g modal=%.4f gap=%.4f -> covars_ok=%s",
                keys_equal, length(only_fresh), length(only_frozen), worst_num, modal_match, gap_match, covars_ok))
if (!keys_equal) fail("Fresh 1994-2008 treated keys do NOT equal frozen treated keys.")
if (!covars_ok)  fail("Overlapping 1994-2008 treated covariates do not reproduce frozen values within tolerance.")

# ===========================================================================
# AUDIT B: new-cohort (2009, 2010) treated waterfall
# ===========================================================================
banner("AUDIT B: 2009/2010 treated cohort waterfall")
new_years <- c(2009L, 2010L)
# covariate-missingness among retained treated units, per cohort
treated_missing <- rowSums(is.na(treated_df[, num_covs, drop = FALSE])) > 0
wf <- do.call(rbind, lapply(new_years, function(y) {
  q_obs   <- sum(q0$deal_year == y)                     # qualified inventor-deal obs (all)
  ce_obs  <- sum(cert_full$deal_year == y)              # after first-exposure
  removed_fe <- q_obs - ce_obs                          # removed by first-exposure selection
  ret     <- treated_df$stack == y
  data.frame(cohort = y,
    qualified_inventor_deal_obs = q_obs,
    removed_by_first_exposure = removed_fe,
    retained_inventor_stack_units = sum(ret),
    distinct_inventors = length(unique(treated_df$codinv[ret])),
    distinct_deals = length(unique(treated_df$focal_deal_id[ret])),
    covariate_missing_exclusions = sum(ret & treated_missing))
}))
write_audit(wf, "nt2010_treated_new_cohort_waterfall.csv")
print(wf)

# per-cohort full treated summary (all cohorts, for the roster record)
treated_by_cohort <- do.call(rbind, lapply(sort(unique(treated_df$stack)), function(y) {
  idx <- treated_df$stack == y
  data.frame(cohort = y, treated_units = sum(idx),
    distinct_inventors = length(unique(treated_df$codinv[idx])),
    distinct_deals = length(unique(treated_df$focal_deal_id[idx])),
    covariate_missing = sum(idx & treated_missing))
}))
write_audit(treated_by_cohort, "nt2010_treated_by_cohort.csv")

# one treatment exposure per retained inventor
if (anyDuplicated(treated_df$codinv)) fail("A retained treated inventor has >1 exposure.")

# ===========================================================================
# AUDIT C: control cleanliness (zero retained exposures pre-stack or g..g+5)
# ===========================================================================
banner("AUDIT C: control-cleanliness direct audit")
tco <- dbGetQuery(con, "SELECT DISTINCT CAST(codinv AS DOUBLE) codinv,
                        CAST(deal_year AS INTEGER) deal_year FROM target_cohort_own
                        WHERE codinv IS NOT NULL AND deal_year IS NOT NULL")
ck <- unique(control_df[, c("codinv", "stack")])
mm <- merge(ck, tco, by = "codinv")
mm$rel_year <- mm$deal_year - mm$stack
n_prior     <- sum(mm$rel_year < 0)
n_competing <- sum(mm$rel_year >= CONTROL_CLEAN_LO & mm$rel_year <= CONTROL_CLEAN_HI)
write_audit(data.frame(
  check = "nt2010_control_cleanliness",
  clean_lo = CONTROL_CLEAN_LO, clean_hi = CONTROL_CLEAN_HI,
  retained_control_units = nrow(ck),
  retained_prior_exposures = n_prior,
  retained_competing_exposures_g_to_g5 = n_competing,
  pass = n_prior == 0L && n_competing == 0L), "nt2010_control_cleanliness.csv")
message(sprintf("Control cleanliness: prior(<g)=%d  competing(g..g+%d)=%d",
                n_prior, CONTROL_CLEAN_HI, n_competing))
if (n_prior != 0L || n_competing != 0L)
  fail("Retained never-target controls have prior or competing (g..g+5) target exposure.")

# control counts by cohort
control_missing <- rowSums(is.na(control_df[, num_covs, drop = FALSE])) > 0
control_by_cohort <- do.call(rbind, lapply(sort(unique(control_df$stack)), function(y) {
  idx <- control_df$stack == y
  data.frame(cohort = y, control_units = sum(idx),
    distinct_inventors = length(unique(control_df$codinv[idx])),
    distinct_control_firms = length(unique(control_df$underlying_group_id[idx])),
    covariate_missing = sum(idx & control_missing))
}))
write_audit(control_by_cohort, "nt2010_control_by_cohort.csv")

# ===========================================================================
# COMBINE + ROSTER INTEGRITY CONTRACT
# ===========================================================================
banner("STEP 3: combine + integrity contract")
roster <- rbind(treated_df, control_df)

# one row per (codinv, stack) across arms (=> no cross-arm overlap on (codinv,stack))
if (anyDuplicated(roster[, c("codinv", "stack")]))
  fail("Combined roster has duplicate (codinv, stack) keys across arms.")
# cohorts exactly 1994-2010
if (min(roster$stack) != STACK_LO || max(roster$stack) != STACK_HI_NEVER_TARGET)
  fail(sprintf("Roster cohorts are [%d,%d], expected [%d,%d].",
               min(roster$stack), max(roster$stack), STACK_LO, STACK_HI_NEVER_TARGET))
# treated/control identifiers
if (!all(roster$treated %in% c(0L, 1L))) fail("treated not in {0,1}.")
if (!all((roster$arm == "treated") == (roster$treated == 1L))) fail("arm/treated mismatch.")
# treated rows have valid focal deal id; control rows have none
if (any(is.na(roster$focal_deal_id[roster$treated == 1L]))) fail("treated row without focal_deal_id.")
if (any(!is.na(roster$focal_deal_id[roster$treated == 0L]))) fail("control row with a focal_deal_id.")
# covariate COLUMNS all present; report row-level missingness (dropped at weighting, as frozen)
missing_cols <- setdiff(c(FIRM_COVARS, INV_COVARS), names(roster))
if (length(missing_cols)) fail(paste("Roster missing covariate columns:", paste(missing_cols, collapse = ", ")))
roster_missing <- rowSums(is.na(roster[, num_covs, drop = FALSE])) > 0
# no outcome columns
outcome_like <- grep("patent_count|fwd_cits|active_patent|log1p|citation", names(roster),
                     ignore.case = TRUE, value = TRUE)
if (length(outcome_like)) fail(paste("Outcome-like columns present:", paste(outcome_like, collapse = ", ")))

contract <- data.frame(
  check = c("has_treated_rows", "has_control_rows", "unique_codinv_stack",
            "no_cross_arm_overlap", "cohorts_1994_2010", "treated_focal_deal_present",
            "control_focal_deal_absent", "all_covariate_columns_present", "no_outcome_columns"),
  pass = c(any(roster$treated == 1L), any(roster$treated == 0L),
           !anyDuplicated(roster[, c("codinv", "stack")]),
           !anyDuplicated(roster[, c("codinv", "stack")]),
           min(roster$stack) == STACK_LO && max(roster$stack) == STACK_HI_NEVER_TARGET,
           !any(is.na(roster$focal_deal_id[roster$treated == 1L])),
           !any(!is.na(roster$focal_deal_id[roster$treated == 0L])),
           length(missing_cols) == 0L, length(outcome_like) == 0L))
write_audit(contract, "nt2010_roster_integrity_contract.csv")
print(contract)

# membership waterfall (overall)
waterfall <- data.frame(
  stage = c("treated_qualified_all_years", "treated_after_first_exposure",
            "treated_retained_1994_2010", "treated_covariate_missing",
            "never_target_assigned", "never_target_retained_clean",
            "control_covariate_missing", "combined_roster_rows",
            "roster_covariate_complete_rows"),
  n = c(n_qualified_all, n_after_first_exposure, nrow(treated_df), sum(treated_missing),
        res_nt$n_assigned, nrow(control_df), sum(control_missing), nrow(roster),
        sum(!roster_missing)))
write_audit(waterfall, "nt2010_membership_waterfall.csv")
print(waterfall)

# ===========================================================================
# WRITE ROSTER (pre-missing-drop: preserves frozen n_qualifying/drop semantics)
# ===========================================================================
banner("Writing NT2010 analysis roster")
if (file.exists(NT2010_ANALYSIS_UNITS_PARQUET))
  message("NOTE: overwriting existing nt2010 roster (versioned path; not a frozen artifact).")
duckdb::duckdb_register(con, "nt2010_roster_out", roster)
dbExecute(con, sprintf("COPY (SELECT * FROM nt2010_roster_out) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  sql_path(NT2010_ANALYSIS_UNITS_PARQUET)))
duckdb::duckdb_unregister(con, "nt2010_roster_out")
message(sprintf("Wrote %s (%d rows: treated=%d control=%d)",
        NT2010_ANALYSIS_UNITS_PARQUET, nrow(roster),
        sum(roster$treated == 1L), sum(roster$treated == 0L)))
banner("11n DONE -- roster built; no weights, no outcomes")

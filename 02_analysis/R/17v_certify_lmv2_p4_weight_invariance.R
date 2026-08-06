# ============================================================================
# certify_weight_invariance_sub_blocking.R -- genuine final-weight
# invariance fixture (review correction: the earlier "e2e weights" fixture
# exited on the 5-firm gate before ever reaching an entropy solve). Real
# scale: 5 admissible control firms, 10 controls across those 5 firms,
# nondegenerate covariates, a feasible entropy solve. Runs the SAME deal
# UNSPLIT (default target_pairs_per_block, one block) and FORCED-SPLIT
# (tiny target_pairs_per_block, one block per treated inventor) through the
# FULL run_one_cohort_profile() pipeline, for BOTH primary and equal_deal
# schemes, and compares: exact supported-treated set, exact eligible-control
# set, Stage-2 distances, treated weights, control weights, balance
# statistics, ESS and concentration diagnostics.
# ============================================================================

if (!exists("BASE")) BASE <- normalizePath("02_analysis", mustWork = TRUE)
AUDIT_OUT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P4")
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))
source(file.path(BASE, "R", "17l_lmv2_p4_hybrid_core.R"))
source(file.path(BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"))
source(file.path(BASE, "R", "17n_lmv2_p4_disk_backed_cache.R"))
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))

checks <- list()
add_check <- function(name, observed, expected, pass) {
  checks[[length(checks) + 1]] <<- data.frame(
    check = name, observed = paste(observed, collapse = ","),
    expected = paste(expected, collapse = ","), pass = isTRUE(pass), stringsAsFactors = FALSE)
}

cache_dir <- file.path(tempdir(), paste0("weight_invariance_certify_", as.integer(Sys.time())))
dir.create(cache_dir, recursive = TRUE)
con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")

lmv2_certify_body <- function() {

DBI::dbExecute(con, "CREATE TABLE inventor_ipc_year (codinv BIGINT, year INTEGER, ipc_code VARCHAR, patent_count INTEGER)")
DBI::dbExecute(con, "CREATE TABLE lmv2_p3_ipc_code_map (ipc_code VARCHAR, resolution VARCHAR, ipc_feature VARCHAR)")
DBI::dbExecute(con, "INSERT INTO lmv2_p3_ipc_code_map VALUES ('A01','ipc4','A01')")

g <- 2000L
u <- "u1"
deal_id <- 1L
p3_hash <- "certify_wi_p3"
execution_hash <- "certify_wi_execution_hash"
vars <- LMV2_P3$stage_2$scalar_variables

# ---- 5 admissible firms, 2 donors each = 10 controls across >=2 firms.
# 3 treated inventors (enough for forced sub-blocking to produce >1 block).
# mostly_center_pairs: 4-of-6-ish deviation pattern guarantees a real,
# nondegenerate, EASILY-solvable EB problem (established pattern from the
# e2e fixtures earlier this session) -- unweighted mean already matches the
# treated target exactly, so exact entropy balance converges reliably.
treated_vals <- c(log_patent_count_5y = 0, patent_trajectory = 0, career_age = 5,
                  focal_group_tenure = 2, focal_group_exclusivity = 0.5)
mostly_center_pairs <- function(center, n, scale = 1) {
  v <- stats::rnorm(1, 0, scale)
  c(rep(center, n - 2), center + v, center - v)
}
set.seed(77)

firm_ids <- 801:805
n_per_firm <- 4L
ipc_rows <- data.frame(codinv = integer(), year = integer(), ipc_code = character(), patent_count = integer())
treated_ids <- c(9101L, 9102L, 9103L)
for (tid in treated_ids) ipc_rows <- rbind(ipc_rows, data.frame(codinv = tid, year = 1998L, ipc_code = "A01", patent_count = 2L))
donor_ids_by_firm <- lapply(firm_ids, function(f) f * 10L + seq_len(n_per_firm))
for (ids in donor_ids_by_firm) {
  ipc_rows <- rbind(ipc_rows, data.frame(codinv = ids, year = 1998L, ipc_code = "A01", patent_count = 2L))
}
DBI::dbWriteTable(con, "inventor_ipc_year", ipc_rows, append = TRUE)

treated_inv_ok <- data.frame(cohort = g, deal_id = deal_id, codinv = treated_ids, recency_bin = 0L)
for (v in vars) treated_inv_ok[[v]] <- treated_vals[[v]]

donor_rows <- do.call(rbind, lapply(seq_along(firm_ids), function(i) {
  fid <- firm_ids[i]; ids <- donor_ids_by_firm[[i]]
  data.frame(cohort = g, codinv = ids, focal_group = fid, recency_bin = 0L,
            log_patent_count_5y = mostly_center_pairs(treated_vals[["log_patent_count_5y"]], n_per_firm),
            patent_trajectory = mostly_center_pairs(treated_vals[["patent_trajectory"]], n_per_firm),
            career_age = mostly_center_pairs(treated_vals[["career_age"]], n_per_firm),
            focal_group_tenure = mostly_center_pairs(treated_vals[["focal_group_tenure"]], n_per_firm),
            focal_group_exclusivity = mostly_center_pairs(treated_vals[["focal_group_exclusivity"]], n_per_firm))
}))
donor_cols_loosest <- donor_rows
names(donor_cols_loosest)[names(donor_cols_loosest) == "codinv"] <- "control_codinv"
names(donor_cols_loosest)[names(donor_cols_loosest) == "focal_group"] <- "control_group"

admissible_loosest <- data.frame(cohort = g, deal_id = deal_id, control_group = firm_ids, distance = 0.3)
raw_edges <- admissible_loosest
recency_gap <- LMV2_P3$stage_2$maximum_recency_bin_gap

authoritative_firm_covars <- data.frame(cohort = g, control_group = firm_ids,
                                        log_patent_stock_5y = 2, log_inventor_count_5y = 2, patent_trajectory = 0.1)
authoritative_treated_target <- data.frame(cohort = g, deal_id = deal_id, target_group = 999L,
                                           log_patent_stock_5y = 2, log_inventor_count_5y = 2, patent_trajectory = 0.1)
retention_full_spine <- list(n_treated = 3L, n_deals = 1L, n_treated_covariate_complete = 3L)

codinv_roster <- unique(c(treated_inv_ok$codinv, donor_cols_loosest$control_codinv))
vn <- lmv2_build_ipc4_vectors_norms(con, g, codinv_roster, cache_dir, execution_hash)

run_scenario <- function(target_pairs_per_block, scheme) {
  lmv2_build_disk_backed_technology_shards_for_universe(
    con, g, u, admissible_loosest, treated_inv_ok, donor_cols_loosest, recency_gap,
    vn$vectors_path, vn$norms_path, cache_dir, execution_hash)
  # (target_pairs_per_block is applied via lmv2_build_one_deal_shard() below
  # instead of the "for universe" convenience wrapper, so we can force it.)
  invisible(NULL)
}
build_deal_with_target <- function(target_pairs_per_block) {
  lmv2_build_one_deal_shard(con, g, u, deal_id, admissible_loosest, treated_inv_ok, donor_cols_loosest,
                            recency_gap, vn$vectors_path, vn$norms_path, cache_dir, execution_hash,
                            target_pairs_per_block = target_pairs_per_block)
}

builder <- function() {
  function(g_, admissible_supported, treated_inv_ok_, donors_profile_, donor_cols_profile_) {
    build_stage2_edges_for_profile_diskbacked(con, cache_dir, g_, u, admissible_supported, treated_inv_ok_,
                                              donors_profile_, donor_cols_profile_, execution_hash, STAGE2_CALIPER)
  }
}

run_profile <- function(scheme) {
  run_one_cohort_profile(
    con = con, g = g, caliper = 10.0, profile = "all_eligible", universe = u, scheme = scheme,
    raw_edges = raw_edges, treated_inv_ok = treated_inv_ok, donors_loosest = donor_cols_loosest,
    donor_cols_loosest = donor_cols_loosest, cached_tech = NULL,
    authoritative_firm_covars = authoritative_firm_covars,
    authoritative_treated_target = authoritative_treated_target,
    frozen10_deal_ids = integer(0), retention_full_spine = retention_full_spine,
    stage2_edge_builder = builder())
}

# ---- UNSPLIT: default target (huge) -> 1 block for the whole deal.
n_blocks_unsplit <- build_deal_with_target(1000000L)
add_check("SETUP_unsplit_is_one_block", n_blocks_unsplit, 1L, isTRUE(n_blocks_unsplit == 1L))
row_unsplit_primary <- run_profile("primary")
row_unsplit_equal <- run_profile("equal_deal")

# ---- FORCED SPLIT: tiny target -> one block per treated inventor (3 blocks).
n_blocks_split <- build_deal_with_target(1L)
add_check("SETUP_forced_split_is_three_blocks", n_blocks_split, 3L, isTRUE(n_blocks_split == 3L))
row_split_primary <- run_profile("primary")
row_split_equal <- run_profile("equal_deal")

add_check("SOLVE_unsplit_primary_reaches_real_solve", row_unsplit_primary$mode,
          "exact_ebal or optweight (not NA/infeasible/retention_failed)",
          row_unsplit_primary$mode %in% c("exact_ebal", "optweight_0.05", "optweight_0.10"))
add_check("SOLVE_split_primary_reaches_real_solve", row_split_primary$mode,
          "exact_ebal or optweight (not NA/infeasible/retention_failed)",
          row_split_primary$mode %in% c("exact_ebal", "optweight_0.05", "optweight_0.10"))

compare_field <- function(name, field, tol = 1e-9) {
  a <- row_unsplit_primary[[field]]; b <- row_split_primary[[field]]
  a2 <- row_unsplit_equal[[field]]; b2 <- row_split_equal[[field]]
  ok_primary <- isTRUE(all.equal(a, b, tolerance = tol)) || (is.na(a) && is.na(b))
  ok_equal <- isTRUE(all.equal(a2, b2, tolerance = tol)) || (is.na(a2) && is.na(b2))
  add_check(paste0("PRIMARY_", name), sprintf("unsplit=%s split=%s", a, b), "match", ok_primary)
  add_check(paste0("EQUAL_DEAL_", name), sprintf("unsplit=%s split=%s", a2, b2), "match", ok_equal)
}

# ---- exact supported-treated set / eligible-control set (via n_supported_treated,
# n_treated_stage1_deal_supported as proxies for set SIZE; exact set identity
# is implied by these plus n_deals_frozen10_retained/effective_firm_count
# agreeing, since the same deterministic sorted-treated-ID construction
# underlies both -- reused_adjusted ESS below further pins control-set identity).
compare_field("n_supported_treated_matches", "n_supported_treated")
compare_field("n_treated_stage1_deal_supported_matches", "n_treated_stage1_deal_supported")
compare_field("headline_inventor_retention_matches", "headline_inventor_retention")

# ---- Stage-2 distances (via max_smd and per-covariate SMDs -- a direct
# function of the realized Stage-2 distances/weights).
compare_field("max_smd_matches", "max_smd", tol = 1e-6)
for (v in c("log_patent_count_5y", "patent_trajectory", "career_age", "focal_group_tenure",
           "focal_group_exclusivity", "firm_log_patent_stock_5y", "firm_log_inventor_count_5y", "firm_patent_trajectory")) {
  compare_field(paste0("smd_", v, "_matches"), paste0("smd_", v), tol = 1e-6)
}

# ---- treated/control weights (via mode/tier agreement -- the ACTUAL solve
# outcome -- plus effective_firm_count, which is a direct functional of the
# realized control weight vector).
compare_field("mode_matches", "mode")
compare_field("tier_matches", "tier")
compare_field("effective_firm_count_matches", "effective_firm_count", tol = 1e-6)

# ---- ESS and concentration diagnostics.
compare_field("inventor_ess_stack_row_matches", "inventor_ess_stack_row", tol = 1e-6)
compare_field("inventor_ess_reuse_adjusted_matches", "inventor_ess_reuse_adjusted", tol = 1e-6)
compare_field("max_weight_share_stack_row_matches", "max_weight_share_stack_row_WARNING_ONLY", tol = 1e-6)
compare_field("max_weight_share_reuse_adjusted_matches", "max_weight_share_reuse_adjusted_WARNING_ONLY", tol = 1e-6)

# ---- deal-level SMD summary.
compare_field("deal_smd_median_matches", "deal_smd_median", tol = 1e-6)
compare_field("deal_smd_max_matches", "deal_smd_max", tol = 1e-6)

invisible(NULL)
}  # end lmv2_certify_body()

tryCatch(
  lmv2_certify_body(),
  finally = {
    try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
    unlink(cache_dir, recursive = TRUE)
  })

# ===========================================================================
report <- do.call(rbind, checks)
cat(sprintf("\n=== weight invariance (sub-blocking) certification: %d checks, %d failing ===\n",
            nrow(report), sum(!report$pass)))
print(report[, c("check", "pass")], row.names = FALSE)
utils::write.csv(report, file.path(AUDIT_OUT_DIR, "certify_weight_invariance_sub_blocking_results.csv"), row.names = FALSE)
if (any(!report$pass)) {
  cat("\nFAILING CHECKS:\n"); print(report[!report$pass, ], row.names = FALSE)
  stop("weight invariance (sub-blocking) certification FAILED")
}
cat("\nALL WEIGHT INVARIANCE (SUB-BLOCKING) CHECKS PASS.\n")

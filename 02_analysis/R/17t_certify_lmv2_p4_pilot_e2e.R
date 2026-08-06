# ============================================================================
# certify_run_cohort_hybrid_pilot_e2e.R -- end-to-end synthetic test of
# run_one_cohort_profile() (review correction): the existing helper fixtures
# tested each piece in isolation but never exercised the two lines where the
# join-key bug (treated_codinv vs codinv) and the name-collision bug
# (patent_trajectory on both inventor and firm sides) actually lived. This
# calls the REAL orchestration function, through attachment, roster creation,
# and solving, with:
#   - a MULTI-INVENTOR deal (3 treated inventors in one deal) -- this is
#     exactly the condition that triggered bug 1 (any deal with >1 treated
#     inventor);
#   - real firm + inventor patent_trajectory values on BOTH sides -- this is
#     exactly the condition that triggered bug 2.
# `con` is passed as NULL: run_one_cohort_profile() never dereferences it
# (every DB query happens in the OUTER run_cohort_hybrid_pilot() loop, before
# this function is called) -- confirmed by this fixture succeeding without a
# real connection. No database access.

if (!exists("BASE")) BASE <- normalizePath("02_analysis", mustWork = TRUE)
AUDIT_OUT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P4")
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))

checks <- list()
add_check <- function(name, observed, expected, pass) {
  checks[[length(checks) + 1]] <<- data.frame(
    check = name, observed = paste(observed, collapse = ","),
    expected = paste(expected, collapse = ","), pass = isTRUE(pass), stringsAsFactors = FALSE)
}

vars <- LMV2_P3$stage_2$scalar_variables   # log_patent_count_5y, patent_trajectory, career_age,
                                           # focal_group_tenure, focal_group_exclusivity

# ---- treated: ONE deal, THREE treated inventors (the multi-inventor
# condition that triggered bug 1). Covariates set to the CENTER of the
# control cloud on every dimension below (0, 0, 5, 2, 0.5) -- an interior
# target, so Stage-2 admissibility is not accidentally defeated by an
# enormous standardized gap on a dimension this fixture isn't testing.
treated_vals <- c(log_patent_count_5y = 0, patent_trajectory = 0, career_age = 5,
                  focal_group_tenure = 2, focal_group_exclusivity = 0.5)
treated_inv_ok <- data.frame(cohort = 1L, deal_id = 1L, codinv = c(901, 902, 903), recency_bin = 0)
for (v in vars) treated_inv_ok[[v]] <- treated_vals[[v]]

# ---- 5 admissible control firms (clears the >=5-firm gate), 6 control
# inventors each = 30 distinct control inventors. Donor covariates are built
# as SYMMETRIC +/-delta PAIRS around the treated center on every inventor
# dimension, and firm-level covariates are built as symmetric deviations
# around the treated firm's target that average out exactly across the 5
# (equal-inventor-count) firms. This means the plain UNWEIGHTED donor mean
# already exactly equals the treated target on all 8 dimensions, so exact
# entropy balancing has a near-trivial (weights~1) solution to converge to,
# rather than fighting numerical degeneracy on a genuinely hard high-
# dimensional balance problem the earlier random-normal construction hit
# ("All weights are NA or 0 in treatment group 0" / degenerate solution).
# This fixture is exercising attachment/join/roster-construction logic, not
# stress-testing the solver's convergence boundary, so a by-construction-
# solvable design is the right tool. CRITICAL: patent_trajectory appears on
# BOTH the inventor side (donors) and the firm side (authoritative_firm_covars)
# under the SAME raw name -- this is exactly the collision that triggered bug 2.
n_firms <- 5
n_per_firm <- 6
firm_groups <- 900 + seq_len(n_firms)
raw_edges <- data.frame(cohort = 1L, deal_id = 1L, control_group = firm_groups, distance = 0.3)

set.seed(11)
symmetric_pairs <- function(center, n, scale = 1) {
  half <- stats::rnorm(n / 2, 0, scale)
  center + c(half, -half)
}
donor_rows <- do.call(rbind, lapply(firm_groups, function(fg) {
  data.frame(cohort = 1L, codinv = fg * 10 + seq_len(n_per_firm), focal_group = fg, recency_bin = 0,
            log_patent_count_5y = symmetric_pairs(treated_vals[["log_patent_count_5y"]], n_per_firm),
            patent_trajectory = symmetric_pairs(treated_vals[["patent_trajectory"]], n_per_firm),
            career_age = symmetric_pairs(treated_vals[["career_age"]], n_per_firm),
            focal_group_tenure = symmetric_pairs(treated_vals[["focal_group_tenure"]], n_per_firm),
            focal_group_exclusivity = symmetric_pairs(treated_vals[["focal_group_exclusivity"]], n_per_firm))
}))
donors_loosest <- donor_rows
donor_cols_loosest <- donor_rows
names(donor_cols_loosest)[names(donor_cols_loosest) == "codinv"] <- "control_codinv"
names(donor_cols_loosest)[names(donor_cols_loosest) == "focal_group"] <- "control_group"

# 5 firms, equal inventor count each (6) -> plain average of these symmetric
# deviations exactly reproduces the treated firm's (2, 2, 0.1) target.
firm_dev <- c(-2, -1, 0, 1, 2)
authoritative_firm_covars <- data.frame(cohort = 1L, control_group = firm_groups,
                                        log_patent_stock_5y = 2 + firm_dev * 0.3,
                                        log_inventor_count_5y = 2 + rev(firm_dev) * 0.3,
                                        patent_trajectory = 0.1 + firm_dev * 0.05)
authoritative_treated_target <- data.frame(cohort = 1L, deal_id = 1L, target_group = 999,
                                           log_patent_stock_5y = 2, log_inventor_count_5y = 2,
                                           patent_trajectory = 0.1)

# ---- cached technology facts: every treated x every donor pair, all shared
# and maximally similar (cosine=1 -> tech_distance=0), so the caliper never
# excludes a pair for technology reasons -- isolates the attachment/join
# logic as the thing under test, not technology admissibility.
treated_ids <- treated_inv_ok$codinv
control_ids <- donor_rows$codinv
grid <- expand.grid(treated_codinv = treated_ids, control_codinv = control_ids)
cached_tech <- list(
  shared_ipc4 = data.frame(cohort = 1L, treated_codinv = grid$treated_codinv,
                           control_codinv = grid$control_codinv, shared_ipc4 = TRUE),
  similarity = data.frame(cohort = 1L, treated_codinv = grid$treated_codinv,
                          control_codinv = grid$control_codinv, cosine = 1))

retention_full_spine <- list(n_treated = 3L, n_deals = 1L, n_treated_covariate_complete = 3L)

# Caliper widened to 10: with 5 independent unit-variance covariate
# dimensions, a random donor's expected Euclidean distance from the treated
# center is already ~sqrt(5)=2.24, so caliper=2.0 admitted almost nobody
# ("inadequate_control_mass"). This fixture is testing attachment/join
# logic, not calibrating the admissibility caliper, so it is widened enough
# that support is not the binding constraint.
row <- run_one_cohort_profile(
  con = NULL, g = 1L, caliper = 10.0, profile = "all_eligible", universe = "u1", scheme = "primary",
  raw_edges = raw_edges, treated_inv_ok = treated_inv_ok, donors_loosest = donors_loosest,
  donor_cols_loosest = donor_cols_loosest, cached_tech = cached_tech,
  authoritative_firm_covars = authoritative_firm_covars,
  authoritative_treated_target = authoritative_treated_target,
  frozen10_deal_ids = integer(0), retention_full_spine = retention_full_spine)

add_check("E2E_run_one_cohort_profile_completes_without_error", "no error thrown", "no error thrown", TRUE)
add_check("E2E_multi_inventor_deal_did_not_crash_the_join",
          row$n_treated_stage1_deal_supported >= 1, TRUE, isTRUE(row$n_treated_stage1_deal_supported >= 1))
add_check("E2E_mode_is_not_a_hard_failure", !row$mode %in% c(NA_character_, "retention_failed"),
          TRUE, !is.na(row$mode) && row$mode != "retention_failed")
add_check("E2E_smd_firm_patent_trajectory_present_not_dropped",
          !is.na(row$smd_firm_patent_trajectory), TRUE, !is.na(row$smd_firm_patent_trajectory))
add_check("E2E_smd_patent_trajectory_inventor_present_not_dropped",
          !is.na(row$smd_patent_trajectory), TRUE, !is.na(row$smd_patent_trajectory))
add_check("E2E_both_trajectory_smds_are_distinct_covariates",
          "firm and inventor trajectory tracked separately", "n/a",
          !is.na(row$smd_firm_patent_trajectory) && !is.na(row$smd_patent_trajectory))
add_check("E2E_headline_retention_computed", !is.na(row$headline_inventor_retention), TRUE,
          !is.na(row$headline_inventor_retention))
add_check("E2E_reuse_adjusted_ess_reported", !is.na(row$inventor_ess_reuse_adjusted), TRUE,
          !is.na(row$inventor_ess_reuse_adjusted))
add_check("E2E_stack_row_ess_reported", !is.na(row$inventor_ess_stack_row), TRUE,
          !is.na(row$inventor_ess_stack_row))
add_check("E2E_no_failure_reason_recorded", is.na(row$failure_reason), TRUE, is.na(row$failure_reason))

# ---- Regression guard: rerun WITHOUT the bug-1 fix's rename, by directly
# reproducing the pre-fix join, to prove it WOULD have failed on this exact
# multi-inventor construction (documents why the fix is necessary, not just
# that the fixed version works).
supp_key <- data.frame(cohort = 1L, deal_id = 1L, treated_codinv = treated_ids)
pre_fix_by <- intersect(names(supp_key), names(treated_inv_ok))
add_check("E2E_regression_guard_confirms_pre_fix_by_was_only_cohort_deal",
          paste(pre_fix_by, collapse = ","), "cohort,deal_id",
          identical(pre_fix_by, c("cohort", "deal_id")))
pre_fix_join <- merge(supp_key, treated_inv_ok, by = pre_fix_by)
add_check("E2E_regression_guard_confirms_pre_fix_join_fans_out",
          sprintf("%d rows from %d treated (should be 9 = 3x3, not 3)", nrow(pre_fix_join), length(treated_ids)),
          "9", nrow(pre_fix_join) == length(treated_ids)^2)

# ===========================================================================
# Fixture LEAK -- (review correction) an unsupported deal (deal 107-style: it
# has admissible Stage-1 firms, just fewer than MIN_ELIGIBLE_FIRMS=5) must
# show up as a support LOSS in the retention funnel, but must never reach
# Stage 2 and must never produce a control-only deal that crashes
# allocate_deal_base_weights(). TWO deals in one cohort: deal 1 (supported,
# 5 admissible firms) and deal 2 (unsupported, only 2 admissible firms).
# Both deals' treated inventors are otherwise perfectly well-formed
# (covariate-complete, technology-admissible via cosine=1/shared_ipc4=TRUE
# for every pair) -- the ONLY thing that should exclude deal 2 is the
# 5-firm gate, isolating exactly the leak this fixture targets.
# ===========================================================================
leak_firms_A <- 800 + 1:5    # deal 1: 5 admissible firms -> supported
leak_firms_B <- 806:807      # deal 2: 2 admissible firms -> unsupported
raw_edges_leak <- data.frame(cohort = 1L,
                             deal_id = c(rep(1L, length(leak_firms_A)), rep(2L, length(leak_firms_B))),
                             control_group = c(leak_firms_A, leak_firms_B), distance = 0.3)

treated_inv_ok_leak <- data.frame(cohort = 1L, deal_id = c(1L, 2L), codinv = c(9101, 9102), recency_bin = 0)
for (v in vars) treated_inv_ok_leak[[v]] <- treated_vals[[v]]

# mostly_center_pairs (not symmetric_pairs): with 5 independent covariate
# dimensions, a fully-random symmetric-pair donor's Euclidean distance from
# the treated center averages ~sqrt(5) in standardized units, and
# standardization is scale-invariant to a uniform rescale of the deviations
# (lmv2_prepare_stage2_edges() recomputes SD from the same donor population,
# so shrinking `scale` shrinks the SD by the same factor and leaves the
# standardized distance unchanged -- confirmed by direct debugging). At the
# locked STAGE2_CALIPER=1.5, a purely random draw can land entirely above
# caliper by chance (observed: min standardized distance 1.517 with one
# seed). mostly_center_pairs keeps n-2 of every 6 donors EXACTLY at the
# treated center on every dimension simultaneously (distance=0, always
# admissible) and confines all deviation to a symmetric +-v pair, so this
# fixture is deterministic support, not a lucky seed.
leak_firm_groups <- c(leak_firms_A, leak_firms_B)
set.seed(23)
mostly_center_pairs <- function(center, n, scale = 1) {
  v <- stats::rnorm(1, 0, scale)
  c(rep(center, n - 2), center + v, center - v)
}
donor_rows_leak <- do.call(rbind, lapply(leak_firm_groups, function(fg) {
  data.frame(cohort = 1L, codinv = fg * 10 + 1:6, focal_group = fg, recency_bin = 0,
            log_patent_count_5y = mostly_center_pairs(treated_vals[["log_patent_count_5y"]], 6),
            patent_trajectory = mostly_center_pairs(treated_vals[["patent_trajectory"]], 6),
            career_age = mostly_center_pairs(treated_vals[["career_age"]], 6),
            focal_group_tenure = mostly_center_pairs(treated_vals[["focal_group_tenure"]], 6),
            focal_group_exclusivity = mostly_center_pairs(treated_vals[["focal_group_exclusivity"]], 6))
}))
donors_loosest_leak <- donor_rows_leak
donor_cols_loosest_leak <- donor_rows_leak
names(donor_cols_loosest_leak)[names(donor_cols_loosest_leak) == "codinv"] <- "control_codinv"
names(donor_cols_loosest_leak)[names(donor_cols_loosest_leak) == "focal_group"] <- "control_group"

leak_firm_dev <- seq(-3, 3, length.out = length(leak_firm_groups))
authoritative_firm_covars_leak <- data.frame(cohort = 1L, control_group = leak_firm_groups,
                                             log_patent_stock_5y = 2 + leak_firm_dev * 0.3,
                                             log_inventor_count_5y = 2 + rev(leak_firm_dev) * 0.3,
                                             patent_trajectory = 0.1 + leak_firm_dev * 0.05)
authoritative_treated_target_leak <- data.frame(cohort = 1L, deal_id = c(1L, 2L), target_group = c(991, 992),
                                                log_patent_stock_5y = 2, log_inventor_count_5y = 2,
                                                patent_trajectory = 0.1)

treated_ids_leak <- treated_inv_ok_leak$codinv
control_ids_leak <- donor_rows_leak$codinv
grid_leak <- expand.grid(treated_codinv = treated_ids_leak, control_codinv = control_ids_leak)
cached_tech_leak <- list(
  shared_ipc4 = data.frame(cohort = 1L, treated_codinv = grid_leak$treated_codinv,
                           control_codinv = grid_leak$control_codinv, shared_ipc4 = TRUE),
  similarity = data.frame(cohort = 1L, treated_codinv = grid_leak$treated_codinv,
                          control_codinv = grid_leak$control_codinv, cosine = 1))

retention_full_spine_leak <- list(n_treated = 2L, n_deals = 2L, n_treated_covariate_complete = 2L)

row_leak <- run_one_cohort_profile(
  con = NULL, g = 1L, caliper = 10.0, profile = "all_eligible", universe = "u1", scheme = "primary",
  raw_edges = raw_edges_leak, treated_inv_ok = treated_inv_ok_leak, donors_loosest = donors_loosest_leak,
  donor_cols_loosest = donor_cols_loosest_leak, cached_tech = cached_tech_leak,
  authoritative_firm_covars = authoritative_firm_covars_leak,
  authoritative_treated_target = authoritative_treated_target_leak,
  frozen10_deal_ids = integer(0), retention_full_spine = retention_full_spine_leak)

add_check("LEAK_run_one_cohort_profile_completes_without_error", "no error thrown", "no error thrown", TRUE)
add_check("LEAK_only_deal_1_counted_as_stage1_supported",
          row_leak$n_deals_stage1_supported, 1L, isTRUE(row_leak$n_deals_stage1_supported == 1L))
add_check("LEAK_unsupported_deal_shows_as_support_loss_in_deal_retention",
          row_leak$headline_deal_retention, 0.5, isTRUE(abs(row_leak$headline_deal_retention - 0.5) < 1e-9))
add_check("LEAK_unsupported_deal_shows_as_support_loss_in_inventor_retention",
          row_leak$headline_inventor_retention, 0.5, isTRUE(abs(row_leak$headline_inventor_retention - 0.5) < 1e-9))
add_check("LEAK_only_deal_1_treated_inventor_supported",
          row_leak$n_supported_treated, 1L, isTRUE(row_leak$n_supported_treated == 1L))
add_check("LEAK_no_base_weight_error_no_control_only_deal",
          row_leak$failure_reason, NA_character_,
          is.na(row_leak$failure_reason) || !grepl("base_weight_error", row_leak$failure_reason %||% ""))
# retention_failed IS the correct outcome here, not a bug: this fixture's
# full spine is deliberately tiny (2 treated inventors total), so losing
# deal 2's one inventor to the (correct) support exclusion crosses the
# locked retention floor -- a proper, handled business-logic gate, not a
# crash. LEAK_no_base_weight_error_no_control_only_deal above already
# directly confirms no crash occurred; this check only confirms `mode` was
# actually populated with a recognized terminal state (not left NA by an
# unhandled error).
add_check("LEAK_mode_is_a_recognized_terminal_state", row_leak$mode,
          "one of exact_ebal/optweight_0.05/optweight_0.10/infeasible/retention_failed",
          row_leak$mode %in% c("exact_ebal", "optweight_0.05", "optweight_0.10", "infeasible", "retention_failed"))

# ---- Regression guard: reproduce the PRE-FIX logic directly (Stage-2 built
# from the FULL, unfiltered `admissible` pool -- i.e. without restricting to
# `admissible_supported`) and show it WOULD have produced a control-only
# deal 2, reproducing the exact real-data deal-107 failure mode this fixture
# targets.
admissible_leak_prefix <- lmv2_ebal_stage1_admissible_edges(raw_edges_leak, 10.0)
n_firms_by_deal_leak <- stats::aggregate(control_group ~ cohort + deal_id, data = admissible_leak_prefix,
                                         FUN = function(x) length(unique(x)))
names(n_firms_by_deal_leak)[3] <- "n_eligible_firms"
supported_deals_leak <- n_firms_by_deal_leak$deal_id[
  vapply(n_firms_by_deal_leak$n_eligible_firms, lmv2_ebal_deal_supported, logical(1), min_firms = MIN_ELIGIBLE_FIRMS)]
add_check("LEAK_regression_guard_confirms_deal_2_correctly_unsupported",
          paste(sort(supported_deals_leak), collapse = ","), "1",
          identical(sort(supported_deals_leak), 1L))
donor_cols_profile_prefix <- donor_cols_loosest_leak[
  donor_cols_loosest_leak$control_group %in% unique(admissible_leak_prefix$control_group), ]
donors_profile_prefix <- donors_loosest_leak[
  donors_loosest_leak$focal_group %in% unique(admissible_leak_prefix$control_group), ]
stage2_edges_prefix <- build_stage2_edges_for_profile(
  1L, admissible_leak_prefix, treated_inv_ok_leak, donors_profile_prefix, donor_cols_profile_prefix,
  cached_tech_leak$shared_ipc4, cached_tech_leak$similarity)
add_check("LEAK_regression_guard_prefix_stage2_edges_would_have_included_deal_2",
          paste(sort(unique(stage2_edges_prefix$deal_id)), collapse = ","), "1,2",
          2L %in% unique(stage2_edges_prefix$deal_id))
admissible_stage2_prefix <- lmv2_ebal_stage2_admissible_edges(stage2_edges_prefix, STAGE2_CALIPER)
control_rows_prefix <- unique(admissible_stage2_prefix[c("cohort", "deal_id", "control_codinv", "control_group")])
add_check("LEAK_regression_guard_prefix_control_rows_would_have_included_unsupported_deal_2",
          2L %in% unique(control_rows_prefix$deal_id), TRUE, 2L %in% unique(control_rows_prefix$deal_id))
treated_key_prefix <- treated_inv_ok_leak[treated_inv_ok_leak$deal_id %in% supported_deals_leak,
                                          c("cohort", "deal_id", "codinv")]
add_check("LEAK_regression_guard_prefix_treated_rows_would_NOT_have_included_deal_2",
          2L %in% unique(treated_key_prefix$deal_id), FALSE, !(2L %in% unique(treated_key_prefix$deal_id)))
add_check("LEAK_regression_guard_confirms_deal_set_mismatch_reproduced",
          "treated={1}, control={1,2} -- exactly the deal-107 mismatch",
          "mismatch reproduced",
          !setequal(unique(treated_key_prefix$deal_id), unique(control_rows_prefix$deal_id)))

# ===========================================================================
report <- do.call(rbind, checks)
cat(sprintf("\n=== run_one_cohort_profile() end-to-end certification: %d checks, %d failing ===\n",
            nrow(report), sum(!report$pass)))
print(report[, c("check", "pass")], row.names = FALSE)
cat("\nfull diagnostic row:\n"); print(t(row))
utils::write.csv(report, file.path(AUDIT_OUT_DIR, "certify_run_cohort_hybrid_pilot_e2e_results.csv"), row.names = FALSE)
if (any(!report$pass)) {
  cat("\nFAILING CHECKS:\n"); print(report[!report$pass, ], row.names = FALSE)
  stop("end-to-end certification FAILED")
}
cat("\nALL END-TO-END CHECKS PASS.\n")

# Database-free certification for the frozen P5.3 production overlay.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(
  BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
source(file.path(
  BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R"))
source(file.path(
  BASE, "R", "18f_lmv2_p5_selected_acceleration.R"))
source(file.path(
  BASE, "R", "18j_lmv2_p5_newton_solver.R"))
source(file.path(
  BASE, "R", "19a_lmv2_p5_rescue_config.R"))
source(file.path(
  BASE, "R", "18n_lmv2_p5_weight_materialization.R"))
source(file.path(
  BASE, "R", "19f_lmv2_p5_rescue_dependence_diagnostics.R"))
source(file.path(
  BASE, "R", "19i_lmv2_p5_final_production_config.R"))

expect_true <- function(value, label) {
  if (!isTRUE(value)) stop("FAIL: ", label)
}
expect_equal <- function(value, expected, label, tolerance = 1e-12) {
  ok <- if (is.numeric(value) && is.numeric(expected)) {
    length(value) == length(expected) &&
      all(abs(value - expected) <= tolerance)
  } else {
    identical(value, expected)
  }
  if (!ok) {
    stop(
      "FAIL: ", label, "; observed=", paste(value, collapse = ","),
      "; expected=", paste(expected, collapse = ","))
  }
}

STAGE1_CALIPERS <- 2.0
STAGE1_PROFILES <- "nearest_50"
STAGE2_CALIPER <- 1.5
UNIVERSES <- "u2"
SCHEMES <- c("primary", "equal_deal")
LMV2_P5_SOLVER <- "newton"
lmv2_p5_production_apply()

expect_equal(
  STAGE1_CALIPERS, 2.0,
  "production Stage-1 caliper is frozen at 2.0")
expect_equal(
  STAGE2_CALIPER, 1.5,
  "production Stage-2 caliper is frozen at 1.5")
expect_equal(
  LMV2_P3$stage_2$scalar_variables,
  c("log_patent_count_5y", "patent_trajectory", "career_age"),
  "reduced inventor distance is frozen")
expect_equal(
  LMV2_HYBRID_INV_VARS,
  c(
    "log_patent_count_5y", "patent_trajectory", "career_age",
    "focal_group_exclusivity"),
  "exclusivity remains an exact balance moment")
expect_true(
  grepl("Outcome and treatment-effect objects are forbidden",
        LMV2_P5_PRODUCTION$outcome_boundary, fixed = TRUE),
  "outcome boundary is explicit")

diagnostics <- data.frame(
  cohort = rep(c(2000L, 2009L), each = 2),
  scheme = rep(c("primary", "equal_deal"), 2),
  mode = c("exact_ebal", "infeasible", "exact_ebal", "exact_ebal"),
  headline_inventor_retention = c(0.94, 0.94, 0.97, 0.97),
  max_smd = c(0, NA, 0, 0),
  inventor_ess_reuse_adjusted = c(76, NA, 80, 75),
  n_supported_treated = c(100, 100, 100, 100),
  stringsAsFactors = FALSE)
status <- lmv2_p5_production_scheme_status(diagnostics)
expect_equal(
  status$feasible,
  c(TRUE, FALSE, TRUE, TRUE),
  "ESS/balance feasibility is scheme-specific")
comparison <- lmv2_p5_production_comparison_map(diagnostics)
expect_equal(
  comparison$include_primary_full,
  c(TRUE, TRUE),
  "both primary-feasible cohorts enter the headline map")
expect_equal(
  comparison$include_primary_like_for_like,
  c(FALSE, TRUE),
  "like-for-like primary follows equal-deal feasibility")
expect_equal(
  comparison$include_equal_deal,
  comparison$include_primary_like_for_like,
  "equal-deal and like-for-like primary use the same cohort map")

bad_ess <- diagnostics
bad_ess$inventor_ess_reuse_adjusted[
  bad_ess$cohort == 2009L & bad_ess$scheme == "primary"] <- 49
bad_status <- lmv2_p5_production_scheme_status(bad_ess)
expect_true(
  !bad_status$feasible[
    bad_status$cohort == 2009L &
      bad_status$scheme == "primary"],
  "primary ESS below 0.50 is a hard failure")

low_coverage <- diagnostics
low_coverage$headline_inventor_retention[
  low_coverage$cohort == 2000L] <- 0.79
scope <- lmv2_p5_production_scheme_status(low_coverage)
expect_true(
  all(scope$scope_review[scope$cohort == 2000L]),
  "cohort coverage below 0.80 triggers scope review")

for (file in c(
    "19i_lmv2_p5_final_production_config.R",
    "19j_run_lmv2_p5_final_production.R",
    "19l_finalize_lmv2_p5_final_production.R",
    "19m_run_lmv2_p5_deal70_refits.R",
    "19n_schedule_lmv2_p5_deal70_refits.R",
    "19o_finalize_lmv2_p5_deal70_refits.R",
    "20c_lmv2_cardinality_candidates.R",
    "20d_run_lmv2_p5_cardinality.R",
    "20e_schedule_lmv2_p5_cardinality.R",
    "20f_finalize_lmv2_p5_cardinality.R")) {
  parse(file = file.path(BASE, "R", file))
}

source(file.path(
  BASE, "R", "20a_lmv2_p6_selection_sensitivity_config.R"))
sensitivity <- lmv2_p6_common_support_sensitivity(
  att_supported = -1, coverage = 0.9, sigma_pre = 2)
expect_equal(
  sensitivity$att_all[sensitivity$delta == 0], -1,
  "delta zero reproduces the supported ATT")
expect_equal(
  sensitivity$att_all[sensitivity$delta == 1], -0.8,
  "unsupported-tail mixture uses realized unsupported mass")
reversal <- lmv2_p6_common_support_reversal(
  att_supported = -1, coverage = 0.9, sigma_pre = 2)
expect_equal(
  reversal$att_unsupported_reversal, 9,
  "reversal unsupported ATT follows the frozen decomposition")
expect_equal(
  reversal$delta_reversal, 5,
  "standardized reversal follows the frozen decomposition")
lee <- lmv2_p6_validate_lee_cell(0.8, 1)
expect_equal(
  lee$distribution_to_trim, "comparison",
  "Lee validation trims the higher-selection distribution")
expect_equal(
  lee$trimming_share, 0.2,
  "Lee trimming share uses the selection-rate ratio")

source(file.path(BASE, "R", "20b_lmv2_cardinality_engine.R"))
cardinality_treated <- data.frame(
  cohort = 2000L, deal_id = 70L, treated_codinv = 1:3,
  x = c(0, 1, 2))
cardinality_controls <- data.frame(
  cohort = 2000L, deal_id = 70L,
  control_codinv = 11:16,
  control_group = rep(c(101, 102), each = 3),
  x = c(0, 1, 2, 0, 1, 2))
cardinality_edges <- merge(
  cardinality_treated[c("cohort", "deal_id", "treated_codinv")],
  cardinality_controls[
    c("cohort", "deal_id", "control_codinv", "control_group")],
  by = c("cohort", "deal_id"))
cardinality_edges$distance <- abs(
  cardinality_edges$treated_codinv -
    ((cardinality_edges$control_codinv - 11) %% 3 + 1))
cardinality <- lmv2_cardinality_match(
  cardinality_treated, cardinality_controls, cardinality_edges,
  balance_variables = "x", controls_per_treated = 2L,
  maximum_control_reuse = 1L, maximum_balance_smd = 0.10)
expect_equal(
  cardinality$status, "optimal",
  "cardinality fixture solves optimally")
expect_equal(
  cardinality$n_matched_treated, 3L,
  "cardinality fixture maximizes treated retention")
expect_true(
  cardinality$maximum_realized_reuse <= 1L,
  "cardinality fixture respects the reuse cap")
expect_true(
  max(abs(cardinality$diagnostics$smd)) <= 0.10 + 1e-6,
  "cardinality fixture respects the balance tolerance")

message("19k P5.3 production certification: ALL FIXTURES PASS")

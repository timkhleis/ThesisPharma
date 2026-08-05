# ============================================================================
# P5.3 final outcome-blind production configuration
# ============================================================================

LMV2_P5_PRODUCTION_VERSION <- "local_match_v2_p5_production_1993_amendment_v1"
LMV2_P5_PRODUCTION_FREEZE_SHA256 <-
  "637e7535239a835ffadc5cbba17a96c2f9a2410d997f36ff127568493b9b33d4"
LMV2_P5_PRODUCTION_STAGE <- "u2_reduced_stage1_2"

LMV2_P5_PRODUCTION_PATHS <- list(
  freeze = file.path(
    BASE, "notes", "local_match_v2_p5_final_production_freeze.md"))

observed_production_freeze_hash <- lmv2_p3_file_hash(
  LMV2_P5_PRODUCTION_PATHS$freeze)
if (!identical(
    observed_production_freeze_hash,
    LMV2_P5_PRODUCTION_FREEZE_SHA256)) {
  stop(
    "P5.3 production freeze drifted: expected ",
    LMV2_P5_PRODUCTION_FREEZE_SHA256, ", observed ",
    observed_production_freeze_hash)
}

LMV2_P5_PRODUCTION <- list(
  outcome_boundary = paste(
    "P5.3 may read treatment assignments, donor eligibility,",
    "pre-treatment covariates, support edges, weights, and design",
    "diagnostics only. Outcome and treatment-effect objects are forbidden."
  ),
  cohorts = 1993:2010,
  stage = LMV2_P5_PRODUCTION_STAGE,
  selected = list(
    universe = "u2",
    profile = "nearest_50",
    stage1_caliper = 2.0,
    stage2_caliper = 1.5,
    technology_resolution = "ipc4",
    distance_variables = c(
      "log_patent_count_5y", "patent_trajectory", "career_age"),
    balance_variables = c(
      "log_patent_count_5y", "patent_trajectory", "career_age",
      "focal_group_exclusivity"),
    schemes = c("primary", "equal_deal"),
    solver = "newton"
  ),
  hard_gates = list(
    aggregate_inventor_coverage = 0.80,
    minimum_cohort_coverage = 0.60,
    aggregate_deal_coverage = 0.80,
    minimum_productivity_quartile_coverage = 0.70,
    minimum_reuse_adjusted_ess_ratio = 0.50
  ),
  scope_review = list(
    aggregate_inventor_coverage = 0.85,
    cohort_inventor_coverage = 0.80
  ),
  deal_70 = list(
    effective_firm_count_review = 2.50,
    influence_band = "min_max_across_nine_single_firm_refits"
  ),
  comparison_estimands = c(
    "primary_full_supported",
    "equal_deal_feasible",
    "primary_equal_deal_feasible_sample"
  ),
  max_workers = 2L,
  minimum_second_worker_available_gb = 12,
  critical_available_gb = 4,
  critical_polls_before_requeue = 3L,
  freeze_hash = LMV2_P5_PRODUCTION_FREEZE_SHA256
)

lmv2_p5_production_apply <- function() {
  lmv2_p5_rescue_apply_stage(LMV2_P5_PRODUCTION_STAGE)
  expected <- LMV2_P5_PRODUCTION$selected
  checks <- c(
    identical(UNIVERSES, expected$universe),
    identical(STAGE1_PROFILES, expected$profile),
    identical(as.numeric(STAGE1_CALIPERS), expected$stage1_caliper),
    identical(as.numeric(STAGE2_CALIPER), expected$stage2_caliper),
    identical(LMV2_P3$stage_2$scalar_variables,
              expected$distance_variables),
    identical(LMV2_HYBRID_INV_VARS, expected$balance_variables),
    identical(SCHEMES, expected$schemes),
    identical(LMV2_P5_SOLVER, expected$solver)
  )
  if (!all(checks)) {
    stop("Live settings do not reproduce the frozen P5.3 specification")
  }
  LMV2_P5_FINAL$outcome_boundary <<-
    LMV2_P5_PRODUCTION$outcome_boundary
  LMV2_P5_FINAL$selected$production_version <<-
    LMV2_P5_PRODUCTION_VERSION
  invisible(TRUE)
}

lmv2_p5_production_execution_hash <- function(
    base_dir, p3_manifest_hash) {
  digest::digest(
    list(
      parent = lmv2_p5_rescue_execution_hash(
        base_dir, p3_manifest_hash, LMV2_P5_PRODUCTION_STAGE),
      version = LMV2_P5_PRODUCTION_VERSION,
      freeze = LMV2_P5_PRODUCTION_FREEZE_SHA256,
      config = lmv2_p3_file_hash(file.path(
        base_dir, "R", "19i_lmv2_p5_final_production_config.R")),
      selected = LMV2_P5_PRODUCTION$selected,
      hard_gates = LMV2_P5_PRODUCTION$hard_gates,
      scope_review = LMV2_P5_PRODUCTION$scope_review,
      comparison_estimands =
        LMV2_P5_PRODUCTION$comparison_estimands
    ),
    algo = "sha256"
  )
}

lmv2_p5_production_scheme_status <- function(diagnostics) {
  required <- c(
    "cohort", "scheme", "mode", "headline_inventor_retention",
    "max_smd", "inventor_ess_reuse_adjusted",
    "n_supported_treated")
  if (!all(required %in% names(diagnostics))) {
    stop("Production diagnostics lack required status columns")
  }
  x <- diagnostics
  x$feasible <- x$mode != "infeasible" &
    is.finite(x$max_smd) &
    is.finite(x$inventor_ess_reuse_adjusted) &
    x$inventor_ess_reuse_adjusted /
      pmax(x$n_supported_treated, 1) >=
      LMV2_P5_PRODUCTION$hard_gates$
        minimum_reuse_adjusted_ess_ratio
  x$scope_review <- x$headline_inventor_retention <
    LMV2_P5_PRODUCTION$scope_review$cohort_inventor_coverage
  x[c(
    "cohort", "scheme", "feasible", "scope_review",
    "headline_inventor_retention")]
}

lmv2_p5_production_comparison_map <- function(diagnostics) {
  status <- lmv2_p5_production_scheme_status(diagnostics)
  primary <- status[
    status$scheme == "primary",
    c("cohort", "feasible"), drop = FALSE]
  names(primary)[2] <- "primary_feasible"
  equal <- status[
    status$scheme == "equal_deal",
    c("cohort", "feasible"), drop = FALSE]
  names(equal)[2] <- "equal_deal_feasible"
  out <- merge(primary, equal, by = "cohort", all = TRUE, sort = TRUE)
  out$primary_feasible[is.na(out$primary_feasible)] <- FALSE
  out$equal_deal_feasible[is.na(out$equal_deal_feasible)] <- FALSE
  out$include_primary_full <- out$primary_feasible
  out$include_equal_deal <- out$equal_deal_feasible
  out$include_primary_like_for_like <-
    out$primary_feasible & out$equal_deal_feasible
  out
}

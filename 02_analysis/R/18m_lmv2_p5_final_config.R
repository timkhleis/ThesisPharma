# ============================================================================
# P5 final, outcome-blind selected specification
# ============================================================================

LMV2_P5_FINAL_VERSION <- "local_match_v2_p5_final_v1"
LMV2_P5_FINAL_AMENDMENT_SHA256 <-
  "9d0a23145f0b1c124b993f42ec755aab55e97fd11b2f403acba79dbed4e8afaa"

LMV2_P5_FINAL_PATHS <- list(
  amendment = file.path(
    BASE, "notes", "local_match_v2_p5_outcome_blind_amendment.md")
)

observed_p5_amendment_hash <- lmv2_p3_file_hash(
  LMV2_P5_FINAL_PATHS$amendment)
if (!identical(
    observed_p5_amendment_hash,
    LMV2_P5_FINAL_AMENDMENT_SHA256)) {
  stop(
    "P5 outcome-blind amendment drifted: expected ",
    LMV2_P5_FINAL_AMENDMENT_SHA256, ", observed ",
    observed_p5_amendment_hash)
}

LMV2_P5_FINAL <- list(
  outcome_boundary = paste(
    "P5 may read only matching/design inputs and must stop before outcomes,",
    "event panels, DiD estimation, or treatment-effect interpretation."
  ),
  selected = list(
    universe = "u1",
    profile = "nearest_50",
    stage1_caliper = 1.5,
    stage2_caliper = 1.5,
    technology_resolution = "ipc4",
    schemes = c("primary", "equal_deal"),
    solver = "newton",
    cohorts = 1994:2010
  ),
  dealsim = list(
    lookback_years = -5:-1,
    resolution = "ipc4",
    quantile_type = 7L,
    probs = c(1 / 3, 2 / 3),
    lower_boundary_included = TRUE,
    placeholder_prefix = "999",
    headline_scheme = "primary",
    sensitivity_scheme = "equal_deal",
    minimum_inventor_retention = 0.80,
    minimum_deal_retention = 0.85
  ),
  compute = list(
    max_workers = 2L,
    duckdb_threads_per_worker = 2L,
    duckdb_memory_limit = "6GB",
    min_start_available_gb = 12,
    critical_available_gb = 4
  ),
  amendment_hash = LMV2_P5_FINAL_AMENDMENT_SHA256
)

lmv2_p5_assert_selected_settings <- function(
    caliper, profile, universe, schemes, solver, cohorts) {
  expected <- LMV2_P5_FINAL$selected
  failures <- character(0)
  if (!identical(as.numeric(caliper), expected$stage1_caliper)) {
    failures <- c(failures, "Stage-1 caliper")
  }
  if (!identical(profile, expected$profile)) {
    failures <- c(failures, "profile")
  }
  if (!identical(universe, expected$universe)) {
    failures <- c(failures, "universe")
  }
  if (!identical(sort(unique(schemes)), sort(expected$schemes))) {
    failures <- c(failures, "weighting schemes")
  }
  if (!identical(solver, expected$solver)) {
    failures <- c(failures, "solver")
  }
  if (!length(cohorts) || any(!cohorts %in% expected$cohorts)) {
    failures <- c(failures, "cohort list")
  }
  if (!identical(STAGE2_CALIPER, expected$stage2_caliper)) {
    failures <- c(failures, "locked Stage-2 caliper")
  }
  if (!identical(
      LMV2_P4_EBAL$stage_2$technology_resolution,
      expected$technology_resolution)) {
    failures <- c(failures, "technology resolution")
  }
  if (length(failures)) {
    stop(
      "P5 selected settings disagree with the outcome-blind amendment: ",
      paste(failures, collapse = ", "))
  }
  invisible(TRUE)
}

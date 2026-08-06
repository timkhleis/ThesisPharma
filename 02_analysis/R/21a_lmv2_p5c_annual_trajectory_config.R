# ============================================================================
# P5c: complete five-year annual patenting trajectory
# ============================================================================

LMV2_P5C_VERSION <- "lmv2_p5c_annual_trajectory_1993_amendment_v1"

LMV2_P5C <- list(
  cohorts = 1993:2010,
  probe_cohorts = c(2000L, 2005L),
  schemes = c("primary", "equal_deal"),
  probe_schemes = "primary",
  production_schemes = "primary",
  probe_variants = c("count_only", "count_active"),
  production_variant = "count_active",
  placebo_variants = c("loyo_m3", "loyo_m4"),
  event_times = -5:-1,
  count_variables = paste0("patent_count_m", 5:1),
  active_variables = paste0("active_patenting_m", 5:1),
  retained_inventor_variables = c(
    "career_age", "focal_group_exclusivity"),
  firm_variables = c(
    "firm_log_patent_stock_5y",
    "firm_log_inventor_count_5y",
    "firm_patent_trajectory"),
  selection = list(
    minimum_reuse_adjusted_ess_ratio = 0.50,
    maximum_absolute_ess_ratio_loss = 0.10,
    maximum_relative_max_share_increase = 0.25),
  freeze_note = file.path(
    BASE, "notes", "local_match_v2_p5c_annual_trajectory_freeze.md")
)

lmv2_p5c_balance_variables <- function(variant) {
  valid <- c(
    LMV2_P5C$probe_variants,
    LMV2_P5C$placebo_variants)
  if (!variant %in% valid) {
    stop("Unknown P5c variant: ", variant)
  }
  held_out <- switch(
    variant,
    loyo_m3 = 3L,
    loyo_m4 = 4L,
    NA_integer_)
  counts <- LMV2_P5C$count_variables
  active <- if (identical(variant, "count_only")) {
    character()
  } else {
    LMV2_P5C$active_variables
  }
  if (!is.na(held_out)) {
    counts <- setdiff(
      counts, paste0("patent_count_m", held_out))
    active <- setdiff(
      active, paste0("active_patenting_m", held_out))
  }
  c(
    counts, active,
    LMV2_P5C$retained_inventor_variables,
    LMV2_P5C$firm_variables)
}

lmv2_p5c_provenance <- function(source_manifest_path) {
  files <- c(
    config = file.path(
      BASE, "R", "21a_lmv2_p5c_annual_trajectory_config.R"),
    runner = file.path(
      BASE, "R", "21b_run_lmv2_p5c_annual_trajectory.R"),
    freeze = LMV2_P5C$freeze_note,
    source_manifest = source_manifest_path,
    matching_config = file.path(
      BASE, "R", "16a_lmv2_matching_config.R"),
    matching_utils = file.path(
      BASE, "R", "16c_lmv2_matching_utils.R"),
    ebal_config = file.path(
      BASE, "R", "17f_lmv2_p4_ebal_config.R"),
    ebal_utils = file.path(
      BASE, "R", "17g_lmv2_p4_ebal_utils.R"),
    hybrid_core = file.path(
      BASE, "R", "17l_lmv2_p4_hybrid_core.R"),
    cohort_core = file.path(
      BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"),
    newton_solver = file.path(
      BASE, "R", "18j_lmv2_p5_newton_solver.R"))
  missing <- files[!file.exists(files)]
  if (length(missing)) {
    stop(
      "P5c provenance file missing: ",
      paste(names(missing), collapse = ", "))
  }
  vapply(
    files, digest::digest, character(1),
    file = TRUE, algo = "sha256")
}

lmv2_p5c_execution_hash <- function(source_manifest_path) {
  digest::digest(
    list(
      version = LMV2_P5C_VERSION,
      settings = LMV2_P5C,
      provenance = lmv2_p5c_provenance(
        source_manifest_path)),
    algo = "sha256")
}

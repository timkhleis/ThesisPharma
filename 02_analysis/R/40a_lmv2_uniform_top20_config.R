# ============================================================================
# Frozen configuration for the independent uniform top-20 branch
# ============================================================================

LMV2_UNIFORM_TOP20_VERSION <- "P6_UNIFORM_TOP20_SYMMETRIC_1993_RELEASE_V1"

lmv2_uniform_top20_config <- function(base = getwd()) {
  base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  analysis <- file.path(base, "02_analysis")
  ppscm <- file.path(
    analysis, "output", "audit", "local_match_v2_1993_amendment",
    "ROBUSTNESS_RELEASE_1993", "P6_PPSCM_V2_SYMMETRIC")
  output <- file.path(
    analysis, "output", "audit", "local_match_v2_1993_amendment",
    "ROBUSTNESS_RELEASE_1993", "P6_UNIFORM_TOP20_SYMMETRIC")
  list(
    version = LMV2_UNIFORM_TOP20_VERSION,
    base = base,
    analysis_dir = analysis,
    database = file.path(
      analysis, "output", "thesis_foundation.duckdb"),
    freeze_path = file.path(
      analysis, "notes", "local_match_v2_uniform_top20_freeze.md"),
    expected_freeze_sha256 =
      "fe5d8f25074bc065c188a89d0f656ef78e368ea854374b50900d17b8741f0ec9",
    source_census_dir = file.path(ppscm, "stage_c_census"),
    source_units_dir = file.path(ppscm, "stage_b_units"),
    expected_census_manifest_sha256 =
      "43b55bb831e0a56c961bad57b94cd57cc58c9364ebb528aae12fc994a716387c",
    prepanel_path = file.path(
      ppscm, "stage_c_census", "ppscm_prepanel.parquet"),
    units_path = file.path(
      ppscm, "stage_b_units", "ppscm_symmetric_units.parquet"),
    candidate_pools_path = file.path(
      ppscm, "stage_c_census", "candidate_donor_pools.parquet"),
    screening_features_path = file.path(
      ppscm, "stage_c_census", "firm_screening_features.parquet"),
    validation_dir = file.path(output, "stage_b_validation"),
    control_null_dir = file.path(output, "stage_c_control_null"),
    post_dir = file.path(output, "stage_d_post"),
    report_dir = file.path(output, "stage_e_report"),
    screening_times = -5:-4,
    validation_times = -3:-1,
    pre_times = -5:-1,
    post_times = 0:5,
    primary_post_times = 1:5,
    expected_deals = 235L,
    expected_treated_inventors = 10818L,
    expected_donors_per_deal = 20L,
    validation_rmse_limit = 0.05,
    validation_gap_limit = 0.05,
    deletion_gap_limit = 0.075,
    minimum_effective_deals = 20,
    validation_bootstrap_replications = 9999L,
    validation_bootstrap_seed = 20260730L,
    control_null_draws = 499L,
    control_null_bootstrap_replications = 999L,
    control_null_seed = 20260731L,
    control_null_minimum_comparable_draws = 400L,
    control_null_volume_bounds = c(0.90, 1.10),
    control_null_nominal_deal_bounds = c(0.90, 1.10),
    control_null_effective_deal_bounds = c(0.50, 2.00),
    control_null_max_share_multiplier = 2,
    equivalence_band = 0.05,
    post_bootstrap_replications = 9999L,
    post_bootstrap_seed = 20260801L,
    honestdid_mbar = seq(0, 2, by = 0.25),
    execution = list(threads = 2L, memory_limit = "9GB"))
}

lmv2_uniform_sha256 <- function(path) {
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

lmv2_uniform_atomic_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  utils::write.csv(x, tmp, row.names = FALSE, na = "")
  if (file.exists(path) && !file.remove(path)) {
    stop("Could not replace ", path)
  }
  if (!file.rename(tmp, path)) stop("Could not publish ", path)
  invisible(path)
}

lmv2_uniform_assert_freeze <- function(config) {
  if (!file.exists(config$freeze_path)) stop("Missing uniform top-20 freeze")
  observed <- tolower(lmv2_uniform_sha256(config$freeze_path))
  if (!identical(observed, config$expected_freeze_sha256)) {
    stop(
      "Uniform top-20 freeze mismatch. Expected ",
      config$expected_freeze_sha256, "; observed ", observed)
  }
  observed
}

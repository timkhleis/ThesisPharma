# ============================================================================
# Configuration and small I/O helpers for PPSCM second-attempt census
# ============================================================================

LMV2_PPSCM_V2_VERSION <- "lmv2_ppscm_v2_symmetric_validation_v1"

lmv2_ppscm_v2_config <- function(base = getwd()) {
  base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  analysis_dir <- file.path(base, "02_analysis")
  output_dir <- file.path(
    analysis_dir, "output", "audit", "local_match_v2",
    "P6_PPSCM_V2_SYMMETRIC")
  units_dir <- file.path(output_dir, "stage_b_units")
  census_dir <- file.path(output_dir, "stage_c_census")
  validation_dir <- file.path(output_dir, "stage_d_validation")
  list(
    version = LMV2_PPSCM_V2_VERSION,
    base = base,
    analysis_dir = analysis_dir,
    db_path = file.path(
      analysis_dir, "output", "thesis_foundation.duckdb"),
    freeze_path = file.path(
      analysis_dir, "notes",
      "local_match_v2_ppscm_second_attempt_freeze.md"),
    expected_freeze_sha256 =
      "c1b7907eb4a954e73f2e0775eb736fcc7db575a27fe2c3928394163a5898ee11",
    output_dir = output_dir,
    units_dir = units_dir,
    census_dir = census_dir,
    validation_dir = validation_dir,
    units_path = file.path(
      units_dir, "ppscm_symmetric_units.parquet"),
    units_manifest_path = file.path(
      units_dir, "symmetric_units_manifest.csv"),
    cohorts = 1995:2010,
    screening_times = -5:-4,
    validation_times = -3:-1,
    pre_times = -5:-1,
    donor_pool_cap = 20L,
    donor_pool_sensitivity = c(10L, 20L, 50L),
    screening_metric_sensitivity = c(
      "full", "drop_ipc", "drop_career", "drop_outcome_level"),
    minimum_donor_firms = 5L,
    minimum_donor_cohort_inventors = 5L,
    minimum_retained_deals = 100L,
    minimum_treated_coverage = 0.80,
    census_abort_rmse = 0.10,
    census_abort_max_abs_gap = 0.10,
    ridge_grid = 10^seq(-6, -1),
    validation_equivalence_band = 0.05,
    equal_deal_validation_band = 0.075,
    bootstrap_replications = 9999L,
    bootstrap_seed = 20260729L,
    minimum_median_ess = 2,
    minimum_p10_ess = 1.25,
    maximum_donor_weight = 0.90,
    attempt1_treated_inventors = 3483L,
    attempt1_treated_deals = 203L,
    p5c_supported_treated_inventors = 27078L,
    execution = list(threads = 2L, memory_limit = "9GB"))
}

lmv2_ppscm_sql_string <- function(con, x) {
  as.character(DBI::dbQuoteString(con, x))
}

lmv2_ppscm_atomic_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  utils::write.csv(x, tmp, row.names = FALSE, na = "")
  if (file.exists(path) && !file.remove(path)) {
    stop("Could not replace ", path)
  }
  if (!file.rename(tmp, path)) stop("Could not publish ", path)
  invisible(path)
}

lmv2_ppscm_atomic_lines <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  writeLines(x, tmp, useBytes = TRUE)
  if (file.exists(path) && !file.remove(path)) {
    stop("Could not replace ", path)
  }
  if (!file.rename(tmp, path)) stop("Could not publish ", path)
  invisible(path)
}

lmv2_ppscm_atomic_copy <- function(con, query, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp.parquet")
  if (file.exists(tmp) && !file.remove(tmp)) {
    stop("Could not clear temporary parquet: ", tmp)
  }
  DBI::dbExecute(con, sprintf(
    "COPY (%s) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
    query, lmv2_ppscm_sql_string(con, normalizePath(
      tmp, winslash = "/", mustWork = FALSE))))
  if (file.exists(path) && !file.remove(path)) {
    stop("Could not replace ", path)
  }
  if (!file.rename(tmp, path)) stop("Could not publish ", path)
  invisible(path)
}

lmv2_ppscm_sha256 <- function(path) {
  digest::digest(
    file = path, algo = "sha256", serialize = FALSE)
}

lmv2_ppscm_assert_freeze <- function(config) {
  if (!file.exists(config$freeze_path)) stop("Missing PPSCM v2 freeze")
  observed <- tolower(lmv2_ppscm_sha256(config$freeze_path))
  if (!identical(observed, config$expected_freeze_sha256)) {
    stop(
      "PPSCM v2 freeze hash mismatch. Expected ",
      config$expected_freeze_sha256, "; observed ", observed)
  }
  invisible(observed)
}

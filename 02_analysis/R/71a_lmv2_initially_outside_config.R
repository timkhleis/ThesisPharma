# Local Match v2 initially-outside inventor productivity package.

LMV2_IO_VERSION <- "lmv2_initially_outside_1993_v1"

lmv2_io_existing_root <- function(candidates, relative_path, label) {
  candidates <- unique(candidates[nzchar(candidates)])
  hits <- candidates[file.exists(file.path(candidates, relative_path))]
  if (!length(hits)) {
    stop("Could not locate ", label, ". Checked:\n",
         paste(" -", file.path(candidates, relative_path), collapse = "\n"))
  }
  normalizePath(hits[[1L]], winslash = "/", mustWork = TRUE)
}

lmv2_io_config <- function(base = getwd()) {
  base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  source_root <- lmv2_io_existing_root(
    c(
      Sys.getenv("LMV2_SOURCE_ROOT"),
      Sys.getenv("LMV2_FOUNDATION_ROOT"),
      base
    ),
    file.path("02_analysis", "output", "audit",
              "local_match_v2_1993_amendment", "P5C_ANNUAL_TRAJECTORY",
              "production", "p5c_cell_diagnostics.csv"),
    "the certified 1993 Local Match v2 source root")

  audit_root <- file.path(
    base, "02_analysis", "output", "audit",
    "local_match_v2_1993_amendment")
  source_audit <- file.path(
    source_root, "02_analysis", "output", "audit",
    "local_match_v2_1993_amendment")

  list(
    version = LMV2_IO_VERSION,
    base = base,
    source_root = source_root,
    foundation_db = file.path(
      source_root, "02_analysis", "output", "thesis_foundation.duckdb"),
    p5c_root = file.path(source_audit, "P5C_ANNUAL_TRAJECTORY"),
    p5c_diagnostics = file.path(
      source_audit, "P5C_ANNUAL_TRAJECTORY", "production",
      "p5c_cell_diagnostics.csv"),
    p5c_weight_glob = file.path(
      source_audit, "P5C_ANNUAL_TRAJECTORY", "production", "weights",
      "*.parquet"),
    retained_s3_weights = file.path(
      source_audit, "P5B_STAYER_S3", "s3_primary_weights.parquet"),
    s0_dir = file.path(audit_root, "INITIALLY_OUTSIDE_S0_S2"),
    s3_dir = file.path(audit_root, "INITIALLY_OUTSIDE_S3"),
    s4_dir = file.path(audit_root, "INITIALLY_OUTSIDE_S4_RESULTS"),
    cohorts = 1993:2010,
    censoring_clean_cohorts = 1993:2008,
    event_times = -5:5,
    post_times = 1:5,
    early_post_times = 1:2,
    placeholder_pattern = "^999[0-9]+$",
    support_variants = c(
      "primary_initially_outside_t1_t5",
      "route_consistent_initially_outside_t1_t5",
      "raw_unmixed_initially_outside_t1_t5",
      "early_initially_outside_t1_t2",
      "target_only_initially_outside_t1_t5",
      "censoring_clean_initially_outside_1993_2008"
    ),
    balance_tiers = c(
      "A_cohort_count_active_scale",
      "B_cohort_count_scale",
      "C_era_count_active_scale",
      "D_era_count_scale"
    ),
    eras = list(`1993_1998` = 1993:1998,
                `1999_2004` = 1999:2004,
                `2005_2010` = 2005:2010),
    inv_vars = c(
      paste0("patent_count_m", 5:1),
      paste0("active_patenting_m", 5:1),
      "career_age", "focal_group_exclusivity"),
    firm_vars = c(
      "firm_log_patent_stock_5y", "firm_log_inventor_count_5y"),
    gates = list(
      minimum_treated_retention = 0.80,
      minimum_reuse_adjusted_ess_ratio = 0.50,
      maximum_exact_smd = 1e-6,
      minimum_effective_treated_deals = 20,
      equivalence_percent = 20),
    bootstrap = list(draws = 9999L, seed = 20260818L),
    source_files = file.path(
      base, "02_analysis", "R",
      c("71a_lmv2_initially_outside_config.R",
        "71b_build_lmv2_initially_outside_s0_s2.R",
        "71c_certify_lmv2_initially_outside_s0_s2.R",
        "71_run_lmv2_initially_outside_s0_s2.R",
        "72_build_lmv2_initially_outside_s3.R",
        "final_thesis/73_run_lmv2_initially_outside_s4.R")),
    plan_files = file.path(
      base, "02_analysis", "notes",
      c("local_match_v2_leaver_productivity_implementation_plan.md",
        "local_match_v2_initially_outside_productivity_plan_amendment.md"))
  )
}

lmv2_io_sql_string <- function(x) {
  paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
}

lmv2_io_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write.csv(x, path, row.names = FALSE, na = "")
  invisible(path)
}

lmv2_io_sha256 <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE)) stop("digest is required")
  digest::digest(path, algo = "sha256", file = TRUE, serialize = FALSE)
}

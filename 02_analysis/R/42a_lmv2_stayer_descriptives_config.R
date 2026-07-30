# Package D1 configuration: descriptive retained-status completion.

LMV2_D1_VERSION <- "lmv2_d1_stayer_descriptives_v1"

lmv2_d1_existing_path <- function(candidates, label) {
  candidates <- unique(candidates[nzchar(candidates)])
  hits <- candidates[file.exists(candidates) | dir.exists(candidates)]
  if (!length(hits)) {
    stop(
      "Could not locate ", label, ". Checked:\n",
      paste(" -", candidates, collapse = "\n"),
      call. = FALSE
    )
  }
  normalizePath(hits[[1L]], winslash = "/", mustWork = TRUE)
}

lmv2_d1_config <- function(base = getwd()) {
  base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  audit_root <- file.path(
    base, "02_analysis", "output", "audit", "local_match_v2"
  )
  results_root <- file.path(
    base, "02_analysis", "output", "results", "local_match_v2"
  )
  foundation_db <- lmv2_d1_existing_path(
    c(
      file.path(base, "02_analysis", "output", "thesis_foundation.duckdb"),
      file.path(
        normalizePath(
          file.path(base, "..", ".."),
          winslash = "/", mustWork = TRUE
        ),
        "02_analysis", "output", "thesis_foundation.duckdb"
      )
    ),
    "the foundation database"
  )
  output_dir <- file.path(audit_root, "D1_STAYER_DESCRIPTIVES")
  results_dir <- file.path(results_root, "D1_STAYER_DESCRIPTIVES")

  list(
    version = LMV2_D1_VERSION,
    base = base,
    foundation_db = foundation_db,
    output_dir = output_dir,
    results_dir = results_dir,
    status_partition = file.path(
      audit_root, "P5B_STAYER_S0_S2",
      "treated_retention_partition.parquet"
    ),
    status_certification = file.path(
      audit_root, "P5B_STAYER_S0_S2", "s0_s2_certification.csv"
    ),
    p8_endpoints = file.path(
      audit_root, "P8_EXIT_DECOMPOSITION",
      "global_career_endpoints.parquet"
    ),
    p8_certification = file.path(
      audit_root, "P8_EXIT_DECOMPOSITION",
      "exit_decomposition_certification.csv"
    ),
    retained_weights = file.path(
      audit_root, "P5B_STAYER_S3", "s3_production_weights.parquet"
    ),
    retained_weights_certification = file.path(
      audit_root, "P5B_STAYER_S3", "s3_certification.csv"
    ),
    completion_year_results = file.path(
      audit_root, "P6_COMPLETION_YEAR_SENSITIVITY",
      "completion_year_inclusive_headline.csv"
    ),
    completion_year_dynamic = file.path(
      audit_root, "P6_P5C_ESTIMATION_COUNT_ACTIVE",
      "p6_event_study_dynamic.csv"
    ),
    completion_year_certification = file.path(
      audit_root, "P6_COMPLETION_YEAR_SENSITIVITY",
      "completion_year_certification.csv"
    ),
    master_inventory = file.path(
      results_root, "CURRENT_LOCAL_MATCH_V2", "results_inventory",
      "master_results_inventory.csv"
    ),
    status_groups = c(
      "initially_retained", "leaver", "no_post_patent"
    ),
    state_levels = c(
      "focal_group_only",
      "outside_group_only",
      "both_focal_and_outside",
      "no_patent_later_patent_exists",
      "end_of_observed_patenting",
      "right_censored_not_observable"
    ),
    pre_window = -5:-1,
    post_window = 1:5,
    continuation_event_time = 6L,
    observation_end_year = 2015L,
    management_smd_threshold = 0.20,
    primary_retained_spec = "primary_count_active_scale",
    primary_retained_support = "primary_resolved_t1",
    freeze_file = file.path(
      base, "02_analysis", "notes",
      "local_match_v2_stayer_descriptive_freeze.md"
    ),
    results_note = file.path(
      base, "02_analysis", "notes",
      "local_match_v2_stayer_descriptive_results.md"
    ),
    source_files = file.path(
      base, "02_analysis", "R",
      c(
        "42_run_lmv2_stayer_descriptives.R",
        "42a_lmv2_stayer_descriptives_config.R",
        "42b_build_lmv2_stayer_status_paths.R",
        "42c_analyze_lmv2_stayer_distributions.R",
        "42d_report_certify_lmv2_stayer_descriptives.R"
      )
    )
  )
}

lmv2_d1_sql_string <- function(x) {
  paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
}

lmv2_d1_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
  invisible(path)
}

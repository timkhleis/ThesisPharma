# Package N4 configuration: exploratory retained-inventor team recomposition.

LMV2_N4_VERSION <- "lmv2_n4_team_recomposition_v1"

lmv2_n4_existing_path <- function(path, label) {
  if (!file.exists(path) && !dir.exists(path)) {
    stop("Missing ", label, ": ", path, call. = FALSE)
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

lmv2_n4_config <- function(base = getwd()) {
  base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  audit_root <- file.path(
    base, "02_analysis", "output", "audit", "local_match_v2"
  )
  results_root <- file.path(
    base, "02_analysis", "output", "results", "local_match_v2"
  )
  list(
    version = LMV2_N4_VERSION,
    base = base,
    foundation_db = lmv2_n4_existing_path(
      file.path(base, "02_analysis", "output", "thesis_foundation.duckdb"),
      "foundation database"
    ),
    retained_weights = lmv2_n4_existing_path(
      file.path(
        audit_root, "P5B_STAYER_S3", "s3_production_weights.parquet"
      ),
      "certified S3 production weights"
    ),
    retained_weights_certification = lmv2_n4_existing_path(
      file.path(audit_root, "P5B_STAYER_S3", "s3_certification.csv"),
      "S3 certification"
    ),
    status_partition = lmv2_n4_existing_path(
      file.path(
        audit_root, "P5B_STAYER_S0_S2",
        "treated_retention_partition.parquet"
      ),
      "certified retained-status partition"
    ),
    status_certification = lmv2_n4_existing_path(
      file.path(
        audit_root, "P5B_STAYER_S0_S2", "s0_s2_certification.csv"
      ),
      "retained-status certification"
    ),
    n0_decision = lmv2_n4_existing_path(
      file.path(audit_root, "N0_NETWORK_CENSUS", "n0_support_decision.csv"),
      "N0 support decision"
    ),
    n0_certification = lmv2_n4_existing_path(
      file.path(
        audit_root, "N0_NETWORK_CENSUS",
        "n0_network_census_certification.csv"
      ),
      "N0 certification"
    ),
    freeze_file = lmv2_n4_existing_path(
      file.path(
        base, "02_analysis", "notes",
        "local_match_v2_n4_team_recomposition_freeze.md"
      ),
      "N4 freeze"
    ),
    results_note = file.path(
      base, "02_analysis", "notes",
      "local_match_v2_n4_team_recomposition_results.md"
    ),
    output_dir = file.path(audit_root, "N4_TEAM_RECOMPOSITION"),
    results_dir = file.path(results_root, "N4_TEAM_RECOMPOSITION"),
    study_end_year = 2015L,
    source_files = file.path(
      base, "02_analysis", "R",
      c(
        "47_run_lmv2_n4_team_recomposition.R",
        "47a_lmv2_n4_team_config.R",
        "47b_build_lmv2_n4_team_recomposition.R",
        "47c_report_lmv2_n4_team_recomposition.R",
        "47d_certify_lmv2_n4_team_recomposition.R"
      )
    )
  )
}

lmv2_n4_sql_string <- function(x) {
  paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
}

lmv2_n4_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
  invisible(path)
}

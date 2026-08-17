# Package N0 configuration: outcome-blind network census.

LMV2_N0_VERSION <- "lmv2_n0_network_census_v1"

lmv2_n0_existing_path <- function(candidates, label) {
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

lmv2_n0_config <- function(base = getwd()) {
  base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  audit_root <- file.path(
    base, "02_analysis", "output", "audit", "local_match_v2"
  )
  results_root <- file.path(
    base, "02_analysis", "output", "results", "local_match_v2"
  )
  p6_dir <- file.path(audit_root, "P6_P5C_PANEL_COUNT_ACTIVE")
  p6_manifest <- file.path(p6_dir, "p6_manifest.csv")
  if (!file.exists(p6_manifest)) {
    stop("Missing certified P5c/P6 manifest: ", p6_manifest, call. = FALSE)
  }
  manifest <- utils::read.csv(
    p6_manifest, stringsAsFactors = FALSE, check.names = FALSE
  )
  if (nrow(manifest) != 1L) {
    stop("Expected one certified P5c/P6 manifest row.", call. = FALSE)
  }
  roster_path <- lmv2_n0_existing_path(
    c(
      Sys.getenv("LMV2_P5C_ROSTER"),
      manifest$roster_path
    ),
    "the certified P5c count-active roster"
  )

  list(
    version = LMV2_N0_VERSION,
    base = base,
    foundation_db = lmv2_n0_existing_path(
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
    ),
    p5c_roster = roster_path,
    p5c_roster_sha256 = manifest$roster_sha256,
    p6_manifest = p6_manifest,
    p6_certification = file.path(
      p6_dir, "p6_p5c_reweight_certification.csv"
    ),
    output_dir = file.path(audit_root, "N0_NETWORK_CENSUS"),
    results_dir = file.path(results_root, "N0_NETWORK_CENSUS"),
    freeze_file = file.path(
      base, "02_analysis", "notes",
      "local_match_v2_network_preanalysis_freeze.md"
    ),
    results_note = file.path(
      base, "02_analysis", "notes",
      "local_match_v2_network_census_results.md"
    ),
    anchor_window = -5:-3,
    validation_window = -2:-1,
    study_start_year = 1988L,
    study_end_year = 2015L,
    minimum_joint_applications = 2L,
    minimum_joint_years = 2L,
    meaningful_effect = 0.05,
    gates = list(
      minimum_treated_inventors = 3000L,
      minimum_treated_deals = 150L,
      minimum_effective_treated_deals = 20,
      maximum_treated_deal_weight_share = 0.10,
      minimum_effective_control_deals = 20,
      maximum_control_deal_weight_share = 0.10,
      minimum_treated_composition_rows = 1000L,
      minimum_treated_composition_deals = 100L,
      minimum_composition_effective_treated_deals = 20,
      minimum_composition_effective_control_deals = 20,
      maximum_composition_control_deal_weight_share = 0.10
    ),
    source_files = file.path(
      base, "02_analysis", "R",
      c(
        "43_run_lmv2_network_census.R",
        "43a_lmv2_network_freeze_config.R",
        "43b_build_lmv2_predeal_dyads.R",
        "43c_census_lmv2_network_support.R",
        "43d_certify_lmv2_network_census.R"
      )
    )
  )
}

lmv2_n0_sql_string <- function(x) {
  paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
}

lmv2_n0_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
  invisible(path)
}

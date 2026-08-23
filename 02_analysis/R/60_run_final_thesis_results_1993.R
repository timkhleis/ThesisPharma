#!/usr/bin/env Rscript

# Orchestrator for the missing 1993-cohort thesis packages added in the final
# audit. By default it rebuilds the lightweight release index from completed
# artifacts. Pass --rebuild-new to rerun the new estimators and diagnostics.

options(stringsAsFactors = FALSE)
args <- commandArgs(trailingOnly = TRUE)
rebuild <- "--rebuild-new" %in% args

root <- normalizePath(".", winslash = "/", mustWork = TRUE)
if (!file.exists(file.path(root, "02_analysis", "R", "51_run_cs2021_1993.R"))) {
  stop("Run this script from the thesis repository root.")
}
rscript <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(rscript)) rscript <- file.path(R.home("bin"), "Rscript")

run <- function(script, extra = character()) {
  path <- file.path(root, "02_analysis", "R", script)
  message("[1993 final release] ", script)
  status <- system2(rscript, c(path, extra), stdout = "", stderr = "")
  if (!identical(status, 0L)) stop(script, " failed with status ", status)
}

if (rebuild) {
  run("51_run_cs2021_1993.R", c("--biters=499", "--control-group=notyettreated"))
  run("51_run_cs2021_1993.R", c("--biters=499", "--control-group=nevertreated"))
  run("52_run_lmv2_short_window.R")
  run("53_run_lmv2_timing_placebo.R")
  run("54_run_lmv2_mechanism_selection.R")
  run("55_run_dealsim_exploratory.R")
  run("56_run_lmv2_network_census.R")
  run("57_certify_selection_bounds_decision.R")
  run("60_amend_lmv2_network_n0.R")
  run("61_run_lmv2_network_n1.R")
  run("62_certify_lmv2_network_n2_lock.R")
  run("63_census_lmv2_retained_network_support.R")
  run("64_build_lmv2_network_descriptive.R")
  run("65_run_lmv2_relative_standing.R")
  run("65k_estimate_lmv2_relative_standing_5x5.R")
  run("65m_estimate_lmv2_heterogeneity_pretrends.R")
  p6_root <- file.path(
    root, "02_analysis", "output", "audit",
    "local_match_v2_1993_amendment"
  )
  citation_dir <- file.path(p6_root, "P6_ESTIMATION_CITATIONS_PER_PATENT")
  citation_manifest <- file.path(citation_dir, "p6_estimation_manifest.csv")
  if (!file.exists(citation_manifest)) {
    run("19c_run_lmv2_p6_estimation.R", c(
      paste0(
        "--panel-dir=",
        file.path(p6_root, "P6_P5C_COUNT_ACTIVE", "panel_matched")
      ),
      paste0(
        "--p6-manifest=",
        file.path(p6_root, "P6_P5C_COUNT_ACTIVE", "p6_manifest.csv")
      ),
      paste0("--output-dir=", citation_dir),
      "--outcomes=fwd_cits5_conditional_mean"
    ))
  } else {
    message(
      "[1993 final release] Reusing certified citations-per-patent estimate: ",
      citation_manifest
    )
  }
}

run("58_build_final_thesis_release_1993.R")
run("59_build_final_thesis_tables_1993.R")
message("1993 final thesis-results release is complete.")

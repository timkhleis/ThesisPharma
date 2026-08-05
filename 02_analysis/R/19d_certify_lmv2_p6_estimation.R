# ============================================================================
# 19d_certify_lmv2_p6_estimation.R -- terminal checks for P6 core estimates
# ============================================================================
# Usage:
# Rscript 02_analysis/R/19d_certify_lmv2_p6_estimation.R
#   --estimation-dir=<completed production estimation directory>

args <- commandArgs(trailingOnly = TRUE)
hit <- grep("^--estimation-dir=", args, value = TRUE)
if (length(hit) != 1L) stop("19d requires --estimation-dir=")
ESTIMATION_DIR <- sub("^--estimation-dir=", "", hit)
DIAGNOSTIC_MODE <- "--diagnostic" %in% args
if (!dir.exists(ESTIMATION_DIR)) {
  stop("Estimation directory not found: ", ESTIMATION_DIR)
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))

required_files <- c(
  manifest = "p6_estimation_manifest.csv",
  input = "p6_estimation_input_certification.csv",
  dynamic = "p6_event_study_dynamic.csv",
  pretrend = "p6_joint_pretrend_tests.csv",
  headline = "p6_headline_post_att.csv",
  coverage = "p6_outcome_pair_coverage.csv",
  progress = "p6_estimation_progress.csv"
)
paths <- stats::setNames(
  file.path(ESTIMATION_DIR, unname(required_files)),
  names(required_files)
)
if (!all(file.exists(paths))) {
  stop("Missing estimation artifacts: ",
       paste(required_files[!file.exists(paths)], collapse = ", "))
}

manifest <- utils::read.csv(paths[["manifest"]], stringsAsFactors = FALSE)
input <- utils::read.csv(paths[["input"]], stringsAsFactors = FALSE)
dynamic <- utils::read.csv(paths[["dynamic"]], stringsAsFactors = FALSE)
pretrend <- utils::read.csv(paths[["pretrend"]], stringsAsFactors = FALSE)
headline <- utils::read.csv(paths[["headline"]], stringsAsFactors = FALSE)
coverage <- utils::read.csv(paths[["coverage"]], stringsAsFactors = FALSE)
progress <- utils::read.csv(paths[["progress"]], stringsAsFactors = FALSE)

checks <- list()
add <- function(name, pass, detail = "") {
  checks[[length(checks) + 1L]] <<- data.frame(
    check = name, pass = isTRUE(pass), detail = as.character(detail),
    stringsAsFactors = FALSE
  )
}

expected_outcomes <- if (DIAGNOSTIC_MODE) {
  strsplit(manifest$outcomes[[1]], ";", fixed = TRUE)[[1]]
} else {
  LMV2_P6_ESTIMATION$core_outcomes
}
expected_samples <- names(LMV2_P6_ESTIMATION$samples)
expected_cells <- expand.grid(
  outcome = expected_outcomes, sample = expected_samples,
  stringsAsFactors = FALSE
)

add("production_manifest_single_row",
    nrow(manifest) == 1L && manifest$run_mode[[1]] == "production")
add("estimation_hash_current",
    manifest$estimation_hash[[1]] == lmv2_p6_estimation_hash())
add("freeze_hash_current",
    manifest$preanalysis_freeze_sha256[[1]] ==
      LMV2_P6_PREANALYSIS_FREEZE_SHA256)
add("input_certification_pass",
    isTRUE(input$pass[[1]]) &&
      isTRUE(manifest$input_certification_pass[[1]]))
add("full_panel_grain",
    input$panel_rows[[1]] == 5638875 &&
      input$units[[1]] == 512625 &&
      input$cohorts[[1]] == 18 &&
      input$deals[[1]] == 343)
add("no_input_defects",
    all(input[c(
      "bad_units", "bad_masses", "bad_treated_weights", "bad_weights"
    )] == 0))
add("frozen_bootstrap_replications",
    manifest$bootstrap_replications[[1]] ==
      LMV2_P6_ESTIMATION$inference$replications)
add("stayer_att_not_authorized",
    identical(manifest$stayer_att_authorized[[1]], FALSE))
add("complete_outcome_sample_grid",
    nrow(progress) == nrow(expected_cells) &&
      all(expected_cells$outcome %in% progress$outcome) &&
      all(expected_cells$sample %in% progress$sample))

avg <- headline[headline$summary == "average_annual_t1_to_t5", ]
cum <- headline[headline$summary == "cumulative_t1_to_t5", ]
add("headline_row_count",
    nrow(avg) == nrow(expected_cells) * 3L &&
      nrow(cum) == nrow(expected_cells) * 3L)

point_spread <- aggregate(
  estimate ~ outcome + sample, avg,
  function(x) max(x) - min(x)
)
add("inference_point_estimates_identical",
    max(abs(point_spread$estimate)) < 1e-9,
    sprintf("max_spread=%.3e", max(abs(point_spread$estimate))))

merge_keys <- c("outcome", "sample", "inference")
scaled <- merge(
  avg[, c(merge_keys, "estimate", "ci_low", "ci_high")],
  cum[, c(merge_keys, "estimate", "ci_low", "ci_high")],
  by = merge_keys, suffixes = c("_avg", "_cum")
)
scale_error <- max(abs(c(
  scaled$estimate_cum - 5 * scaled$estimate_avg,
  scaled$ci_low_cum - 5 * scaled$ci_low_avg,
  scaled$ci_high_cum - 5 * scaled$ci_high_avg
)))
add("cumulative_is_five_times_average", scale_error < 1e-9,
    sprintf("max_error=%.3e", scale_error))

governing <- aggregate(
  governing ~ outcome + sample + summary, headline, sum
)
add("one_governing_interval_per_result",
    all(governing$governing == 1L))
add("all_headline_intervals_finite",
    all(is.finite(headline$estimate)) &&
      all(is.finite(headline$ci_low)) &&
      all(is.finite(headline$ci_high)) &&
      all(headline$ci_low <= headline$estimate) &&
      all(headline$estimate <= headline$ci_high))

dynamic_counts <- aggregate(
  event_time ~ outcome + sample, dynamic, length
)
add("dynamic_window_complete",
    nrow(dynamic_counts) == nrow(expected_cells) &&
      all(dynamic_counts$event_time == 11L))
reference <- dynamic[dynamic$event_time == -1, ]
add("reference_period_exact_zero",
    nrow(reference) == nrow(expected_cells) &&
      all(reference$estimate == 0) &&
      all(reference$se == 0))
add("pretrend_grid_complete_and_finite",
    nrow(pretrend) == nrow(expected_cells) &&
      all(is.finite(pretrend$f_stat)) &&
      all(is.finite(pretrend$p_value)))

expected_coverage_rows <- length(expected_outcomes) * sum(vapply(
  LMV2_P6_ESTIMATION$samples, length, integer(1))) * 10L * 2L
add("coverage_grid_complete", nrow(coverage) == expected_coverage_rows)
complete_primary <- coverage[
  coverage$outcome %in% c("patent_count", "active_patenting"), ]
if (!DIAGNOSTIC_MODE) {
  add("count_outcomes_full_pair_coverage",
      all(complete_primary$eligible_cohort_event) &&
        min(complete_primary$pair_weight_coverage) > 1 - 1e-10)
}
add("availability_share_valid",
    all(coverage$retained_design_share > 0 &
          coverage$retained_design_share <= 1 + 1e-10))
unavailable <- coverage[!coverage$eligible_cohort_event, ]
if (!DIAGNOSTIC_MODE) {
  unavailable_key <- unique(paste(
    unavailable$outcome, unavailable$sample,
    unavailable$cohort, unavailable$event_time, sep = "|"
  ))
  expected_unavailable <- c(
    "tech_drift|full_1993_2010|1996|-5",
    "tech_drift|full_1993_2010|2010|5"
  )
  add("only_predeclared_techdrift_cells_unavailable",
      identical(sort(unavailable_key), sort(expected_unavailable)),
      paste(sort(unavailable_key), collapse = ";"))
} else {
  add("diagnostic_unavailability_reported",
      nrow(coverage) > 0,
      sprintf("unavailable_rows=%d", nrow(unavailable)))
}

file_text <- paste(
  unlist(lapply(
    paths[c("dynamic", "pretrend", "headline", "coverage", "progress")],
    readLines, warn = FALSE
  )),
  collapse = "\n"
)
add("no_stayer_result_artifact",
    !grepl("stayer_att|ATT_stayer", file_text, ignore.case = TRUE))

checks <- do.call(rbind, checks)
utils::write.csv(
  checks, file.path(ESTIMATION_DIR, "p6_estimation_certification.csv"),
  row.names = FALSE, na = ""
)
if (!all(checks$pass)) {
  stop("P6 estimation certification failed: ",
       paste(checks$check[!checks$pass], collapse = ", "))
}

artifact_hashes <- vapply(
  paths, digest::digest, character(1), file = TRUE, algo = "sha256"
)
cert_manifest <- data.frame(
  estimation_version = LMV2_P6_ESTIMATION_VERSION,
  certification_mode = if (DIAGNOSTIC_MODE) "diagnostic" else "core",
  estimation_hash = lmv2_p6_estimation_hash(),
  freeze_sha256 = LMV2_P6_PREANALYSIS_FREEZE_SHA256,
  n_checks = nrow(checks),
  n_failed = sum(!checks$pass),
  artifact_bundle_sha256 =
    digest::digest(artifact_hashes, algo = "sha256", serialize = TRUE),
  certified_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  stringsAsFactors = FALSE
)
utils::write.csv(
  cert_manifest,
  file.path(ESTIMATION_DIR, "p6_estimation_certification_manifest.csv"),
  row.names = FALSE
)
message(sprintf(
  "P6 ESTIMATION PASS | checks=%d | bundle=%s",
  nrow(checks), cert_manifest$artifact_bundle_sha256
))

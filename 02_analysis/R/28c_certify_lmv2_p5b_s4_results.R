# Certify the frozen P5b S4 initially-retained quantity results.

if (!exists("lmv2_p5b_s4_config")) {
  source(file.path("02_analysis", "R", "28a_lmv2_p5b_s4_config.R"))
}

lmv2_certify_p5b_s4 <- function(config = lmv2_p5b_s4_config()) {
  required <- file.path(
    config$output_dir,
    c(
      "s4_base_panel_certification.csv",
      "s4_weight_panel_mapping.csv",
      "s4_event_study_dynamic.csv",
      "s4_joint_pretrend_tests.csv",
      "s4_headline_post_att.csv",
      "s4_outcome_pair_coverage.csv",
      "s4_estimation_progress.csv",
      "s4_estimation_manifest.csv"))
  required <- c(
    required, config$freeze_file, config$source_files,
    config$s3_weights, config$s3_manifest, config$s3_certification)
  missing <- required[!file.exists(required)]
  if (length(missing)) {
    stop("Missing S4 certification input: ", paste(missing, collapse = ", "))
  }

  read_output <- function(name) {
    utils::read.csv(
      file.path(config$output_dir, name), stringsAsFactors = FALSE)
  }
  base <- read_output("s4_base_panel_certification.csv")
  mapping <- read_output("s4_weight_panel_mapping.csv")
  dynamic <- read_output("s4_event_study_dynamic.csv")
  pretrend <- read_output("s4_joint_pretrend_tests.csv")
  headline <- read_output("s4_headline_post_att.csv")
  coverage <- read_output("s4_outcome_pair_coverage.csv")
  progress <- read_output("s4_estimation_progress.csv")
  estimation_manifest <- read_output("s4_estimation_manifest.csv")
  s3_manifest <- utils::read.csv(
    config$s3_manifest, stringsAsFactors = FALSE)

  checks <- list()
  add <- function(name, pass, detail = "") {
    checks[[length(checks) + 1L]] <<- data.frame(
      check = name, pass = isTRUE(pass), detail = as.character(detail),
      stringsAsFactors = FALSE)
  }

  expected_cells <- expand.grid(
    spec = config$production_specs,
    sample = names(config$samples),
    outcome = config$outcomes,
    stringsAsFactors = FALSE)
  cell_key <- function(x) {
    paste(x$spec, x$sample, x$outcome, sep = "::")
  }
  expected_keys <- sort(cell_key(expected_cells))
  progress_keys <- sort(cell_key(progress))

  add("production_manifest_single_row",
      nrow(estimation_manifest) == 1L)
  add("production_run_complete",
      identical(estimation_manifest$run_mode, "production"))
  add("execution_hash_matches_freeze",
      identical(
        estimation_manifest$execution_hash,
        lmv2_p5b_s4_hash(config)))
  add("freeze_hash_matches_manifest",
      identical(
        estimation_manifest$freeze_sha256,
        digest::digest(
          config$freeze_file, algo = "sha256", file = TRUE,
          serialize = FALSE)))
  s3_weight_row <- s3_manifest[
    s3_manifest$artifact == basename(config$s3_weights), ]
  add("s3_weights_match_certified_manifest",
      nrow(s3_weight_row) == 1L &&
        identical(
          estimation_manifest$s3_weights_sha256,
          s3_weight_row$sha256))
  add("base_panel_certification_passes",
      nrow(base) == 1L && isTRUE(base$pass[[1L]]))
  add("weight_panel_mapping_passes",
      nrow(mapping) == 1L && isTRUE(mapping$pass[[1L]]))
  add("all_24_cells_present",
      identical(progress_keys, expected_keys), nrow(progress))
  add("no_duplicate_progress_cells",
      !anyDuplicated(progress_keys))

  dynamic_counts <- table(cell_key(dynamic))
  pretrend_counts <- table(cell_key(pretrend))
  headline_counts <- table(cell_key(headline))
  coverage_counts <- table(cell_key(coverage))
  add("dynamic_has_eleven_coefficients_per_cell",
      identical(sort(names(dynamic_counts)), expected_keys) &&
        all(dynamic_counts == length(config$event_window)))
  add("one_pretrend_test_per_cell",
      identical(sort(names(pretrend_counts)), expected_keys) &&
        all(pretrend_counts == 1L))
  add("six_headline_rows_per_cell",
      identical(sort(names(headline_counts)), expected_keys) &&
        all(headline_counts == 6L))
  expected_coverage_counts <- vapply(
    names(coverage_counts), function(key) {
      sample_id <- strsplit(key, "::", fixed = TRUE)[[1L]][[2L]]
      2L * length(setdiff(
        config$event_window, config$reference_event_time)) *
        length(config$samples[[sample_id]])
    }, integer(1))
  add("coverage_has_cohort_event_arm_rows_per_cell",
      identical(sort(names(coverage_counts)), expected_keys) &&
        all(as.integer(coverage_counts) == expected_coverage_counts))

  add("dynamic_event_set_is_frozen",
      identical(
        sort(unique(as.integer(dynamic$event_time))),
        config$event_window))
  add("all_estimates_finite",
      all(is.finite(dynamic$estimate)) &&
        all(is.finite(headline$estimate)))
  add("all_confidence_intervals_ordered",
      all(headline$ci_low <= headline$ci_high) &&
        all(dynamic$ci_low <= dynamic$ci_high))
  add("all_p_values_valid",
      all(pretrend$p_value >= 0 & pretrend$p_value <= 1) &&
        all(headline$p_value >= 0 & headline$p_value <= 1))
  add("wild_bootstrap_uses_9999_draws",
      all(headline$bootstrap_replications[
        headline$inference == "deal_wild_bootstrap_t"] ==
          config$bootstrap_replications))

  annual <- headline[
    headline$summary == "average_annual_t1_to_t5", ]
  cumulative <- headline[
    headline$summary == "cumulative_t1_to_t5", ]
  merge_keys <- c("spec", "sample", "outcome", "inference")
  scale_check <- merge(
    annual, cumulative, by = merge_keys, suffixes = c("_a", "_c"))
  add("cumulative_patent_effect_is_five_times_annual",
      max(abs(
        scale_check$estimate_c[scale_check$outcome == "patent_count"] -
          5 * scale_check$estimate_a[
            scale_check$outcome == "patent_count"])) <= 1e-10)

  inference_spread <- aggregate(
    estimate ~ spec + sample + outcome + summary,
    data = headline,
    FUN = function(x) max(x) - min(x))
  add("point_estimator_matches_across_inference_methods",
      max(inference_spread$estimate) <= 1e-8,
      max(inference_spread$estimate))
  governing_counts <- aggregate(
    governing ~ spec + sample + outcome + summary,
    data = headline, FUN = sum)
  add("one_governing_interval_per_result",
      all(governing_counts$governing == 1L))
  add("primary_full_sample_has_151_deals",
      all(annual$nominal_treated_deals[
        annual$spec == config$production_specs[[1L]] &
          annual$sample == "full_1994_2010"] == 151L))
  primary_effective_deals <- unique(annual$effective_treated_deals[
    annual$spec == config$production_specs[[1L]] &
      annual$sample == "full_1994_2010"])
  add("primary_effective_deals_at_least_20",
      length(primary_effective_deals) == 1L &&
        primary_effective_deals >= 20,
      paste(primary_effective_deals, collapse = ";"))
  add("pair_coverage_is_complete_for_quantity",
      all(abs(coverage$pair_weight_coverage - 1) <= 1e-12),
      min(coverage$pair_weight_coverage))

  # Positive tooth tests: each protected rule must fail on a real mutation.
  duplicate_progress <- rbind(progress, progress[1L, ])
  duplicate_tooth <- anyDuplicated(cell_key(duplicate_progress)) > 0L
  corrupt_scale <- scale_check
  patent_index <- which(corrupt_scale$outcome == "patent_count")[[1L]]
  corrupt_scale$estimate_c[patent_index] <-
    corrupt_scale$estimate_c[patent_index] + 1
  scale_tooth <- max(abs(
    corrupt_scale$estimate_c[
      corrupt_scale$outcome == "patent_count"] -
      5 * corrupt_scale$estimate_a[
        corrupt_scale$outcome == "patent_count"])) > 1e-10
  hash_tooth <- !identical(
    paste0(estimation_manifest$execution_hash, "x"),
    lmv2_p5b_s4_hash(config))
  corrupted_mapping <- mapping
  corrupted_mapping$mapped_rows <-
    corrupted_mapping$mapped_rows - 1L
  corrupted_mapping_pass <-
    corrupted_mapping$weight_rows == corrupted_mapping$mapped_rows &&
    is.na(corrupted_mapping$duplicate_map_positive) &&
    corrupted_mapping$specifications ==
      length(config$production_specs) &&
    corrupted_mapping$minimum_cohorts == 17L &&
    corrupted_mapping$bad_spec_maps == 0L &&
    corrupted_mapping$bad_panel_counts == 0L
  map_tooth <- !isTRUE(corrupted_mapping_pass)
  tooth <- data.frame(
    test = c(
      "duplicate_cell_fires", "cumulative_corruption_fires",
      "execution_hash_drift_fires", "mapping_failure_fires"),
    pass = c(duplicate_tooth, scale_tooth, hash_tooth, map_tooth),
    stringsAsFactors = FALSE)
  add("all_tooth_tests_pass", all(tooth$pass))

  certification <- do.call(rbind, checks)
  certification_path <- file.path(
    config$output_dir, "s4_certification.csv")
  tooth_path <- file.path(config$output_dir, "s4_tooth_tests.csv")
  utils::write.csv(
    certification, certification_path, row.names = FALSE)
  utils::write.csv(tooth, tooth_path, row.names = FALSE)

  artifact_paths <- c(
    file.path(config$output_dir, c(
      "s4_event_study_dynamic.csv",
      "s4_joint_pretrend_tests.csv",
      "s4_headline_post_att.csv",
      "s4_outcome_pair_coverage.csv",
      "s4_estimation_progress.csv",
      "s4_estimation_manifest.csv",
      "s4_base_panel_certification.csv",
      "s4_weight_panel_mapping.csv")),
    certification_path, tooth_path, config$freeze_file)
  final_manifest <- data.frame(
    artifact = basename(artifact_paths),
    path = normalizePath(
      artifact_paths, winslash = "/", mustWork = TRUE),
    sha256 = vapply(
      artifact_paths, digest::digest, character(1),
      algo = "sha256", file = TRUE, serialize = FALSE),
    execution_hash = lmv2_p5b_s4_hash(config),
    stringsAsFactors = FALSE)
  utils::write.csv(
    final_manifest,
    file.path(config$output_dir, "s4_manifest.csv"),
    row.names = FALSE)

  if (!all(certification$pass)) {
    stop(
      "S4 certification failed: ",
      paste(certification$check[!certification$pass], collapse = ", "))
  }
  invisible(list(
    certification = certification,
    tooth = tooth,
    primary_effective_deals = primary_effective_deals))
}

if (sys.nframe() == 0L) {
  lmv2_certify_p5b_s4()
}

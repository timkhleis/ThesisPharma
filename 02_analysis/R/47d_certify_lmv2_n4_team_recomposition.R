# Package N4: certify exploratory retained-inventor team recomposition.

if (!exists("lmv2_n4_config")) {
  source(file.path(
    "02_analysis", "R", "47a_lmv2_n4_team_config.R"
  ))
}

lmv2_n4_all_true <- function(path) {
  x <- utils::read.csv(
    path, stringsAsFactors = FALSE, check.names = FALSE
  )
  "pass" %in% names(x) && nrow(x) > 0L &&
    !anyNA(x$pass) && all(tolower(as.character(x$pass)) == "true")
}

lmv2_n4_certify <- function(config = lmv2_n4_config()) {
  source(file.path(config$base, "02_analysis", "R", "00_utils.R"))
  use_project_library()
  shared_lib <- file.path(
    normalizePath(
      file.path(config$base, "..", ".."),
      winslash = "/", mustWork = TRUE
    ),
    ".r_libs"
  )
  if (dir.exists(shared_lib)) {
    .libPaths(unique(c(shared_lib, .libPaths())))
  }
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Missing package: digest", call. = FALSE)
  }
  audit_csv <- function(name) utils::read.csv(
    file.path(config$output_dir, name),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  result_csv <- function(name) utils::read.csv(
    file.path(config$results_dir, name),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  construction <- audit_csv("n4_construction_audit.csv")
  attestation <- audit_csv("n4_freeze_attestation.csv")
  annual <- result_csv("composition_annual.csv")
  pooled <- result_csv("composition_pooled.csv")
  raw <- result_csv("raw_composition.csv")
  coverage <- result_csv("tie_coverage.csv")
  recurrence <- result_csv("tie_recurrence.csv")
  denominators <- result_csv("denominator_audit.csv")
  mixed <- result_csv("mixed_audit.csv")
  n0 <- utils::read.csv(
    config$n0_decision, stringsAsFactors = FALSE, check.names = FALSE
  )
  note_text <- paste(
    readLines(config$results_note, warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )
  annual_sums <- aggregate(
    weighted_share ~ event_time, data = annual, sum
  )
  required_categories <- c(
    "legacy_target", "legacy_acquirer", "new_to_both", "outside_group"
  )
  strict_coverage <- coverage$weighted_coverage[
    coverage$tie_definition == "strict_persistent"
  ]
  weak_coverage <- coverage$weighted_coverage[
    coverage$tie_definition == "weak_one_patent"
  ]
  artifact_paths <- c(
    file.path(
      config$output_dir,
      c(
        "n4_freeze_attestation.csv",
        "n4_construction_audit.csv",
        "n4_roster.parquet",
        "post_collaborator_appearances.parquet",
        "baseline_ties.parquet",
        "tie_recurrence.parquet",
        "focal_year_team_denominators.parquet"
      )
    ),
    file.path(
      config$results_dir,
      c(
        "composition_annual.csv",
        "composition_pooled.csv",
        "raw_composition.csv",
        "tie_coverage.csv",
        "tie_recurrence.csv",
        "denominator_audit.csv",
        "mixed_audit.csv",
        "figure_team_recomposition.png",
        "table_tie_recurrence.tex"
      )
    ),
    config$results_note
  )
  checks <- data.frame(
    check = c(
      "freeze_predates_outcome_construction",
      "freeze_hash_matches_current_file",
      "upstream_status_certification_passes",
      "upstream_weight_certification_passes",
      "n0_path_q_remains_closed",
      "construction_audit_passes",
      "retained_population_is_2663_inventors_151_deals",
      "all_defined_appearances_have_one_category",
      "annual_category_grid_is_complete",
      "annual_focal_normalized_shares_sum_to_one",
      "pooled_focal_normalized_shares_sum_to_one",
      "raw_appearance_shares_sum_to_one",
      "weak_anchor_coverage_is_not_below_strict",
      "tie_recurrence_has_both_definitions_and_five_horizons",
      "team_denominator_grid_has_five_horizons",
      "unresolved_rows_are_separately_audited",
      "results_are_labelled_exploratory_and_descriptive",
      "results_note_has_no_inferential_claim",
      "all_declared_artifacts_exist",
      "all_declared_sources_exist"
    ),
    pass = c(
      tolower(attestation$post_outcomes_opened_only_after_freeze) == "true" &&
        as.POSIXct(
          attestation$freeze_modified_utc,
          format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
        ) <
          as.POSIXct(
            attestation$construction_started_utc,
            format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
          ),
      identical(
        attestation$freeze_sha256,
        digest::digest(
          file = config$freeze_file, algo = "sha256", serialize = FALSE
        )
      ),
      lmv2_n4_all_true(config$status_certification),
      lmv2_n4_all_true(config$retained_weights_certification),
      nrow(n0) == 1L &&
        n0$decision == "feasibility_only_stop_before_N1" &&
        tolower(n0$post_treatment_effects_opened) == "false",
      nrow(construction) == 1L &&
        tolower(construction$pass) == "true",
      construction$roster_inventors == 2663L &&
        construction$roster_deals == 151L,
      construction$defined_rows_without_category == 0L,
      nrow(annual) == 5L * length(required_categories) &&
        setequal(annual$category, required_categories),
      nrow(annual_sums) == 5L &&
        all(abs(annual_sums$weighted_share - 1) < 1e-10),
      abs(sum(pooled$weighted_share) - 1) < 1e-10 &&
        setequal(pooled$category, required_categories),
      abs(sum(raw$raw_share) - 1) < 1e-10 &&
        setequal(raw$category, required_categories),
      length(strict_coverage) == 1L &&
        length(weak_coverage) == 1L &&
        weak_coverage >= strict_coverage,
      setequal(
        recurrence$tie_definition,
        c("strict_persistent", "weak_one_patent")
      ) &&
        setequal(recurrence$horizon, 1:5) &&
        nrow(recurrence) == 10L,
      setequal(denominators$event_time, 1:5) &&
        nrow(denominators) == 5L,
      mixed$unresolved_appearances ==
        construction$unresolved_post_appearances,
      grepl(
        "exploratory and descriptive", note_text, fixed = TRUE
      ) &&
        grepl("N0 Path Q decision remains unchanged", note_text, fixed = TRUE),
      !grepl("95% CI|p-value|p =", note_text),
      all(file.exists(artifact_paths)),
      all(file.exists(config$source_files))
    ),
    stringsAsFactors = FALSE
  )
  certification_path <- file.path(
    config$output_dir, "n4_team_recomposition_certification.csv"
  )
  lmv2_n4_write_csv(checks, certification_path)
  if (!all(checks$pass)) {
    stop(
      "N4 certification failed: ",
      paste(checks$check[!checks$pass], collapse = ", "),
      call. = FALSE
    )
  }
  manifest_paths <- c(
    artifact_paths, certification_path, config$freeze_file,
    config$status_partition, config$retained_weights,
    config$n0_decision, config$source_files
  )
  manifest <- data.frame(
    path = normalizePath(
      manifest_paths, winslash = "/", mustWork = TRUE
    ),
    sha256 = vapply(
      manifest_paths,
      digest::digest,
      character(1),
      file = TRUE,
      algo = "sha256",
      serialize = FALSE
    ),
    bytes = unname(file.info(manifest_paths)$size),
    stringsAsFactors = FALSE
  )
  lmv2_n4_write_csv(
    manifest,
    file.path(config$output_dir, "n4_team_recomposition_manifest.csv")
  )
  invisible(checks)
}

if (sys.nframe() == 0L) {
  checks <- lmv2_n4_certify()
  message(
    "N4 team recomposition certified: ",
    sum(checks$pass), "/", nrow(checks), " checks pass."
  )
}

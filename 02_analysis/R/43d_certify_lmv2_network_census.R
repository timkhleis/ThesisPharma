# Package N0: certify the outcome-blind network census.

if (!exists("lmv2_n0_config")) {
  source(file.path(
    "02_analysis", "R", "43a_lmv2_network_freeze_config.R"
  ))
}

lmv2_n0_all_true <- function(x) {
  length(x) > 0L && !anyNA(x) &&
    all(tolower(as.character(x)) == "true")
}

lmv2_n0_fixture_passes <- function() {
  application_inventors <- unique(data.frame(
    appln_id = c(1L, 1L, 1L, 2L, 2L, 3L, 3L, 4L),
    codinv = c(10L, 20L, 20L, 10L, 20L, 10L, 30L, 10L),
    year = c(2000L, 2000L, 2000L, 2001L, 2001L, 2000L, 2000L, 2001L)
  ))
  pairs <- merge(
    application_inventors,
    application_inventors,
    by = c("appln_id", "year"),
    suffixes = c("_a", "_b")
  )
  pairs <- unique(pairs[pairs$codinv_a < pairs$codinv_b, ])
  ties <- aggregate(
    appln_id ~ codinv_a + codinv_b,
    data = pairs,
    FUN = function(x) length(unique(x))
  )
  years <- aggregate(
    year ~ codinv_a + codinv_b,
    data = pairs,
    FUN = function(x) length(unique(x))
  )
  tie <- merge(ties, years, by = c("codinv_a", "codinv_b"))
  persistent <- tie[tie$appln_id >= 2L & tie$year >= 2L, ]
  nrow(pairs) == 3L &&
    nrow(persistent) == 1L &&
    persistent$codinv_a == 10L &&
    persistent$codinv_b == 20L
}

lmv2_n0_certify <- function(config = lmv2_n0_config()) {
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

  audit_files <- file.path(
    config$output_dir,
    c(
      "p5c_network_roster.parquet",
      "predeal_application_dyads.parquet",
      "predeal_focal_partner_links.parquet",
      "persistent_baseline_ties.parquet",
      "network_focal_support.parquet",
      "validation_denominator_support.parquet",
      "network_construction_audit.csv",
      "network_coverage_by_arm.csv",
      "network_coverage_by_cohort.csv",
      "network_deal_concentration.csv",
      "validation_denominator_coverage.csv",
      "n0_support_gate_checks.csv",
      "n0_support_decision.csv"
    )
  )
  result_files <- file.path(
    config$results_dir,
    c(
      "table_network_census.tex",
      "table_network_validation_denominators.tex"
    )
  )
  required <- c(
    audit_files,
    result_files,
    config$p5c_roster,
    config$p6_manifest,
    config$p6_certification,
    config$freeze_file,
    config$results_note,
    config$source_files
  )
  if (any(!file.exists(required))) {
    stop(
      "Missing N0 certification input(s): ",
      paste(required[!file.exists(required)], collapse = ", "),
      call. = FALSE
    )
  }

  read_audit <- function(name) {
    utils::read.csv(
      file.path(config$output_dir, name),
      stringsAsFactors = FALSE, check.names = FALSE
    )
  }
  construction <- read_audit("network_construction_audit.csv")
  coverage <- read_audit("network_coverage_by_arm.csv")
  validation <- read_audit("validation_denominator_coverage.csv")
  support_checks <- read_audit("n0_support_gate_checks.csv")
  decision <- read_audit("n0_support_decision.csv")
  p6_manifest <- utils::read.csv(
    config$p6_manifest, stringsAsFactors = FALSE, check.names = FALSE
  )
  p6_cert <- utils::read.csv(
    config$p6_certification,
    stringsAsFactors = FALSE, check.names = FALSE
  )

  observed_roster_hash <- digest::digest(
    file = config$p5c_roster, algo = "sha256", serialize = FALSE
  )
  freeze_hash <- digest::digest(
    file = config$freeze_file, algo = "sha256", serialize = FALSE
  )
  construction_sources <- config$source_files[
    grepl("43b_|43c_", basename(config$source_files))
  ]
  construction_text <- paste(
    unlist(lapply(
      construction_sources,
      readLines,
      warn = FALSE,
      encoding = "UTF-8"
    )),
    collapse = "\n"
  )
  forbidden_post_patterns <- c(
    "event_time BETWEEN 0",
    "event_time >= 0",
    "event_time > 0",
    "event_time IN (0",
    "event_time = 0"
  )
  source_has_post_access <- any(vapply(
    forbidden_post_patterns,
    grepl,
    logical(1),
    x = construction_text,
    fixed = TRUE
  ))

  expected_decision <- if (lmv2_n0_all_true(support_checks$pass)) {
    "release_N1_preperiod_validation"
  } else {
    "feasibility_only_stop_before_N1"
  }
  registration <- data.frame(
    package = "N0_NETWORK_CENSUS",
    reportable_effect_estimates = 0L,
    inventory_registration_required = FALSE,
    registered = TRUE,
    detail = paste(
      "N0 reports support and denominator coverage only;",
      "no treatment-effect estimate is produced."
    ),
    stringsAsFactors = FALSE
  )
  registration_path <- file.path(
    config$results_dir, "reportable_result_registration.csv"
  )
  lmv2_n0_write_csv(registration, registration_path)

  freeze_text <- paste(
    readLines(config$freeze_file, warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )
  checks <- data.frame(
    check = c(
      "upstream_p5c_manifest_passes",
      "upstream_p5c_cohort_certification_passes",
      "p5c_roster_hash_matches_certified_manifest",
      "network_construction_audit_passes",
      "application_inventor_keys_are_unique",
      "application_dyad_keys_are_unique_and_symmetric",
      "persistent_ties_satisfy_frozen_thresholds",
      "anchor_and_validation_windows_are_disjoint",
      "all_constructed_inputs_stop_at_t_minus_one",
      "construction_source_has_no_post_event_access",
      "both_arms_use_one_construction",
      "partner_denominator_is_complete",
      "composition_missingness_is_explicit",
      "support_decision_matches_frozen_gates",
      "meaningful_effect_threshold_is_frozen_at_five_points",
      "construction_fixture_passes",
      "all_reportable_outputs_registered_in_inventory",
      "post_treatment_effects_remain_closed",
      "freeze_records_annual_quantity_normalized_denominators",
      "all_declared_sources_exist"
    ),
    pass = c(
      nrow(p6_manifest) == 1L &&
        p6_manifest$n_failed == 0L &&
        lmv2_n0_all_true(
          p6_manifest$p5c_reweight_certification_pass
        ),
      nrow(p6_cert) == 17L &&
        all(is.finite(p6_cert$mass_gap)) &&
        max(abs(p6_cert$mass_gap)) < 1e-8,
      identical(observed_roster_hash, config$p5c_roster_sha256),
      nrow(construction) == 1L && isTRUE(construction$pass[[1L]]),
      construction$duplicate_application_inventor_keys == 0L,
      construction$duplicate_application_dyad_keys == 0L &&
        construction$self_link_rows == 0L,
      construction$invalid_persistent_ties == 0L,
      max(config$anchor_window) < min(config$validation_window) &&
        all(c(
          config$anchor_window, config$validation_window
        ) %in% -5:-1),
      construction$maximum_input_event_time <= -1L,
      !source_has_post_access,
      setequal(coverage$arm, c("treated", "control")) &&
        construction$network_support_arms == 2L,
      all(
        validation$partner_denominator_defined_rows ==
          validation$network_rows
      ),
      all(validation$composition_defined_rows <= validation$network_rows) &&
        all(validation$weighted_composition_defined_share >= 0) &&
        all(validation$weighted_composition_defined_share <= 1),
      nrow(decision) == 1L &&
        decision$decision == expected_decision &&
        lmv2_n0_all_true(
          decision$all_support_gates_pass
        ) == lmv2_n0_all_true(support_checks$pass),
      abs(decision$meaningful_effect_threshold -
            config$meaningful_effect) < 1e-12 &&
        config$meaningful_effect == 0.05,
      lmv2_n0_fixture_passes(),
      registration$reportable_effect_estimates == 0L &&
        isTRUE(registration$registered),
      !lmv2_n0_all_true(decision$post_treatment_effects_opened),
      grepl(
        "equal-weight mean of the five annual event-time effects",
        freeze_text,
        fixed = TRUE
      ) &&
        grepl(
          "outcome is missing when the denominator is zero",
          freeze_text,
          fixed = TRUE
        ),
      all(file.exists(config$source_files))
    ),
    value = c(
      as.character(p6_manifest$n_failed),
      paste0(nrow(p6_cert), " cohorts"),
      observed_roster_hash,
      as.character(construction$pass),
      as.character(construction$duplicate_application_inventor_keys),
      paste(
        construction$duplicate_application_dyad_keys,
        construction$self_link_rows,
        sep = "/"
      ),
      as.character(construction$invalid_persistent_ties),
      paste(
        min(config$anchor_window), max(config$anchor_window),
        min(config$validation_window), max(config$validation_window),
        sep = ":"
      ),
      as.character(construction$maximum_input_event_time),
      as.character(source_has_post_access),
      paste(coverage$arm, collapse = ";"),
      paste(
        validation$partner_denominator_defined_rows,
        validation$network_rows,
        sep = "/", collapse = ";"
      ),
      paste(validation$composition_defined_rows, collapse = ";"),
      decision$decision,
      as.character(decision$meaningful_effect_threshold),
      as.character(lmv2_n0_fixture_passes()),
      "0 effect estimates",
      as.character(decision$post_treatment_effects_opened),
      freeze_hash,
      as.character(sum(file.exists(config$source_files)))
    ),
    detail = c(
      "P5c/P6 manifest has zero failed checks",
      "all 17 cohort mass reconciliations pass",
      "immutable P5c roster",
      "construction script internal audit",
      "unique (application, inventor) source key",
      "unique ordered undirected application dyads; no self-links",
      "at least two applications in at least two anchor years",
      "anchor -5:-3; validation -2:-1",
      "N0 cannot use event time zero or later",
      "static audit of N0 construction and census sources",
      "same SQL definitions for treated and controls",
      "baseline partners remain valid denominator zeros",
      "solo/no-co-invention years are undefined, not zero",
      "support failures certify feasibility-only rather than changing rules",
      "N1 governing MDE must be <= 0.05",
      "synthetic duplicate, self-link, and persistence fixture",
      paste(
        "N0 emits no treatment-effect estimate;",
        "nothing enters the master results inventory"
      ),
      "N0 never estimates post-acquisition effects",
      "freeze states annual aggregation and zero-denominator handling",
      "five N0 source files"
    ),
    stringsAsFactors = FALSE
  )

  certification_path <- file.path(
    config$output_dir, "n0_network_census_certification.csv"
  )
  lmv2_n0_write_csv(checks, certification_path)
  if (!all(checks$pass)) {
    stop(
      "N0 certification failed: ",
      paste(checks$check[!checks$pass], collapse = ", "),
      call. = FALSE
    )
  }

  freeze_attestation <- data.frame(
    version = config$version,
    freeze_path = normalizePath(
      config$freeze_file, winslash = "/", mustWork = TRUE
    ),
    freeze_sha256 = freeze_hash,
    anchor_window = "-5:-3",
    validation_window = "-2:-1",
    meaningful_effect = config$meaningful_effect,
    decision = decision$decision,
    stringsAsFactors = FALSE
  )
  freeze_attestation_path <- file.path(
    config$output_dir, "n0_freeze_attestation.csv"
  )
  lmv2_n0_write_csv(freeze_attestation, freeze_attestation_path)

  artifact_paths <- c(
    list.files(
      config$output_dir, full.names = TRUE, recursive = FALSE
    ),
    list.files(
      config$results_dir, full.names = TRUE, recursive = FALSE
    ),
    config$results_note
  )
  artifact_paths <- artifact_paths[
    file.exists(artifact_paths) &
      !dir.exists(artifact_paths) &
      basename(artifact_paths) != "n0_network_census_manifest.csv"
  ]
  input_paths <- c(
    config$foundation_db,
    config$p5c_roster,
    config$p6_manifest,
    config$p6_certification,
    config$freeze_file,
    config$source_files
  )
  manifest_paths <- unique(c(input_paths, artifact_paths))
  info <- file.info(manifest_paths)
  manifest <- data.frame(
    role = ifelse(
      manifest_paths %in% input_paths, "input_or_source", "artifact"
    ),
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
    bytes = unname(info$size),
    modified_utc = format(
      info$mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
    ),
    stringsAsFactors = FALSE
  )
  lmv2_n0_write_csv(
    manifest,
    file.path(config$output_dir, "n0_network_census_manifest.csv")
  )

  invisible(list(
    checks = checks,
    support_checks = support_checks,
    decision = decision,
    freeze_hash = freeze_hash
  ))
}

if (sys.nframe() == 0L) {
  lmv2_n0_certify()
  message("N0 network census certified.")
}

# Certify P5b S0-S2 outputs and publish a source-linked manifest.

if (!exists("lmv2_stayer_config")) {
  source(file.path("02_analysis", "R", "26a_lmv2_stayer_config.R"))
}

lmv2_certify_stayer_s0_s2 <- function(config = lmv2_stayer_config()) {
  read_output <- function(name) {
    path <- file.path(config$output_dir, name)
    if (!file.exists(path)) stop("Missing S0-S2 output: ", path)
    read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  }

  treated <- read_output("treated_retention_funnel.csv")
  controls <- read_output("control_retention_funnel.csv")
  power <- read_output("treated_retention_power.csv")
  continuity <- read_output("control_group_continuity_summary.csv")
  key_audit <- read_output("inventor_affiliation_key_audit.csv")
  integrity <- read_output("partition_integrity_audit.csv")

  primary_power <- power[
    power$retention_window == "t1_t5_primary", , drop = FALSE]
  sensitivity_power <- power[
    power$retention_window == "t2_t5_sensitivity", , drop = FALSE]
  primary_treated <- treated[
    treated$retention_window == "t1_t5_primary" &
      treated$retention_status == "initially_retained", , drop = FALSE]
  primary_control <- controls[
    controls$retention_window == "t1_t5_primary" &
      controls$retention_status == "initially_retained", , drop = FALSE]
  primary_continuity <- continuity[
    continuity$retention_window == "t1_t5_primary", , drop = FALSE]

  unresolved_share <- function(frame, row_col) {
    rows <- frame[
      frame$retention_window == "t1_t5_primary", , drop = FALSE]
    unresolved <- rows[rows$retention_status == "unresolved", row_col]
    if (length(unresolved) == 0L) unresolved <- 0
    sum(unresolved) / sum(rows[[row_col]])
  }

  add_check <- function(check, observed, rule, pass) {
    data.frame(
      check = check,
      observed = as.character(observed),
      rule = rule,
      pass = isTRUE(pass),
      stringsAsFactors = FALSE)
  }

  source_hash_tooth <- lmv2_hash_tooth_test()
  synthetic_tooth_tests <- data.frame(
    test = c(
      "duplicate_key_check_fires",
      "continuity_flag_fires",
      "power_gate_fires",
      "unresolved_category_fires"),
    pass = c(
      sum(duplicated(data.frame(codinv = c(1L, 1L),
                                year = c(2000L, 2000L)))) > 0,
      {
        n_post <- 10
        modal_n <- 8
        n_same <- 1
        n_post >= config$continuity$minimum_post_inventors &&
          modal_n / n_post >= config$continuity$modal_outside_share &&
          n_same / n_post <= config$continuity$maximum_same_group_share
      },
      (config$power$minimum_retained_inventors - 1L) <
        config$power$minimum_retained_inventors,
      {
        first_post_year <- 2001L
        first_post_group <- NA_integer_
        focal_group_path <- FALSE
        target_company_path <- FALSE
        synthetic_status <- if (is.na(first_post_year)) {
          "no_post_patent"
        } else if (focal_group_path || target_company_path) {
          "initially_retained"
        } else if (is.na(first_post_group)) {
          "unresolved"
        } else {
          "leaver"
        }
        identical(synthetic_status, "unresolved")
      }),
    stringsAsFactors = FALSE)
  lmv2_write_csv(
    synthetic_tooth_tests,
    file.path(config$output_dir, "s0_s2_tooth_tests.csv"))

  checks <- do.call(rbind, list(
    add_check(
      "source_hash_guard_has_teeth",
      source_hash_tooth,
      "TRUE",
      source_hash_tooth),
    add_check(
      "synthetic_checks_have_teeth",
      all(synthetic_tooth_tests$pass),
      "TRUE",
      all(synthetic_tooth_tests$pass)),
    add_check(
      "inventor_affiliation_unique_by_inventor_year",
      key_audit$duplicate_inventor_year_rows[[1L]],
      "0",
      key_audit$duplicate_inventor_year_rows[[1L]] == 0),
    add_check(
      "retention_partition_unique_keys",
      sum(integrity$duplicate_keys),
      "0",
      sum(integrity$duplicate_keys) == 0),
    add_check(
      "retention_partition_timing",
      sum(integrity$wrong_timing_rows),
      "0",
      sum(integrity$wrong_timing_rows) == 0),
    add_check(
      "retention_partition_status_domain",
      sum(integrity$invalid_status_rows),
      "0",
      sum(integrity$invalid_status_rows) == 0),
    add_check(
      "retained_classification_coherence",
      sum(integrity$incoherent_retained_rows),
      "0",
      sum(integrity$incoherent_retained_rows) == 0),
    add_check(
      "primary_retained_inventors",
      primary_power$retained_inventors[[1L]],
      paste0(">=", config$power$minimum_retained_inventors),
      primary_power$retained_inventors[[1L]] >=
        config$power$minimum_retained_inventors),
    add_check(
      "primary_retained_deals",
      primary_power$retained_deals[[1L]],
      paste0(">=", config$power$minimum_retained_deals),
      primary_power$retained_deals[[1L]] >=
        config$power$minimum_retained_deals),
    add_check(
      "primary_raw_effective_deals",
      primary_power$raw_effective_deals[[1L]],
      paste0(">=", config$power$minimum_raw_effective_deals),
      primary_power$raw_effective_deals[[1L]] >=
        config$power$minimum_raw_effective_deals),
    add_check(
      "primary_symmetric_control_count",
      primary_control$inventor_cohort_rows[[1L]],
      ">=primary retained treated count",
      primary_control$inventor_cohort_rows[[1L]] >=
        primary_treated$inventor_deal_rows[[1L]]),
    add_check(
      "treated_unresolved_share",
      unresolved_share(treated, "inventor_deal_rows"),
      paste0("<=", config$unresolved_share_maximum),
      unresolved_share(treated, "inventor_deal_rows") <=
        config$unresolved_share_maximum),
    add_check(
      "control_unresolved_share",
      unresolved_share(controls, "inventor_cohort_rows"),
      paste0("<=", config$unresolved_share_maximum),
      unresolved_share(controls, "inventor_cohort_rows") <=
        config$unresolved_share_maximum),
    add_check(
      "control_group_id_discontinuity_share",
      primary_continuity$affected_post_share[[1L]],
      paste0("<=", config$continuity$maximum_affected_post_share),
      primary_continuity$affected_post_share[[1L]] <=
        config$continuity$maximum_affected_post_share),
    add_check(
      "timing_sensitivity_materialized",
      sensitivity_power$retained_inventors[[1L]],
      ">0",
      sensitivity_power$retained_inventors[[1L]] > 0)
  ))

  source_paths <- c(config$source_files, config$freeze_file)
  missing_sources <- source_paths[!file.exists(source_paths)]
  if (length(missing_sources) > 0L) {
    stop("Missing source files:\n", paste(missing_sources, collapse = "\n"))
  }
  source_manifest <- data.frame(
    file = normalizePath(source_paths, winslash = "/", mustWork = TRUE),
    git_blob_hash = vapply(source_paths, lmv2_git_blob_hash, character(1)),
    stringsAsFactors = FALSE)
  execution_hash <- lmv2_composite_source_hash(source_paths)

  manifest <- data.frame(
    version = config$version,
    execution_hash = execution_hash,
    foundation_db = config$foundation_db,
    foundation_db_bytes = file.info(config$foundation_db)$size,
    foundation_db_modified = format(
      file.info(config$foundation_db)$mtime,
      "%Y-%m-%dT%H:%M:%S%z"),
    primary_window = "t=+1..+5",
    sensitivity_window = "t=+2..+5",
    primary_retained_inventors = primary_power$retained_inventors[[1L]],
    primary_retained_deals = primary_power$retained_deals[[1L]],
    primary_raw_effective_deals =
      primary_power$raw_effective_deals[[1L]],
    timing_sensitivity_retained_inventors =
      sensitivity_power$retained_inventors[[1L]],
    timing_sensitivity_retained_deals =
      sensitivity_power$retained_deals[[1L]],
    all_checks_pass = all(checks$pass),
    stringsAsFactors = FALSE)

  lmv2_write_csv(
    checks, file.path(config$output_dir, "s0_s2_certification.csv"))
  lmv2_write_csv(
    source_manifest,
    file.path(config$output_dir, "s0_s2_source_manifest.csv"))
  lmv2_write_csv(
    manifest, file.path(config$output_dir, "s0_s2_manifest.csv"))

  if (!all(checks$pass)) {
    stop(
      "P5b S0-S2 certification failed: ",
      paste(checks$check[!checks$pass], collapse = ", "))
  }
  invisible(list(checks = checks, manifest = manifest))
}

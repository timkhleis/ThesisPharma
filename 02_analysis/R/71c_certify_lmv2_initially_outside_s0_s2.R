# Certify the outcome-blind initially-outside classification package.

if (!exists("lmv2_io_config")) {
  source(file.path("02_analysis", "R",
                   "71a_lmv2_initially_outside_config.R"))
}

lmv2_certify_initially_outside_s0_s2 <- function(config = lmv2_io_config()) {
  read_out <- function(name) {
    path <- file.path(config$s0_dir, name)
    if (!file.exists(path)) stop("Missing S0-S2 artifact: ", path)
    read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  }
  integrity <- read_out("classification_integrity.csv")
  nesting <- read_out("p5c_nesting_audit.csv")
  rates <- read_out("selection_rates.csv")
  timing <- read_out("first_post_timing.csv")
  placeholder <- read_out("placeholder_target_only_audit.csv")
  existence <- read_out("group_existence_audit.csv")
  coverage <- read_out("calendar_coverage.csv")

  primary <- nesting[
    nesting$support_variant == "primary_initially_outside_t1_t5", ]
  treated_primary <- primary[primary$arm == "treated", ]
  control_primary <- primary[primary$arm == "control", ]

  checks <- data.frame(
    check = c(
      "partition_keys_unique",
      "first_post_timing_valid",
      "status_flags_coherent",
      "all_approved_variants_present",
      "all_cohorts_present_in_primary_treated",
      "all_cohorts_present_in_primary_control",
      "primary_nested_treated_nonempty",
      "primary_nested_control_nonempty",
      "selection_rates_bounded",
      "timing_audit_nonempty",
      "group_existence_audit_complete",
      "calendar_coverage_complete",
      "placeholder_audit_present"),
    pass = c(
      all(integrity$n_rows == integrity$distinct_keys),
      all(integrity$wrong_timing == 0),
      all(integrity$incoherent_status == 0),
      all(config$support_variants %in% nesting$support_variant),
      identical(sort(unique(treated_primary$cohort)), config$cohorts),
      identical(sort(unique(control_primary$cohort)), config$cohorts),
      sum(treated_primary$nested_rows) > 0,
      sum(control_primary$nested_rows) > 0,
      all(rates$selection_rate >= 0 & rates$selection_rate <= 1),
      nrow(timing) > 0,
      nrow(existence) == 3L * length(config$cohorts) * 11L,
      nrow(coverage) == length(config$cohorts) * 11L,
      nrow(placeholder) == 1L),
    detail = c(
      paste(integrity$arm, integrity$n_rows, sep = "=", collapse = "; "),
      paste("wrong timing rows", sum(integrity$wrong_timing)),
      paste("incoherent rows", sum(integrity$incoherent_status)),
      paste(sort(unique(nesting$support_variant)), collapse = "; "),
      paste(sort(unique(treated_primary$cohort)), collapse = ";"),
      paste(sort(unique(control_primary$cohort)), collapse = ";"),
      paste("nested treated rows", sum(treated_primary$nested_rows)),
      paste("nested control rows", sum(control_primary$nested_rows)),
      paste("rate range", paste(range(rates$selection_rate), collapse = "--")),
      paste("timing rows", nrow(timing)),
      paste("existence rows", nrow(existence)),
      paste("coverage rows", nrow(coverage)),
      paste("placeholder deals", placeholder$placeholder_deals)),
    stringsAsFactors = FALSE)

  lmv2_io_write_csv(checks, file.path(config$s0_dir, "s0_s2_certification.csv"))

  source_paths <- c(config$foundation_db, config$p5c_diagnostics,
                    config$plan_files,
                    file.path(config$base, "02_analysis", "R",
                              c("71a_lmv2_initially_outside_config.R",
                                "71b_build_lmv2_initially_outside_s0_s2.R",
                                "71c_certify_lmv2_initially_outside_s0_s2.R",
                                "71_run_lmv2_initially_outside_s0_s2.R")))
  source_paths <- source_paths[file.exists(source_paths)]
  manifest <- data.frame(
    path = normalizePath(source_paths, winslash = "/", mustWork = TRUE),
    sha256 = vapply(source_paths, lmv2_io_sha256, character(1)),
    stringsAsFactors = FALSE)
  lmv2_io_write_csv(manifest, file.path(config$s0_dir, "s0_s2_manifest.csv"))

  if (!all(checks$pass)) {
    failed <- checks$check[!checks$pass]
    stop("S0-S2 certification failed: ", paste(failed, collapse = ", "))
  }
  invisible(checks)
}

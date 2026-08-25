# ============================================================================
# 36a_lmv2_exit_decomposition_config.R
# Additive configuration for the patenting-exit accounting decomposition.
# ============================================================================

LMV2_EXIT_DECOMP_VERSION <- "lmv2_exit_decomposition_1993_amendment_v1"

lmv2_exit_existing_path <- function(candidates, label) {
  candidates <- unique(candidates[nzchar(candidates)])
  hits <- candidates[file.exists(candidates) | dir.exists(candidates)]
  if (!length(hits)) {
    stop(
      "Could not locate ", label, ". Checked:\n",
      paste(" -", candidates, collapse = "\n"))
  }
  normalizePath(hits[[1L]], winslash = "/", mustWork = TRUE)
}

lmv2_exit_config <- function(base = getwd(), output_dir = NULL) {
  base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  project_root <- normalizePath(
    file.path(base, "..", ".."), winslash = "/", mustWork = TRUE)
  audit_root <- file.path(
    base, "02_analysis", "output", "audit", "local_match_v2_1993_amendment")
  p6_panel_dir <- file.path(
    audit_root, "P6_P5C_COUNT_ACTIVE", "panel_matched")
  s3_dir <- file.path(audit_root, "P5B_STAYER_S3")
  s4_dir <- file.path(audit_root, "P5B_STAYER_S4_RESULTS")
  derived_dir <- lmv2_exit_existing_path(
    c(
      file.path(project_root, "02_analysis", "output", "parquet", "derived"),
      file.path(base, "02_analysis", "output", "parquet", "derived")
    ),
    "the derived Parquet layer")
  canonical_dir <- lmv2_exit_existing_path(
    c(
      file.path(project_root, "02_analysis", "output", "parquet", "canonical"),
      file.path(base, "02_analysis", "output", "parquet", "canonical")
    ),
    "the canonical Parquet layer")
  helper_dir <- lmv2_exit_existing_path(
    c(
      file.path(project_root, "02_analysis", "output", "parquet", "helper"),
      file.path(base, "02_analysis", "output", "parquet", "helper")
    ),
    "the helper Parquet layer")
  if (is.null(output_dir)) {
    output_dir <- file.path(audit_root, "P8_EXIT_DECOMPOSITION")
  }

  list(
    version = LMV2_EXIT_DECOMP_VERSION,
    base = base,
    project_root = project_root,
    output_dir = output_dir,
    panel_dir = p6_panel_dir,
    p6_manifest = file.path(
      audit_root, "P6_P5C_COUNT_ACTIVE", "p6_manifest.csv"),
    certified_p6_headline = file.path(
      audit_root, "P6_ESTIMATION_PRIMARY",
      "p6_headline_post_att.csv"),
    s3_weights = file.path(s3_dir, "s3_production_weights.parquet"),
    s3_certification = file.path(s3_dir, "s3_certification.csv"),
    s4_manifest = file.path(s4_dir, "s4_manifest.csv"),
    inventor_year = file.path(derived_dir, "inventor_year.parquet"),
    patent_inventor_enriched = file.path(
      derived_dir, "patent_inventor_enriched.parquet"),
    inventor_affiliation = file.path(
      derived_dir, "inventor_affiliation_own.parquet"),
    patent_company_link = file.path(
      derived_dir, "patent_company_link.parquet"),
    patent_inventor = file.path(canonical_dir, "patent_inventor.parquet"),
    deal_target_company = file.path(
      helper_dir, "deal_target_company_strict.parquet"),
    endpoint_path = file.path(output_dir, "global_career_endpoints.parquet"),
    observation_end_year = 2015L,
    event_window = -5:5,
    reference_event_time = -1L,
    samples = list(
      headline_1993_2010 = list(
        cohorts = 1993:2010, post_window = 1:5,
        censoring_label = "primary_same_sample_right_edge_sensitive"),
      strict_1993_2005 = list(
        cohorts = 1993:2005, post_window = 1:5,
        censoring_label = "five_year_endpoint_buffer"),
      headline_1993_2010_t1_t3 = list(
        cohorts = 1993:2010, post_window = 1:3,
        censoring_label = "same_cohort_two_year_endpoint_buffer")
    ),
    primary_sample = "headline_1993_2010",
    primary_stayer_spec = "primary_count_active_scale",
    primary_stayer_support = "primary_resolved_t1",
    fixed_lookahead_years = 3L,
    active_ess_floor = 20,
    bootstrap = list(
      production = 9999L,
      smoke = 199L,
      seed = 20260722L),
    execution = list(threads = 8L, memory_limit = "6GB"),
    freeze_file = file.path(
      base, "02_analysis", "notes",
      "local_match_v2_patenting_exit_decomposition_freeze.md"),
    source_files = file.path(
      base, "02_analysis", "R",
      c(
        "36a_lmv2_exit_decomposition_config.R",
        "36b_build_lmv2_global_career_endpoints.R",
        "final_thesis/36c_estimate_lmv2_exit_decomposition.R",
        "36d_report_certify_lmv2_exit_decomposition.R",
        "36_run_lmv2_exit_decomposition.R"
      ))
  )
}

lmv2_exit_sql_string <- function(x) {
  paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
}

lmv2_exit_panel_files <- function(config) {
  files <- sort(list.files(
    config$panel_dir,
    pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
    full.names = TRUE))
  expected <- length(unique(unlist(lapply(
    config$samples, function(x) x$cohorts
  ))))
  if (length(files) != expected) {
    stop("P6 panel shard count does not match the amended cohort set")
  }
  normalizePath(files, winslash = "/", mustWork = TRUE)
}

lmv2_exit_panel_sql <- function(files) {
  paste0(
    "read_parquet([",
    paste(vapply(files, lmv2_exit_sql_string, character(1)), collapse = ","),
    "])"
  )
}

lmv2_exit_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
  invisible(path)
}

lmv2_exit_sha256 <- function(path) {
  digest::digest(
    path, algo = "sha256", file = TRUE, serialize = FALSE)
}

lmv2_exit_execution_hash <- function(config) {
  inputs <- c(
    config$freeze_file, config$p6_manifest, config$s3_weights,
    config$s3_certification, config$inventor_year,
    config$patent_inventor_enriched, config$source_files)
  inputs <- inputs[file.exists(inputs)]
  digest::digest(
    list(
      version = config$version,
      observation_end_year = config$observation_end_year,
      samples = config$samples,
      input_sha256 = setNames(
        vapply(inputs, lmv2_exit_sha256, character(1)),
        normalizePath(inputs, winslash = "/", mustWork = TRUE))
    ),
    algo = "sha256", serialize = TRUE)
}

lmv2_exit_s4_headline_path <- function(config) {
  if (!file.exists(config$s4_manifest)) return(NA_character_)
  manifest <- utils::read.csv(
    config$s4_manifest, stringsAsFactors = FALSE)
  hit <- manifest[
    manifest$artifact == "s4_headline_post_att.csv", , drop = FALSE]
  if (nrow(hit) != 1L || !file.exists(hit$path[[1L]])) {
    return(NA_character_)
  }
  if ("sha256" %in% names(hit) &&
      !identical(lmv2_exit_sha256(hit$path[[1L]]), hit$sha256[[1L]])) {
    stop("Certified S4 headline file does not match its manifest")
  }
  normalizePath(hit$path[[1L]], winslash = "/", mustWork = TRUE)
}

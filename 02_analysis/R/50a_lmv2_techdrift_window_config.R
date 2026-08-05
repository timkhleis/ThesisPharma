# Frozen configuration for the pooled-window TechDrift amendment.

if (!exists("lmv2_p5b_s4_config")) {
  source(file.path("02_analysis", "R", "28a_lmv2_p5b_s4_config.R"))
}

LMV2_TECHDRIFT_WINDOW_VERSION <-
  "lmv2_techdrift_window_1993_amendment_v1"

lmv2_techdrift_window_config <- function(base = getwd()) {
  base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  stayer <- lmv2_p5b_s4_config(base)
  audit_root <- file.path(
    base, "02_analysis", "output", "audit",
    "local_match_v2_1993_amendment")
  p6_dir <- file.path(audit_root, "P6_P5C_COUNT_ACTIVE")
  output_dir <- file.path(
    audit_root, "P5B_TECHDRIFT_WINDOWED_AMENDMENT")

  list(
    version = LMV2_TECHDRIFT_WINDOW_VERSION,
    base = base,
    p6_root = stayer$p6_root,
    foundation_db = file.path(
      stayer$p6_root, "02_analysis", "output",
      "thesis_foundation.duckdb"),
    panel_dir = file.path(p6_dir, "panel_matched"),
    panel_manifest = file.path(p6_dir, "p6_manifest.csv"),
    weights = stayer$s3_weights,
    weights_manifest = stayer$s3_manifest,
    weights_certification = stayer$s3_certification,
    primary_spec = "primary_count_active_scale",
    analysis_population = "frozen_initially_retained_inventor_design",
    outcome_defined_population =
      "nonempty_classified_ipc4_vectors_in_both_comparison_windows",
    cohorts = 1993:2010,
    main_pair = "recent5_post5",
    pair_definitions = data.frame(
      pair_name = c(
        "recent5_post5", "fullstock_post5",
        "recent5_post2", "recent5_post3_5",
        "pre10_6_pre5"),
      left_window = c(
        "recent_pre5", "full_pre", "recent_pre5",
        "recent_pre5", "early_pre5"),
      right_window = c(
        "post5", "post5", "post2", "post3_5",
        "recent_pre5"),
      stringsAsFactors = FALSE),
    specifications = data.frame(
      specification = c(
        "pooled_recent5_main", "pooled_fullstock_sensitivity",
        "pooled_recent5_binary_sensitivity",
        "pooled_early_post", "pooled_late_post",
        "pooled_recent5_exclude_2010", "restricted_prepre_placebo"),
      pair_name = c(
        "recent5_post5", "fullstock_post5", "recent5_post5",
        "recent5_post2",
        "recent5_post3_5", "recent5_post5", "pre10_6_pre5"),
      weight_scheme = c(
        "patent_count", "patent_count", "binary_presence",
        "patent_count", "patent_count", "patent_count", "patent_count"),
      cohort_min = c(
        1993L, 1993L, 1993L, 1993L, 1993L, 1993L, 1998L),
      cohort_max = c(
        2010L, 2010L, 2010L, 2010L, 2010L, 2009L, 2010L),
      role = c(
        "amended_main", "baseline_sensitivity",
        "vector_weight_sensitivity", "coarse_dynamic",
        "coarse_dynamic", "late_tail_sensitivity",
        "restricted_diagnostic"),
      stringsAsFactors = FALSE),
    event_windows = list(
      recent_pre5 = -5:-1,
      full_pre_max = -1L,
      post5 = 1:5,
      post2 = 1:2,
      post3_5 = 3:5,
      early_pre5 = -10:-6),
    pre_placebo_min_cohort = 1998L,
    bootstrap_replications = 9999L,
    seed = 20260804L,
    main_min_weight_coverage = 0.95,
    output_dir = output_dir,
    amendment_note = file.path(
      base, "02_analysis", "notes",
      "local_match_v2_techdrift_window_amendment.md"),
    legacy_stayer_headline = file.path(
      audit_root, "P5B_STAYER_S6_SECONDARY_OUTCOMES",
      "s6_secondary_headline.csv"),
    legacy_full_headline = file.path(
      audit_root, "P6_ESTIMATION_PRIMARY",
      "p6_headline_post_att.csv"),
    source_files = file.path(
      base, "02_analysis", "R",
      c(
        "50a_lmv2_techdrift_window_config.R",
        "50b_run_lmv2_techdrift_window.R",
        "50c_certify_lmv2_techdrift_window.R",
        "50d_report_lmv2_techdrift_window.R"))
  )
}

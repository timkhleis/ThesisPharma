# Frozen P5b S4 initially-retained outcome-estimation configuration.

if (!exists("lmv2_p5b_s3_config")) {
  source(file.path("02_analysis", "R", "27a_lmv2_p5b_s3_config.R"))
}

LMV2_P5B_S4_VERSION <- "lmv2_p5b_stayer_s4_1993_amendment_v1"

lmv2_p5b_s4_config <- function(base = getwd()) {
  base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  s3 <- lmv2_p5b_s3_config(base)
  user_root <- Sys.getenv("USERPROFILE")
  p6_root <- lmv2_stayer_existing_path(
    c(
      base,
      Sys.getenv("LMV2_P6_ROOT"),
      file.path(user_root, "Documents", "Thesis", ".worktrees",
                "lmv2-p6-outcomes")
    ),
    "the authoritative P6 outcomes worktree")
  p6_audit <- file.path(
    p6_root, "02_analysis", "output", "audit",
    "local_match_v2_1993_amendment")
  output_dir <- file.path(
    base, "02_analysis", "output", "audit",
    "local_match_v2_1993_amendment",
    "P5B_STAYER_S4_RESULTS")

  list(
    version = LMV2_P5B_S4_VERSION,
    base = base,
    p6_root = p6_root,
    p6_r_dir = file.path(p6_root, "02_analysis", "R"),
    base_panel_dir = file.path(
      p6_audit, "P6_P5C_COUNT_ACTIVE", "panel_matched"),
    base_p6_manifest = file.path(
      p6_audit, "P6_P5C_COUNT_ACTIVE", "p6_manifest.csv"),
    s3 = s3,
    s3_weights = file.path(
      s3$output_dir, "s3_production_weights.parquet"),
    s3_manifest = file.path(s3$output_dir, "s3_manifest.csv"),
    s3_certification = file.path(
      s3$output_dir, "s3_certification.csv"),
    output_dir = output_dir,
    production_specs = s3$production_specs,
    samples = list(
      full_1993_2010 = 1993:2010
    ),
    outcomes = c("patent_count", "active_patenting"),
    event_window = -5:5,
    reference_event_time = -1L,
    pretrend_window = -5:-2,
    post_window = 1:5,
    bootstrap_replications = 9999L,
    bootstrap_seed = 20260722L,
    freeze_file = file.path(
      base, "02_analysis", "notes",
      "local_match_v2_p5b_s4_estimation_freeze.md"),
    source_files = file.path(
      base, "02_analysis", "R",
      c(
        "28a_lmv2_p5b_s4_config.R",
        "28b_run_lmv2_p5b_s4_estimation.R",
        "28c_certify_lmv2_p5b_s4_results.R"
      )),
    external_core_files = file.path(
      p6_root, "02_analysis", "R",
      c(
        "15a_lmv2_design_lock.R",
        "18a_lmv2_outcome_config.R",
        "19a_lmv2_p6_estimation_config.R",
        "19b_lmv2_p6_estimation_core.R"
      ))
  )
}

lmv2_p5b_s4_hash <- function(config = lmv2_p5b_s4_config()) {
  digest::digest(
    list(
      version = config$version,
      freeze_sha256 = digest::digest(
        config$freeze_file, algo = "sha256", file = TRUE,
        serialize = FALSE),
      production_specs = config$production_specs,
      samples = config$samples,
      outcomes = config$outcomes,
      event_window = config$event_window,
      reference_event_time = config$reference_event_time,
      pretrend_window = config$pretrend_window,
      post_window = config$post_window,
      bootstrap_replications = config$bootstrap_replications,
      bootstrap_seed = config$bootstrap_seed,
      source_sha256 = vapply(
        c(config$source_files, config$external_core_files),
        digest::digest, character(1),
        algo = "sha256", file = TRUE, serialize = FALSE)
    ),
    algo = "sha256", serialize = TRUE)
}

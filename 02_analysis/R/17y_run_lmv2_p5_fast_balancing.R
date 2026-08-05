# ============================================================================
# Restartable P5 balancing runner using the sparse technology-cache join.
# ============================================================================
# This is intentionally additive. It does not modify or reuse the P4 run
# directory, so the currently running pilot and all of its checkpoints remain
# valid. Use a distinct --audit-dir for P5.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, required = TRUE) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) {
    if (required) stop("Missing --", name, "=...")
    return(NA_character_)
  }
  sub(paste0("^--", name, "="), "", hit[[1]])
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)

# 17o's own CLI is guarded by --mode=. P5 deliberately uses --p5-mode= so
# sourcing it defines the certified pipeline without starting the P4 CLI.
if (any(startsWith(args, "--mode="))) {
  stop("Use --p5-mode=production|certify, not --mode=, with the P5 runner")
}
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
source(file.path(BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R"))
lmv2_install_p5_sparse_cache()

mode <- read_arg("p5-mode")
if (identical(mode, "certify")) {
  source(file.path(BASE, "R", "17z_certify_lmv2_p5_sparse_cache.R"),
         local = new.env())
} else if (identical(mode, "production")) {
  db_path <- read_arg("db")
  audit_dir <- read_arg("audit-dir")
  p3_manifest_path <- read_arg("p3-manifest")
  cohort_text <- read_arg("cohorts")
  cohorts_to_run <- as.integer(strsplit(cohort_text, ",", fixed = TRUE)[[1]])
  if (!length(cohorts_to_run) || anyNA(cohorts_to_run)) {
    stop("--cohorts= must be a comma-separated list of integer cohort years")
  }

  # The sparse disk-backed path is both the fast path and the bounded-memory
  # path. Route every requested production cohort through it.
  COHORTS <- cohorts_to_run
  LMV2_DISKBACKED_COHORTS <- cohorts_to_run
  dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
  p3_hash <- lmv2_p3_file_hash(p3_manifest_path)
  p5_manifest <- data.frame(
    timestamp = as.character(Sys.time()),
    sparse_cache_version = LMV2_P5_SPARSE_CACHE_VERSION,
    sparse_cache_hash = lmv2_p3_file_hash(
      file.path(BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R")),
    p5_runner_hash = lmv2_p3_file_hash(
      file.path(BASE, "R", "17y_run_lmv2_p5_fast_balancing.R")),
    execution_hash = lmv2_p5_sparse_execution_hash(BASE, p3_hash),
    cohorts = paste(cohorts_to_run, collapse = ";"),
    disk_backed_all_cohorts = TRUE,
    duckdb_threads = 2L,
    duckdb_memory_limit = "6GB",
    stringsAsFactors = FALSE)
  utils::write.csv(
    p5_manifest, file.path(audit_dir, "p5_acceleration_manifest.csv"),
    row.names = FALSE)
  run_cohort_hybrid_pilot(
    db_path, audit_dir, p3_manifest_path,
    cohorts_to_run = cohorts_to_run)
} else {
  stop("Unknown --p5-mode=", mode, "; expected production or certify")
}

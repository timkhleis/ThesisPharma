# ============================================================================
# 19c_run_lmv2_p6_estimation.R -- certified P6 full-cohort outcome runner
# ============================================================================
# Usage:
# Rscript 02_analysis/R/19c_run_lmv2_p6_estimation.R
#   --panel-dir=<certified P6 panel_matched directory>
#   --p6-manifest=<certified P6 p6_manifest.csv>
#   --output-dir=<new estimation output directory>
#   [--outcomes=patent_count,active_patenting,...]
#   [--smoke]
#
# --smoke uses 199 bootstrap draws and writes a non-production manifest.
# Production always uses the frozen 9,999 draws.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}

PANEL_DIR <- get_arg("--panel-dir")
P6_MANIFEST <- get_arg("--p6-manifest")
OUTPUT_DIR <- get_arg("--output-dir")
OUTCOME_ARG <- get_arg("--outcomes")
SMOKE <- "--smoke" %in% args

if (any(is.na(c(PANEL_DIR, P6_MANIFEST, OUTPUT_DIR)))) {
  stop("19c requires explicit --panel-dir=, --p6-manifest=, --output-dir=")
}
if (!dir.exists(PANEL_DIR)) stop("Panel directory not found: ", PANEL_DIR)
if (!file.exists(P6_MANIFEST)) stop("P6 manifest not found: ", P6_MANIFEST)
if (dir.exists(OUTPUT_DIR) && length(list.files(OUTPUT_DIR, all.files = TRUE,
                                               no.. = TRUE))) {
  stop("Output directory must be new or empty: ", OUTPUT_DIR)
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
required <- c(
  "DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng"
)
for (pkg in required) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

if (!identical(
  as.character(utils::packageVersion("fwildclusterboot")),
  LMV2_P6_ESTIMATION$inference$package_version
)) {
  stop("fwildclusterboot version differs from the frozen version")
}

outcomes <- if (is.na(OUTCOME_ARG)) {
  LMV2_P6_ESTIMATION$core_outcomes
} else {
  trimws(strsplit(OUTCOME_ARG, ",", fixed = TRUE)[[1]])
}
if (!length(outcomes) ||
    !all(outcomes %in% LMV2_P6_ESTIMATION$outcomes$outcome)) {
  stop("Requested outcome set is empty or contains an unfrozen outcome")
}
samples <- if (SMOKE) {
  list(smoke_1993_1995 = 1993:1995)
} else {
  LMV2_P6_ESTIMATION$samples
}
bootstrap_reps <- if (SMOKE) 199L else
  LMV2_P6_ESTIMATION$inference$replications

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
stamp_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+_stamp\\.csv$",
  full.names = TRUE
))

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) {
  utils::write.csv(
    x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = ""
  )
}

t0 <- Sys.time()
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'",
  LMV2_P6_ESTIMATION$execution$duckdb_memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA threads=%d", LMV2_P6_ESTIMATION$execution$threads
))
temp_dir <- file.path(OUTPUT_DIR, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(temp_dir)
))

input_checks <- lmv2_validate_estimation_inputs(
  con, panel_files, stamp_files, P6_MANIFEST
)
write_csv(input_checks, "p6_estimation_input_certification.csv")
panel_sql <- lmv2_panel_sql(panel_files)

dynamic_all <- list()
pretrend_all <- list()
headline_all <- list()
coverage_all <- list()
progress <- list()
index <- 0L

for (sample_id in names(samples)) {
  cohorts <- samples[[sample_id]]
  deal_counts <- lmv2_design_deal_counts(con, panel_sql, cohorts)
  for (outcome in outcomes) {
    index <- index + 1L
    message(sprintf(
      "[%d/%d] %s | %s",
      index, length(samples) * length(outcomes), sample_id, outcome
    ))
    step_start <- Sys.time()
    fitted <- lmv2_fit_outcome(
      con, panel_sql, outcome, sample_id, cohorts,
      bootstrap_reps, deal_counts
    )
    dynamic_all[[index]] <- fitted$dynamic
    pretrend_all[[index]] <- fitted$pretrend
    headline_all[[index]] <- fitted$headline
    coverage_all[[index]] <- fitted$coverage
    progress[[index]] <- data.frame(
      sample = sample_id,
      outcome = outcome,
      min_pair_weight_coverage =
        min(fitted$coverage$pair_weight_coverage),
      runtime_minutes = as.numeric(
        difftime(Sys.time(), step_start, units = "mins")
      ),
      stringsAsFactors = FALSE
    )
    write_csv(do.call(rbind, progress), "p6_estimation_progress.csv")
    rm(fitted)
    gc()
  }
}

dynamic <- do.call(rbind, dynamic_all)
pretrend <- do.call(rbind, pretrend_all)
headline <- do.call(rbind, headline_all)
coverage <- do.call(rbind, coverage_all)
progress <- do.call(rbind, progress)

write_csv(dynamic, "p6_event_study_dynamic.csv")
write_csv(pretrend, "p6_joint_pretrend_tests.csv")
write_csv(headline, "p6_headline_post_att.csv")
write_csv(coverage, "p6_outcome_pair_coverage.csv")
write_csv(progress, "p6_estimation_progress.csv")

source_files <- file.path(BASE, "R", c(
  "18a_lmv2_outcome_config.R",
  "19a_lmv2_p6_estimation_config.R",
  "19b_lmv2_p6_estimation_core.R",
  "19c_run_lmv2_p6_estimation.R"
))
source_hashes <- vapply(
  source_files, digest::digest, character(1),
  file = TRUE, algo = "sha256"
)
manifest <- data.frame(
  estimation_version = LMV2_P6_ESTIMATION_VERSION,
  run_mode = if (SMOKE) "smoke_nonproduction" else "production",
  estimation_hash = lmv2_p6_estimation_hash(),
  construction_design_hash = lmv2_p6_design_hash(),
  preanalysis_freeze_sha256 = LMV2_P6_PREANALYSIS_FREEZE_SHA256,
  construction_manifest_sha256 =
    digest::digest(file = P6_MANIFEST, algo = "sha256"),
  panel_bundle_sha256 =
    digest::digest(vapply(panel_files, tools::md5sum, character(1)),
                   algo = "sha256", serialize = TRUE),
  source_bundle_sha256 =
    digest::digest(source_hashes, algo = "sha256", serialize = TRUE),
  outcomes = paste(outcomes, collapse = ";"),
  samples = paste(names(samples), collapse = ";"),
  bootstrap_replications = bootstrap_reps,
  n_input_checks = ncol(input_checks) - 1L,
  input_certification_pass = isTRUE(input_checks$pass[[1]]),
  stayer_att_authorized = FALSE,
  runtime_minutes = as.numeric(difftime(Sys.time(), t0, units = "mins")),
  stringsAsFactors = FALSE
)
write_csv(manifest, "p6_estimation_manifest.csv")

message(sprintf(
  "P6 %s estimation complete: %d outcomes x %d samples in %.2f minutes",
  manifest$run_mode, length(outcomes), length(samples),
  manifest$runtime_minutes
))

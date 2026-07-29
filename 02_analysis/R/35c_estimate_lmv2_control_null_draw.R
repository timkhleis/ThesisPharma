# ============================================================================
# Estimate one control-null draw with the certified P6 estimator
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit[[1]])
}
panel_dir <- normalizePath(
  arg("panel-dir"), winslash = "/", mustWork = TRUE)
panel_manifest_path <- normalizePath(
  arg("panel-manifest"), winslash = "/", mustWork = TRUE)
output_dir <- arg("output-dir")

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (package in c(
    "DBI", "duckdb", "digest", "fixest",
    "fwildclusterboot", "dqrng")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Missing package: ", package)
  }
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
source(file.path(BASE, "R", "35a_lmv2_control_null_config.R"))

manifest <- utils::read.csv(
  panel_manifest_path, stringsAsFactors = FALSE)
if (nrow(manifest) != 1L ||
    !isTRUE(as.logical(manifest$certification_pass))) {
  stop("Control-null panel manifest is absent or uncertified")
}
cohorts <- as.integer(strsplit(
  manifest$analysis_cohorts, ";", fixed = TRUE)[[1]])
panel_files <- file.path(
  panel_dir,
  sprintf("lmv2_event_panel_c%d.parquet", cohorts))
if (any(!file.exists(panel_files))) {
  stop("Control-null panel is missing one or more cohort shards")
}
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=2")
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
tmp_dir <- file.path(output_dir, "duckdb_tmp")
dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s",
  DBI::dbQuoteString(con, normalizePath(
    tmp_dir, winslash = "/", mustWork = TRUE))))

panel_sql <- lmv2_panel_sql(panel_files)
deal_counts <- lmv2_design_deal_counts(
  con, panel_sql, cohorts)
started <- Sys.time()
fit <- lmv2_fit_outcome(
  con = con,
  panel_sql = panel_sql,
  outcome = LMV2_CONTROL_NULL_P6$outcome,
  sample_id = manifest$sample_id,
  cohorts = cohorts,
  bootstrap_reps =
    LMV2_CONTROL_NULL_P6$bootstrap_replications,
  design_deal_counts = deal_counts)
for (nm in c("dynamic", "pretrend", "headline", "coverage")) {
  fit[[nm]]$assignment_arm <- manifest$assignment_arm
  fit[[nm]]$predicted_placebo_sign <-
    manifest$predicted_placebo_sign
  fit[[nm]]$treated_inventor_count_ratio <-
    manifest$treated_inventor_count_ratio
  fit[[nm]]$supported_treated_inventor_count_ratio <-
    manifest$supported_treated_inventor_count_ratio
  fit[[nm]]$nominal_treated_firms <-
    manifest$nominal_treated_firms
  fit[[nm]]$nominal_treated_firm_ratio <-
    manifest$nominal_treated_firm_ratio
  fit[[nm]]$effective_treated_firms <-
    manifest$effective_treated_firms
  fit[[nm]]$max_treated_firm_weight_share <-
    manifest$max_treated_firm_weight_share
  fit[[nm]]$effective_treated_firm_ratio <-
    manifest$effective_treated_firm_ratio
  utils::write.csv(
    fit[[nm]],
    file.path(output_dir, paste0("control_null_", nm, ".csv")),
    row.names = FALSE, na = "")
}
utils::write.csv(
  data.frame(
    version = LMV2_CONTROL_NULL_P6_VERSION,
    draw_id = manifest$draw_id,
    assignment_arm = manifest$assignment_arm,
    analysis_cohorts = manifest$analysis_cohorts,
    sample_id = manifest$sample_id,
    predicted_placebo_sign =
      manifest$predicted_placebo_sign,
    treated_inventor_count_ratio =
      manifest$treated_inventor_count_ratio,
    supported_treated_inventor_count_ratio =
      manifest$supported_treated_inventor_count_ratio,
    nominal_treated_firms =
      manifest$nominal_treated_firms,
    nominal_treated_firm_ratio =
      manifest$nominal_treated_firm_ratio,
    effective_treated_firms =
      manifest$effective_treated_firms,
    max_treated_firm_weight_share =
      manifest$max_treated_firm_weight_share,
    effective_treated_firm_ratio =
      manifest$effective_treated_firm_ratio,
    panel_manifest_sha256 = digest::digest(
      file = panel_manifest_path, algo = "sha256"),
    bootstrap_replications =
      LMV2_CONTROL_NULL_P6$bootstrap_replications,
    elapsed_seconds = as.numeric(
      difftime(Sys.time(), started, units = "secs")),
    status = "complete",
    stringsAsFactors = FALSE),
  file.path(output_dir, "control_null_estimation_manifest.csv"),
  row.names = FALSE)

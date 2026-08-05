# ============================================================================
# 36_run_lmv2_exit_decomposition.R
# Restartable runner for the additive P8 full-cohort package.
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
smoke <- "--smoke" %in% args
production <- "--production" %in% args
if (smoke == production) {
  stop("Specify exactly one of --smoke or --production")
}
source(file.path(
  "02_analysis", "R", "36a_lmv2_exit_decomposition_config.R"))
output_arg <- sub(
  "^--output-dir=", "", grep(
    "^--output-dir=", args, value = TRUE))
default_output <- file.path(
  "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
  if (smoke) "P8_EXIT_DECOMPOSITION_SMOKE" else "P8_EXIT_DECOMPOSITION")
output_dir <- if (length(output_arg)) output_arg[[1L]] else default_output
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(
  output_dir, winslash = "/", mustWork = TRUE)
rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

run_stage <- function(script) {
  stage <- sub("\\.R$", "", script)
  log <- file.path(output_dir, paste0(stage, ".log"))
  child_args <- c(
    file.path("02_analysis", "R", script),
    if (smoke) "--smoke" else "--production",
    paste0("--output-dir=", output_dir))
  status <- system2(
    rscript, child_args, stdout = log, stderr = log)
  if (!identical(status, 0L)) {
    stop(script, " failed; see ", log)
  }
  message("Completed ", script)
}

run_stage("36b_build_lmv2_global_career_endpoints.R")
run_stage("36c_estimate_lmv2_exit_decomposition.R")
run_stage("36d_report_certify_lmv2_exit_decomposition.R")

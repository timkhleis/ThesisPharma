args <- commandArgs(trailingOnly = TRUE)
smoke <- "--smoke" %in% args
production <- "--production" %in% args
if (smoke == production) {
  stop("Specify exactly one of --smoke or --production")
}
output_arg <- sub(
  "^--output-dir=", "", grep("^--output-dir=", args, value = TRUE))
parent_arg <- sub(
  "^--parent-exit-dir=", "",
  grep("^--parent-exit-dir=", args, value = TRUE))
output_dir <- if (length(output_arg)) output_arg[[1L]] else file.path(
  "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
  if (smoke) "P8_STAYER_LANDMARK_SMOKE" else "P8_STAYER_LANDMARK")
parent_exit_dir <- if (length(parent_arg)) parent_arg[[1L]] else file.path(
  "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
  if (smoke) "P8_EXIT_DECOMPOSITION_SMOKE" else "P8_EXIT_DECOMPOSITION")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
parent_exit_dir <- normalizePath(
  parent_exit_dir, winslash = "/", mustWork = TRUE)
rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
run_stage <- function(script) {
  log <- file.path(output_dir, sub("\\.R$", ".log", script))
  child_args <- c(
    file.path("02_analysis", "R", script),
    if (smoke) "--smoke" else "--production",
    paste0("--output-dir=", output_dir),
    paste0("--parent-exit-dir=", parent_exit_dir))
  status <- system2(rscript, child_args, stdout = log, stderr = log)
  if (!identical(status, 0L)) {
    stop(script, " failed; see ", log)
  }
  message("Completed ", script)
}
run_stage("37a_lmv2_stayer_landmark_config_build.R")
run_stage("37b_estimate_certify_lmv2_stayer_landmark.R")

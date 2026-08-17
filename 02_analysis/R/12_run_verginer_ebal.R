# ============================================================================
# 12_run_verginer_ebal.R -- Run Verginer-variable entropy-balanced exercise
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
)

scripts <- file.path(BASE, "R", c(
  "12b_build_verginer_covariates.R",
  "12d_estimate_verginer_ebal.R",
  "12e_report_verginer_ebal.R"
))

for (script in scripts) {
  message("\n", strrep("=", 76), "\nRunning: ", script, "\n", strrep("=", 76))
  status <- system2(rscript, c(script, args))
  if (!identical(status, 0L)) {
    if (basename(script) == "12d_estimate_verginer_ebal.R") {
      report_script <- file.path(BASE, "R", "12e_report_verginer_ebal.R")
      message("\n12d stopped before outcome reporting; writing checkpoint from diagnostics.")
      report_status <- system2(rscript, c(report_script, args))
      if (!identical(report_status, 0L)) {
        stop("Report script also failed after 12d stop: ", report_script, call. = FALSE)
      }
    }
    stop("Script failed: ", script, call. = FALSE)
  }
}

message("\n12_run_verginer_ebal complete.")

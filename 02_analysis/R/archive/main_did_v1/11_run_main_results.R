# ============================================================================
# 11_run_main_results.R -- Run Main DiD v1 never-target panel + event study
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
RSCRIPT <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(RSCRIPT)) RSCRIPT <- file.path(R.home("bin"), "Rscript")

scripts <- c(
  file.path(BASE, "R", "11d_build_main_panel.R"),
  file.path(BASE, "R", "11e_estimate_main_results.R")
)

for (script in scripts) {
  message("\n", strrep("=", 76), "\nRunning: ", script, "\n", strrep("=", 76))
  status <- system2(RSCRIPT, script)
  if (!identical(status, 0L)) stop("Script failed: ", script, call. = FALSE)
}

message("\n11_run_main_results complete.")

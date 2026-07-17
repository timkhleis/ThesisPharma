# ============================================================================
# 11_run_robustness_results.R -- Run Main DiD v1 robustness Phase 2
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
RSCRIPT <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(RSCRIPT)) RSCRIPT <- file.path(R.home("bin"), "Rscript")

scripts <- file.path(BASE, "R", c(
  "11k_build_robustness_panels.R",
  "11l_estimate_robustness_results.R"
))

for (script in scripts) {
  message("\n", strrep("=", 76), "\nRunning robustness Phase 2 script: ", script,
          "\n", strrep("=", 76))
  status <- system2(RSCRIPT, script)
  if (!identical(status, 0L)) stop("Script failed: ", script, call. = FALSE)
}

message("\n11_run_robustness_results Phase 2 complete.")

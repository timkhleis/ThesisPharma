# ============================================================================
# 11_run_robustness.R -- Run Main DiD v1 robustness Phase 1 only
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
RSCRIPT <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(RSCRIPT)) RSCRIPT <- file.path(R.home("bin"), "Rscript")

script <- file.path(BASE, "R", "11j_build_robustness_weights.R")

message("\n", strrep("=", 76), "\nRunning Phase 1 design checkpoint: ", script,
        "\n", strrep("=", 76))
status <- system2(RSCRIPT, script)
if (!identical(status, 0L)) stop("Script failed: ", script, call. = FALSE)

message("\n11_run_robustness Phase 1 complete. Outcome estimation is intentionally not run.")

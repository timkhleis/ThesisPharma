args <- commandArgs(trailingOnly = TRUE)
lmv2_aliases <- c(
  "--local-match-v2", "--lmv2", "--current-release",
  "--verify", "--smoke", "--production", "--handoff-only"
)
if (any(args %in% lmv2_aliases)) {
  stop(
    paste(
      "02_analysis/R/run_pipeline.R builds only the canonical foundation",
      "and derived tables; it is not the Local Match v2 release runner.",
      "Use 02_analysis/R/41_run_lmv2_current_release.R instead."
    ),
    call. = FALSE
  )
}

scripts <- c(
  file.path("02_analysis", "R", "01_build_data_foundation.R"),
  file.path("02_analysis", "R", "02_build_derived_tables.R")
)

rscript <- file.path(R.home("bin"), "Rscript.exe")

for (script in scripts) {
  message("Running ", script, " ...")
  status <- system2(rscript, script)
  if (!identical(status, 0L)) {
    stop("Pipeline failed while running ", script, call. = FALSE)
  }
}

message("Merged database pipeline complete.")

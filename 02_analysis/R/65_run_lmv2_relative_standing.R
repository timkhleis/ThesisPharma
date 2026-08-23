# ============================================================================
# 65_run_lmv2_relative_standing.R -- reproduce and certify the package
# ============================================================================

scripts <- file.path(
  "02_analysis", "R",
  c(
    "65b_build_lmv2_relative_standing.R",
    "65c_estimate_lmv2_relative_standing.R",
    "65d_report_certify_lmv2_relative_standing.R",
    "65e_interview_lmv2_relative_standing.R"
  )
)
if (!all(file.exists(scripts))) {
  stop("Missing package script: ",
       paste(scripts[!file.exists(scripts)], collapse = ", "))
}
rscript <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(rscript)) rscript <- file.path(R.home("bin"), "Rscript")
for (script in scripts) {
  message("Running ", script)
  status <- system2(rscript, script)
  if (!identical(status, 0L)) {
    stop("Relative-standing package failed in ", script)
  }
}
message("Relative-standing package completed and certified.")

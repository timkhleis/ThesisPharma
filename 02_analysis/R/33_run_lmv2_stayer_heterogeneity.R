# Run the certified initially retained inventor heterogeneity package.

scripts <- c(
  "33b_build_lmv2_stayer_moderators.R",
  "33c_compute_lmv2_stayer_power_gate.R",
  "33d_estimate_lmv2_stayer_heterogeneity.R",
  "33e_report_certify_lmv2_stayer_heterogeneity.R"
)

rscript <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(rscript)) rscript <- file.path(R.home("bin"), "Rscript")

for (script in scripts) {
  message("Running ", script)
  status <- system2(
    rscript, file.path("02_analysis", "R", script),
    stdout = "", stderr = ""
  )
  if (!identical(status, 0L)) stop(script, " failed with status ", status)
}

message("Initially retained inventor heterogeneity package complete.")

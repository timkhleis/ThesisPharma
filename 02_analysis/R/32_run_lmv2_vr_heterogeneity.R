# ============================================================================
# 32_run_lmv2_vr_heterogeneity.R -- reproduce the complete package
# ============================================================================
# Run from the thesis worktree root. Each stage has its own provenance checks,
# so this wrapper stops immediately if a frozen input or prior stage is stale.

scripts <- file.path(
  "02_analysis", "R",
  c(
    "32b_build_lmv2_vr_moderators.R",
    "32c_compute_lmv2_vr_power_gate.R",
    "32d_estimate_lmv2_vr_heterogeneity.R",
    "32e_report_certify_lmv2_vr_heterogeneity.R"
  )
)
if (!all(file.exists(scripts))) {
  stop("Missing package script: ", paste(scripts[!file.exists(scripts)],
                                          collapse = ", "))
}
rscript <- file.path(R.home("bin"), "Rscript.exe")
for (script in scripts) {
  message("Running ", script)
  status <- system2(rscript, script)
  if (!identical(status, 0L)) {
    stop("VR heterogeneity package failed in ", script)
  }
}
message("VR heterogeneity package completed and certified.")

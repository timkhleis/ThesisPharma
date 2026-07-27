# ============================================================================
# Package 1D: attach loyo_m1 weights to P6 and run the frozen estimator
# ============================================================================

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
if (!requireNamespace("digest", quietly = TRUE)) stop("Missing package: digest")

P6_ROOT <- normalizePath(file.path(BASE, ".."), winslash = "/", mustWork = TRUE)
WORKTREES <- normalizePath(file.path(P6_ROOT, ".."), winslash = "/", mustWork = TRUE)
P4_ROOT <- normalizePath(
  file.path(WORKTREES, "lmv2-p4-ebal"), winslash = "/", mustWork = TRUE)
AUDIT_ROOT <- file.path(BASE, "output", "audit", "local_match_v2")
P4_AUDIT_ROOT <- file.path(
  P4_ROOT, "02_analysis", "output", "audit", "local_match_v2")
FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_package1d_mean_reversion_freeze.md")

base_panel_dir <- file.path(
  AUDIT_ROOT, "P6_V3_PRODUCTION_FREEZE_1ED", "panel_matched")
base_manifest <- file.path(
  AUDIT_ROOT, "P6_V3_PRODUCTION_FREEZE_1ED", "p6_manifest.csv")
p4_cert_path <- file.path(
  P4_AUDIT_ROOT, "P5C_PACKAGE1D_LOYO_M1",
  "package1d_loyo_m1_certification.csv")
handoff_dir <- file.path(
  P4_AUDIT_ROOT, "P5C_P6_HANDOFF_PACKAGE1D_LOYO_M1")
roster <- file.path(
  handoff_dir, "p5c_p6_primary_weighted_roster.parquet")
roster_manifest <- file.path(
  handoff_dir, "p5c_p6_roster_manifest.csv")

required <- c(
  base_panel_dir, base_manifest, p4_cert_path, roster, roster_manifest,
  FREEZE_PATH,
  file.path(BASE, "R", "20a_reweight_lmv2_p6_panel.R"),
  file.path(BASE, "R", "19c_run_lmv2_p6_estimation.R"),
  file.path(BASE, "R", "19d_certify_lmv2_p6_estimation.R"))
if (!all(file.exists(required) | dir.exists(required))) {
  stop("Package 1D P6 input is missing")
}
p4_cert <- utils::read.csv(p4_cert_path, stringsAsFactors = FALSE)
if (nrow(p4_cert) != 1L || !isTRUE(p4_cert$all_pass)) {
  stop("Package 1D loyo_m1 weights are not certified")
}

rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
run_r <- function(script, args) {
  status <- system2(
    rscript, c(shQuote(script), vapply(args, shQuote, character(1))))
  if (!identical(status, 0L)) {
    stop("Package 1D child script failed (", status, "): ", basename(script))
  }
}

panel_out <- file.path(AUDIT_ROOT, "P6_PACKAGE1D_PANEL_LOYO_M1")
panel_manifest <- file.path(panel_out, "p6_manifest.csv")
if (!file.exists(panel_manifest)) {
  run_r(
    file.path(BASE, "R", "20a_reweight_lmv2_p6_panel.R"),
    c(
      paste0("--base-panel-dir=", base_panel_dir),
      paste0("--base-p6-manifest=", base_manifest),
      paste0("--roster=", roster),
      paste0("--roster-manifest=", roster_manifest),
      paste0("--output-dir=", panel_out)))
}
panel_info <- utils::read.csv(panel_manifest, stringsAsFactors = FALSE)
if (nrow(panel_info) != 1L ||
    panel_info$p5c_variant != "loyo_m1" ||
    !isTRUE(panel_info$p5c_reweight_certification_pass)) {
  stop("Reweighted Package 1D P6 panel is invalid")
}

estimation_out <- file.path(AUDIT_ROOT, "P6_PACKAGE1D_ESTIMATION_LOYO_M1")
estimation_cert <- file.path(
  estimation_out, "p6_estimation_certification_manifest.csv")
if (!file.exists(estimation_cert)) {
  if (dir.exists(estimation_out) &&
      length(list.files(estimation_out, all.files = TRUE, no.. = TRUE))) {
    stop("Partial Package 1D estimation directory requires review")
  }
  run_r(
    file.path(BASE, "R", "19c_run_lmv2_p6_estimation.R"),
    c(
      paste0("--panel-dir=", file.path(panel_out, "panel_matched")),
      paste0("--p6-manifest=", panel_manifest),
      paste0("--output-dir=", estimation_out)))
  run_r(
    file.path(BASE, "R", "19d_certify_lmv2_p6_estimation.R"),
    paste0("--estimation-dir=", estimation_out))
}
estimation_cert_info <- utils::read.csv(
  estimation_cert, stringsAsFactors = FALSE)
if (nrow(estimation_cert_info) != 1L ||
    estimation_cert_info$n_failed != 0) {
  stop("Package 1D P6 estimation certification failed")
}

out_dir <- file.path(AUDIT_ROOT, "P6_PACKAGE1D_MEAN_REVERSION")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
run_manifest <- data.frame(
  variant = "loyo_m1",
  roster_manifest = normalizePath(
    roster_manifest, winslash = "/", mustWork = TRUE),
  roster_manifest_sha256 = digest::digest(
    file = roster_manifest, algo = "sha256"),
  panel_manifest = normalizePath(
    panel_manifest, winslash = "/", mustWork = TRUE),
  panel_manifest_sha256 = digest::digest(
    file = panel_manifest, algo = "sha256"),
  estimation_manifest = normalizePath(
    file.path(estimation_out, "p6_estimation_manifest.csv"),
    winslash = "/", mustWork = TRUE),
  estimation_manifest_sha256 = digest::digest(
    file = file.path(estimation_out, "p6_estimation_manifest.csv"),
    algo = "sha256"),
  certification_manifest_sha256 = digest::digest(
    file = estimation_cert, algo = "sha256"),
  freeze_sha256 = digest::digest(file = FREEZE_PATH, algo = "sha256"),
  runner_sha256 = digest::digest(
    file = file.path(BASE, "R", "23a_run_lmv2_package1d_p6.R"),
    algo = "sha256"),
  pass = TRUE,
  stringsAsFactors = FALSE)
utils::write.csv(
  run_manifest,
  file.path(out_dir, "package1d_p6_run_manifest.csv"),
  row.names = FALSE, na = "")
print(run_manifest)

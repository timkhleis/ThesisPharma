# ============================================================================
# Package 1: attach missing LOYO weights to P6 and run the frozen estimator
# ============================================================================

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
if (!requireNamespace("digest", quietly = TRUE)) {
  stop("Missing package: digest")
}

AUDIT_ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment")
RELEASE_ROOT <- file.path(AUDIT_ROOT, "ROBUSTNESS_RELEASE_1993")

base_panel_dir <- file.path(
  AUDIT_ROOT, "P6_P5C_COUNT_ACTIVE", "panel_matched")
base_manifest <- file.path(
  AUDIT_ROOT, "P6_P5C_COUNT_ACTIVE", "p6_manifest.csv")
p4_grid_cert <- file.path(
  RELEASE_ROOT, "P5C_LOYO_GRID",
  "package1_loyo_grid_certification.csv")
freeze_path <- file.path(
  BASE, "notes", "local_match_v2_package1_preperiod_freeze.md")

required <- c(
  base_panel_dir, base_manifest, p4_grid_cert, freeze_path,
  file.path(BASE, "R", "20a_reweight_lmv2_p6_panel.R"),
  file.path(BASE, "R", "19c_run_lmv2_p6_estimation.R"),
  file.path(BASE, "R", "19d_certify_lmv2_p6_estimation.R"))
if (!all(file.exists(required) | dir.exists(required))) {
  stop("Package 1 P6 input is missing")
}
p4_cert <- utils::read.csv(
  p4_grid_cert, stringsAsFactors = FALSE)
if (nrow(p4_cert) != 1L || !isTRUE(p4_cert$all_pass)) {
  stop("Package 1 LOYO weight grid is not certified")
}

rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
run_r <- function(script, args) {
  status <- system2(
    rscript,
    c(shQuote(script), vapply(args, shQuote, character(1))))
  if (!identical(status, 0L)) {
    stop("Package 1 child script failed (", status, "): ", basename(script))
  }
}

variants <- c("loyo_m2", "loyo_m3", "loyo_m4", "loyo_m5")
results <- list()
for (variant in variants) {
  label <- toupper(variant)
  handoff_dir <- file.path(
    RELEASE_ROOT, paste0("P5C_P6_HANDOFF_", label))
  roster <- file.path(
    handoff_dir, "p5c_p6_primary_weighted_roster.parquet")
  roster_manifest <- file.path(
    handoff_dir, "p5c_p6_roster_manifest.csv")
  if (!file.exists(roster) || !file.exists(roster_manifest)) {
    stop("Package 1 handoff missing for ", variant)
  }

  panel_out <- file.path(
    RELEASE_ROOT, paste0("P6_PACKAGE1_PANEL_", label))
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
  panel_info <- utils::read.csv(
    panel_manifest, stringsAsFactors = FALSE)
  if (nrow(panel_info) != 1L ||
      panel_info$p5c_variant != variant ||
      !isTRUE(panel_info$p5c_reweight_certification_pass)) {
    stop("Reweighted Package 1 P6 panel is invalid for ", variant)
  }

  estimation_out <- file.path(
    RELEASE_ROOT, paste0("P6_PACKAGE1_ESTIMATION_", label))
  estimation_cert <- file.path(
    estimation_out, "p6_estimation_certification_manifest.csv")
  if (!file.exists(estimation_cert)) {
    if (dir.exists(estimation_out) &&
        length(list.files(
          estimation_out, all.files = TRUE, no.. = TRUE))) {
      stop(
        "Partial Package 1 estimation directory requires review: ",
        estimation_out)
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
    stop("Package 1 P6 estimation certification failed for ", variant)
  }

  results[[variant]] <- data.frame(
    variant = variant,
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
    pass = TRUE,
    stringsAsFactors = FALSE)
}

out_dir <- file.path(RELEASE_ROOT, "P6_PACKAGE1_LOYO_GRID")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
run_manifest <- do.call(rbind, results)
run_manifest$freeze_sha256 <- digest::digest(
  file = freeze_path, algo = "sha256")
run_manifest$runner_sha256 <- digest::digest(
  file = file.path(BASE, "R", "21b_run_lmv2_package1_p6.R"),
  algo = "sha256")
utils::write.csv(
  run_manifest,
  file.path(out_dir, "package1_p6_run_manifest.csv"),
  row.names = FALSE, na = "")
print(run_manifest)


# Provenance-gated wrapper around the certified P6 estimator.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit)
}
design <- read_arg("design")
panel_dir <- normalizePath(
  read_arg("panel-dir"), winslash = "/", mustWork = TRUE)
panel_manifest <- normalizePath(
  read_arg("p6-manifest"), winslash = "/", mustWork = TRUE)
output_dir <- read_arg("output-dir")

BASE <- normalizePath("02_analysis", mustWork = TRUE)
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
source(file.path(BASE, "R", "20b_lmv2_p6_p5c_freeze.R"))
lmv2_p6_p5c_assert_freeze(design, panel_manifest)

rscript <- file.path(
  R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
runner <- file.path(BASE, "R", "19c_run_lmv2_p6_estimation.R")
status <- system2(
  rscript,
  c(
    runner,
    paste0("--panel-dir=", shQuote(panel_dir)),
    paste0("--p6-manifest=", shQuote(panel_manifest)),
    paste0("--output-dir=", shQuote(output_dir))))
if (!identical(status, 0L)) {
  stop("Certified P6 estimator failed with status ", status)
}

estimation_manifest <- file.path(
  output_dir, "p6_estimation_manifest.csv")
if (!file.exists(estimation_manifest)) {
  stop("P6 estimator did not create its manifest")
}
attestation <- data.frame(
  design = design,
  freeze_sha256 = LMV2_P6_P5C_FREEZE_SHA256,
  panel_manifest_sha256 = digest::digest(
    file = panel_manifest, algo = "sha256"),
  estimation_manifest_sha256 = digest::digest(
    file = estimation_manifest, algo = "sha256"),
  wrapper_sha256 = digest::digest(
    file = file.path(
      BASE, "R", "20c_run_lmv2_p6_p5c_estimation.R"),
    algo = "sha256"),
  completed_at = as.character(Sys.time()),
  stringsAsFactors = FALSE)
utils::write.csv(
  attestation,
  file.path(output_dir, "p6_p5c_freeze_attestation.csv"),
  row.names = FALSE)


# ============================================================================
# 15g_run_lmv2_p2.R -- deterministic P2 build and certification runner
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))

AUDIT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P2")
dir.create(AUDIT_DIR, recursive = TRUE, showWarnings = FALSE)
rscript <- file.path(R.home("bin"), "Rscript.exe")
build_script <- file.path(BASE, "R", "15e_build_lmv2_p2.R")
cert_script <- file.path(BASE, "R", "15f_certify_lmv2_p2.R")
manifest_path <- file.path(AUDIT_DIR, "p2_interface_manifest.csv")

run_script <- function(path) {
  status <- system2(rscript, shQuote(path))
  if (!identical(status, 0L)) stop("P2 script failed: ", basename(path))
}

run_script(build_script)
first <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
run_script(build_script)
second <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)

key <- c("table", "rows", "logical_sha256")
deterministic <- identical(first[, key], second[, key])
det <- data.frame(
  design_version = LMV2_DESIGN_VERSION,
  design_hash = LMV2_DESIGN_HASH,
  check = "two_complete_p2_builds_have_identical_logical_manifests",
  pass = deterministic,
  stringsAsFactors = FALSE
)
utils::write.csv(det, file.path(AUDIT_DIR, "p2_rebuild_determinism.csv"),
                 row.names = FALSE, na = "")
if (!deterministic) stop("P2 logical manifests differ across complete rebuilds.")

run_script(cert_script)
status <- utils::read.csv(file.path(AUDIT_DIR, "p2_package_status.csv"),
                          stringsAsFactors = FALSE)
print(det)
print(status)


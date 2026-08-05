# ============================================================================
# 16e_run_lmv2_p3.R -- twice-built deterministic P3 package runner
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
dir.create(LMV2_P3_PATHS$audit, recursive = TRUE, showWarnings = FALSE)
rscript <- file.path(R.home("bin"), "Rscript.exe")
build <- file.path(BASE, "R", "16b_build_lmv2_matching_covariates.R")
cert <- file.path(BASE, "R", "16d_certify_lmv2_matching_engine.R")
manifest_path <- file.path(LMV2_P3_PATHS$audit, "p3_interface_manifest.csv")

run_script <- function(path) {
  status <- system2(rscript, shQuote(path, type = "cmd"))
  if (!identical(status, 0L)) stop("P3 script failed: ", basename(path))
}
read_manifest <- function() {
  x <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
  x[order(x$table), c("table","rows","logical_sha256","p3_config_hash",
                       "p2_manifest_hash","amendment_hash")]
}

started <- Sys.time()
run_script(build)
first <- read_manifest()
utils::write.csv(first,file.path(LMV2_P3_PATHS$audit,"p3_interface_manifest_run1.csv"),
                 row.names=FALSE,na="")
first_done <- Sys.time()
run_script(build)
second <- read_manifest()
utils::write.csv(second,file.path(LMV2_P3_PATHS$audit,"p3_interface_manifest_run2.csv"),
                 row.names=FALSE,na="")
second_done <- Sys.time()

deterministic <- identical(first, second)
comparison <- merge(first,second,by="table",suffixes=c("_run1","_run2"),sort=TRUE)
comparison$identical <- vapply(seq_len(nrow(comparison)), function(i) {
  identical(first[first$table==comparison$table[i],,drop=FALSE],
            second[second$table==comparison$table[i],,drop=FALSE])
}, logical(1))
utils::write.csv(comparison,
                 file.path(LMV2_P3_PATHS$audit,"p3_interface_manifest_comparison.csv"),
                 row.names=FALSE,na="")
det <- data.frame(
  p3_version=LMV2_P3_VERSION,p3_config_hash=LMV2_P3_CONFIG_HASH,
  check="two_complete_p3_builds_have_identical_logical_manifests",
  pass=deterministic,
  first_build_minutes=as.numeric(difftime(first_done,started,units="mins")),
  second_build_minutes=as.numeric(difftime(second_done,first_done,units="mins")),
  stringsAsFactors=FALSE
)
utils::write.csv(det,file.path(LMV2_P3_PATHS$audit,"p3_rebuild_determinism.csv"),
                 row.names=FALSE,na="")
if (!deterministic) stop("P3 logical manifests differ across complete rebuilds")
run_script(cert)
print(det)

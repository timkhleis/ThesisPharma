# ============================================================================
# 15d_run_lmv2_p1.R -- isolated, twice-built P1 package runner
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
load_packages()
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))

audit_dir <- file.path(BASE, "output", "audit", "local_match_v2", "p1")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

con <- connect_duckdb(read_only = TRUE)
current_pre <- DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) AS inventor_year_rows,
    COUNT(DISTINCT (codinv, year)) AS inventor_year_keys,
    COUNT(*) - COUNT(DISTINCT (codinv, year)) AS duplicate_rows,
    SUM(patent_count) AS reported_patent_count_sum,
    SUM(fractional_patent_count) AS reported_fractional_count_sum
  FROM inventor_year
")
source_spine <- DBI::dbGetQuery(con, "
  SELECT
    (SELECT COUNT(*) FROM patent_inventor) AS patent_inventor_rows,
    (SELECT COUNT(DISTINCT (codinv, appln_id)) FROM patent_inventor) AS distinct_inventor_application_pairs,
    (SELECT COUNT(*) FROM patent_application) AS patent_applications,
    (SELECT COUNT(DISTINCT codinv) FROM inventor) AS inventor_ids
")
disconnect_duckdb(con)

snapshot_path <- file.path(audit_dir, "p1_pre_repair_snapshot.csv")
if (file.exists(snapshot_path)) {
  saved_pre <- read.csv(snapshot_path, stringsAsFactors = FALSE)
  pre <- if (saved_pre$duplicate_rows[[1]] > 0) saved_pre else current_pre
} else {
  pre <- current_pre
}
pre$design_hash <- LMV2_DESIGN_HASH
source_spine$design_hash <- LMV2_DESIGN_HASH
write.csv(pre, snapshot_path, row.names = FALSE, na = "")
write.csv(source_spine, file.path(audit_dir, "p1_source_spine.csv"), row.names = FALSE, na = "")

rscript <- file.path(R.home("bin"), "Rscript.exe")
run_script <- function(script, args = character()) {
  status <- system2(rscript, c(file.path(BASE, "R", script), args))
  if (!identical(status, 0L)) stop(script, " failed with status ", status)
}

for (label in c("run1", "run2")) {
  message("P1 ", label, ": rebuilding derived foundation")
  run_script("02_build_derived_tables.R")
  message("P1 ", label, ": certifying")
  run_script("15c_certify_lmv2_p1.R", label)
}

read_char_csv <- function(path) {
  utils::read.csv(path, colClasses = "character", check.names = FALSE,
                  stringsAsFactors = FALSE)
}
cs1 <- read_char_csv(file.path(audit_dir, "p1_logical_checksums_run1.csv"))
cs2 <- read_char_csv(file.path(audit_dir, "p1_logical_checksums_run2.csv"))
logical_cols <- c("table_name", "n_rows", "hash_sum", "hash_xor", "design_hash")
logical_reproducible <- identical(cs1[logical_cols], cs2[logical_cols])
parquet_reproducible <- identical(cs1[c("table_name", "parquet_md5")],
                                  cs2[c("table_name", "parquet_md5")])
if (!logical_reproducible) stop("P1 logical checksums differ across the two builds")

checks <- read.csv(file.path(audit_dir, "p1_checks_run2.csv"), stringsAsFactors = FALSE)
final <- data.frame(
  design_version = LMV2_DESIGN_VERSION,
  design_hash = LMV2_DESIGN_HASH,
  p1_pass = all(checks$pass) && logical_reproducible,
  acceptance_checks = nrow(checks),
  failed_checks = sum(!checks$pass),
  logical_checksums_reproducible = logical_reproducible,
  physical_parquet_md5_reproducible = parquet_reproducible,
  physical_parquet_md5_is_gate = FALSE,
  physical_parquet_note = "unordered table export; logical table checksum is the reproducibility gate",
  pre_repair_duplicate_rows = pre$duplicate_rows,
  post_repair_duplicate_rows = checks$value[checks$metric == "inventor_year_duplicate_rows"],
  stringsAsFactors = FALSE
)
write.csv(final, file.path(audit_dir, "p1_acceptance.csv"), row.names = FALSE, na = "")
if (!isTRUE(final$p1_pass)) stop("P1 final acceptance failed")
message("P1 PACKAGE PASS | logical checksums reproduced across two full builds")

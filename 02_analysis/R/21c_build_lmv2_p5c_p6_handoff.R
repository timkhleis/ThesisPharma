# ============================================================================
# P5c -> P6 weighted-roster handoff
# ============================================================================
# Preserves every certified P5a roster field and replaces only `weight`, using
# an exact roster_row_id join to the certified P5c cohort files.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit)
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(
  BASE, "R", "21a_lmv2_p5c_annual_trajectory_config.R"))
source(file.path(
  BASE, "R", "21d_lmv2_p5c_provenance_lock.R"))
for (package in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Missing package: ", package)
  }
}

source_roster <- normalizePath(
  read_arg("source-roster"), winslash = "/", mustWork = TRUE)
diagnostics_path <- normalizePath(
  read_arg("p5c-diagnostics"), winslash = "/", mustWork = TRUE)
source_manifest_path <- normalizePath(
  read_arg("source-weight-manifest"), winslash = "/", mustWork = TRUE)
variant <- read_arg("variant")
if (!variant %in% c(
    LMV2_P5C$production_variant,
    LMV2_P5C$placebo_variants)) {
  stop("Unsupported P5c handoff variant: ", variant)
}
lmv2_p5c_assert_provenance(source_manifest_path)
execution_hash <- lmv2_p5c_execution_hash(source_manifest_path)
output_dir <- read_arg("output-dir")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(
  output_dir, winslash = "/", mustWork = TRUE)

diagnostics <- utils::read.csv(
  diagnostics_path, stringsAsFactors = FALSE)
selected <- diagnostics[
  diagnostics$execution_hash == execution_hash &
    diagnostics$scheme == "primary" &
    diagnostics$variant == variant &
    diagnostics$feasible, ,
  drop = FALSE]
if (nrow(selected) != length(LMV2_P5C$cohorts) ||
    !identical(sort(as.integer(selected$cohort)), LMV2_P5C$cohorts) ||
    any(!file.exists(selected$weight_path))) {
  stop("Expected one complete certified P5c primary weight file per cohort")
}
for (i in seq_len(nrow(selected))) {
  observed <- digest::digest(
    file = selected$weight_path[[i]], algo = "sha256")
  if (!identical(observed, selected$weight_sha256[[i]])) {
    stop("P5c weight checksum failed for cohort ", selected$cohort[[i]])
  }
}

sql_quote <- function(con, path) {
  as.character(DBI::dbQuoteString(
    con, normalizePath(path, winslash = "/", mustWork = TRUE)))
}
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=4")
DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")
weight_list <- paste(
  vapply(
    selected$weight_path,
    function(path) sql_quote(con, path),
    character(1)),
  collapse = ",")
old_sql <- sprintf(
  "read_parquet(%s)", sql_quote(con, source_roster))
new_sql <- sprintf("read_parquet([%s])", weight_list)

checks_before <- data.frame(
  check = c(
    "source_unique_row_ids", "p5c_unique_row_ids",
    "source_rows_missing_p5c", "p5c_rows_missing_source",
    "same_row_count"),
  observed = c(
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*)-COUNT(DISTINCT roster_row_id) n FROM %s",
      old_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*)-COUNT(DISTINCT roster_row_id) n FROM %s",
      new_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM %s o
       ANTI JOIN %s w USING(roster_row_id)", old_sql, new_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM %s w
       ANTI JOIN %s o USING(roster_row_id)", new_sql, old_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT ABS(
         (SELECT COUNT(*) FROM %s)-
         (SELECT COUNT(*) FROM %s)) n",
      old_sql, new_sql))$n),
  expected = 0,
  stringsAsFactors = FALSE)
checks_before$pass <- checks_before$observed == checks_before$expected
if (!all(checks_before$pass)) {
  stop(
    "P5c handoff identity gate failed: ",
    paste(checks_before$check[!checks_before$pass], collapse = ", "))
}

roster_path <- file.path(
  output_dir, "p5c_p6_primary_weighted_roster.parquet")
tmp_path <- paste0(roster_path, ".tmp.parquet")
if (file.exists(tmp_path)) file.remove(tmp_path)
DBI::dbExecute(con, sprintf(
  "COPY (
     SELECT o.* REPLACE (CAST(w.final_weight AS DOUBLE) AS weight)
     FROM %s o
     JOIN %s w USING(roster_row_id)
     ORDER BY o.cohort,o.deal_id,o.arm DESC,o.codinv,
              o.focal_group_1,o.roster_row_id
   ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
  old_sql, new_sql, DBI::dbQuoteString(con, tmp_path)))
if (file.exists(roster_path)) file.remove(roster_path)
if (!file.rename(tmp_path, roster_path)) {
  stop("Could not atomically publish P5c P6 roster")
}

roster_sql <- sprintf(
  "read_parquet(%s)", DBI::dbQuoteString(con, roster_path))
checks_after <- data.frame(
  check = c(
    "all_amended_cohorts", "unique_roster_ids",
    "finite_positive_weights", "treated_weights_unchanged",
    "cohort_weight_mass_equal", "roster_rows"),
  observed = c(
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(DISTINCT cohort) n FROM %s", roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*)-COUNT(DISTINCT roster_row_id) n FROM %s",
      roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM %s
       WHERE weight IS NULL OR NOT isfinite(weight) OR weight<=0",
      roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM %s
       WHERE arm='treated' AND weight<>1", roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT cohort FROM %s GROUP BY cohort
         HAVING ABS(
           SUM(weight) FILTER(WHERE arm='treated')-
           SUM(weight) FILTER(WHERE arm='control'))>1e-7)",
      roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM %s", roster_sql))$n),
  expected = c(
    length(LMV2_P5C$cohorts), 0, 0, 0, 0,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM %s", old_sql))$n),
  stringsAsFactors = FALSE)
checks_after$pass <- checks_after$observed == checks_after$expected
certification <- rbind(checks_before, checks_after)
utils::write.csv(
  certification,
  file.path(output_dir, "p5c_p6_roster_certification.csv"),
  row.names = FALSE)
if (!all(certification$pass)) {
  stop(
    "P5c P6 roster certification failed: ",
    paste(certification$check[!certification$pass], collapse = ", "))
}

freeze_hash <- digest::digest(
  file = LMV2_P5C$freeze_note, algo = "sha256")
source_hash <- digest::digest(
  file = file.path(
    BASE, "R", "21c_build_lmv2_p5c_p6_handoff.R"),
  algo = "sha256")
weight_hashes <- selected$weight_sha256[
  order(as.integer(selected$cohort))]
roster_rows <- DBI::dbGetQuery(con, sprintf(
  "SELECT COUNT(*) n FROM %s", roster_sql))$n[[1]]
design_hash <- digest::digest(
  list(
    p5c_execution_hash = execution_hash,
    p5c_variant = variant,
    p5c_freeze_sha256 = freeze_hash,
    source_p5a_roster_sha256 = digest::digest(
      file = source_roster, algo = "sha256"),
    p5c_weight_sha256 = weight_hashes,
    handoff_source_sha256 = source_hash),
  algo = "sha256")
manifest <- data.frame(
  roster_sha256 = digest::digest(
    file = roster_path, algo = "sha256"),
  roster_rows = roster_rows,
  p5a_design_hash = design_hash,
  certification_pass = TRUE,
  production_freeze_hash = freeze_hash,
  handoff_source_sha256 = source_hash,
  p5c_execution_hash = execution_hash,
  p5c_variant = variant,
  source_p5a_roster_sha256 = digest::digest(
    file = source_roster, algo = "sha256"),
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest,
  file.path(output_dir, "p5c_p6_roster_manifest.csv"),
  row.names = FALSE)
message(
  "P5c-P6 weighted roster certified: ", roster_rows,
  " rows | design_hash=",
  design_hash)

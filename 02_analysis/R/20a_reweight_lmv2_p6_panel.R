# ============================================================================
# Reuse certified P6 outcomes with a new, row-identical P5c weight roster
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit)
}
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}

base_panel_dir <- normalizePath(
  read_arg("base-panel-dir"), winslash = "/", mustWork = TRUE)
base_manifest_path <- normalizePath(
  read_arg("base-p6-manifest"), winslash = "/", mustWork = TRUE)
roster_path <- normalizePath(
  read_arg("roster"), winslash = "/", mustWork = TRUE)
roster_manifest_path <- normalizePath(
  read_arg("roster-manifest"), winslash = "/", mustWork = TRUE)
output_dir <- read_arg("output-dir")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(
  output_dir, winslash = "/", mustWork = TRUE)
panel_dir <- file.path(output_dir, "panel_matched")
dir.create(panel_dir, recursive = TRUE, showWarnings = FALSE)

roster_manifest <- utils::read.csv(
  roster_manifest_path, stringsAsFactors = FALSE)
if (nrow(roster_manifest) != 1L ||
    !isTRUE(roster_manifest$certification_pass) ||
    !identical(
      digest::digest(file = roster_path, algo = "sha256"),
      roster_manifest$roster_sha256)) {
  stop("P5c roster manifest is invalid or does not match its roster")
}
base_manifest <- utils::read.csv(
  base_manifest_path, stringsAsFactors = FALSE)
if (nrow(base_manifest) != 1L ||
    base_manifest$n_failed != 0) {
  stop("Base P6 construction manifest is invalid")
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")
quote_path <- function(path) {
  as.character(DBI::dbQuoteString(
    con, normalizePath(path, winslash = "/", mustWork = TRUE)))
}
roster_sql <- sprintf("read_parquet(%s)", quote_path(roster_path))
cohorts <- DBI::dbGetQuery(con, sprintf(
  "SELECT DISTINCT CAST(cohort AS INTEGER) cohort
   FROM %s ORDER BY cohort", roster_sql))$cohort

results <- list()
for (cohort in cohorts) {
  base_path <- file.path(
    base_panel_dir,
    sprintf("lmv2_event_panel_c%d.parquet", cohort))
  base_stamp_path <- file.path(
    base_panel_dir,
    sprintf("lmv2_event_panel_c%d_stamp.csv", cohort))
  if (!file.exists(base_path) || !file.exists(base_stamp_path)) {
    stop("Base P6 shard or stamp missing for cohort ", cohort)
  }
  base_sql <- sprintf("read_parquet(%s)", quote_path(base_path))
  identity <- DBI::dbGetQuery(con, sprintf(
    "WITH p AS (
       SELECT DISTINCT roster_row_id FROM %s
     ), r AS (
       SELECT roster_row_id FROM %s WHERE cohort=%d
     )
     SELECT
       (SELECT COUNT(*) FROM p) panel_units,
       (SELECT COUNT(*) FROM r) roster_units,
       (SELECT COUNT(*) FROM p ANTI JOIN r USING(roster_row_id))
         panel_only,
       (SELECT COUNT(*) FROM r ANTI JOIN p USING(roster_row_id))
         roster_only",
    base_sql, roster_sql, cohort))
  if (identity$panel_units != identity$roster_units ||
      identity$panel_only != 0 || identity$roster_only != 0) {
    stop("P5c/P6 roster identity mismatch for cohort ", cohort)
  }

  final_path <- file.path(
    panel_dir,
    sprintf("lmv2_event_panel_c%d.parquet", cohort))
  temp_path <- paste0(final_path, ".tmp.parquet")
  if (file.exists(temp_path)) file.remove(temp_path)
  DBI::dbExecute(con, sprintf(
    "COPY (
       SELECT p.* REPLACE (CAST(r.weight AS DOUBLE) AS weight)
       FROM %s p
       JOIN %s r USING(roster_row_id)
       WHERE r.cohort=%d
       ORDER BY p.deal_id,p.arm,p.codinv,p.roster_row_id,p.event_time
     ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
    base_sql, roster_sql, cohort,
    DBI::dbQuoteString(con, temp_path)))
  if (file.exists(final_path)) file.remove(final_path)
  if (!file.rename(temp_path, final_path)) {
    stop("Could not publish P5c P6 shard for cohort ", cohort)
  }

  output_sql <- sprintf(
    "read_parquet(%s)", DBI::dbQuoteString(con, final_path))
  checks <- DBI::dbGetQuery(con, sprintf(
    "WITH b AS (SELECT * FROM %s),
          o AS (SELECT * FROM %s),
          masses AS (
            SELECT
              SUM(weight) FILTER(
                WHERE arm='treated' AND event_time=-1) tm,
              SUM(weight) FILTER(
                WHERE arm='control' AND event_time=-1) cm
            FROM o)
     SELECT
       (SELECT COUNT(*) FROM b) base_rows,
       (SELECT COUNT(*) FROM o) output_rows,
       (SELECT COUNT(*) FROM o
        WHERE weight IS NULL OR NOT isfinite(weight) OR weight<=0)
          bad_weights,
       (SELECT ABS(tm-cm) FROM masses) mass_gap,
       (SELECT COUNT(*) FROM o
        WHERE arm='treated' AND weight<>1) bad_treated_weights",
    base_sql, output_sql))
  if (checks$base_rows != checks$output_rows ||
      checks$bad_weights != 0 ||
      checks$mass_gap > 1e-7 ||
      checks$bad_treated_weights != 0) {
    stop("Reweighted P6 shard failed invariants for cohort ", cohort)
  }

  roster_hash <- DBI::dbGetQuery(con, sprintf(
    "SELECT
       COUNT(*) AS roster_rows,
       CAST(SUM(CAST(hash(
         deal_id,arm,codinv,roster_row_id,weight,status_eligible,
         focal_group_1,focal_group_2,use_target_company_path,
         qualification_route,target_to_acquirer_transition_strict,
         latest_pre_candidate_group_count,multi_exposure_inventor,
         big_deal) AS HUGEINT)) AS VARCHAR) AS roster_hash_sum,
       CAST(bit_xor(hash(
         deal_id,arm,codinv,roster_row_id,weight,status_eligible,
         focal_group_1,focal_group_2,use_target_company_path,
         qualification_route,target_to_acquirer_transition_strict,
         latest_pre_candidate_group_count,multi_exposure_inventor,
         big_deal)) AS VARCHAR) AS roster_hash_xor
     FROM %s WHERE cohort=%d",
    roster_sql, cohort))
  stamp <- utils::read.csv(
    base_stamp_path, stringsAsFactors = FALSE)
  stamp$roster_rows <- roster_hash$roster_rows
  stamp$roster_hash_sum <- roster_hash$roster_hash_sum
  stamp$roster_hash_xor <- roster_hash$roster_hash_xor
  stamp$shard_rows <- checks$output_rows
  stamp$shard_parquet_md5 <- unname(tools::md5sum(final_path))
  stamp$p5c_roster_sha256 <- roster_manifest$roster_sha256
  stamp$p5c_design_hash <- roster_manifest$p5a_design_hash
  stamp$p5c_variant <- roster_manifest$p5c_variant
  utils::write.csv(
    stamp,
    file.path(
      panel_dir,
      sprintf("lmv2_event_panel_c%d_stamp.csv", cohort)),
    row.names = FALSE)
  results[[length(results) + 1L]] <- data.frame(
    cohort = cohort,
    units = identity$panel_units,
    rows = checks$output_rows,
    mass_gap = checks$mass_gap,
    shard_md5 = stamp$shard_parquet_md5,
    stringsAsFactors = FALSE)
}

certification <- do.call(rbind, results)
utils::write.csv(
  certification,
  file.path(output_dir, "p6_p5c_reweight_certification.csv"),
  row.names = FALSE)

source_hash <- digest::digest(
  file = file.path(
    BASE, "R", "20a_reweight_lmv2_p6_panel.R"),
  algo = "sha256")
manifest <- base_manifest
manifest$roster_path <- roster_path
manifest$roster_sha256 <- roster_manifest$roster_sha256
manifest$roster_manifest_path <- roster_manifest_path
manifest$roster_manifest_sha256 <- digest::digest(
  file = roster_manifest_path, algo = "sha256")
manifest$p5a_design_hash <- roster_manifest$p5a_design_hash
manifest$p5c_variant <- roster_manifest$p5c_variant
manifest$p5c_execution_hash <- roster_manifest$p5c_execution_hash
manifest$p5c_reweight_source_sha256 <- source_hash
manifest$p5c_reweight_certification_pass <- TRUE
manifest$runtime_minutes <- NA_real_
utils::write.csv(
  manifest,
  file.path(output_dir, "p6_manifest.csv"),
  row.names = FALSE)
message(
  "P6 panel reweighted and certified for ",
  roster_manifest$p5c_variant, ": ",
  sum(certification$rows), " rows")

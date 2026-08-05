# Build the certified primary-weight roster consumed by P6.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit)
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(BASE, "R", "19i_lmv2_p5_final_production_config.R"))
for (package in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Missing package: ", package)
  }
}

db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
production_root <- normalizePath(
  read_arg("production-root"), winslash = "/", mustWork = TRUE)
output_dir <- read_arg("output-dir")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)

comparison_path <- file.path(
  production_root, "finalized", "comparison_weight_manifest.csv")
comparison <- utils::read.csv(
  comparison_path, stringsAsFactors = FALSE)
primary <- comparison[
  comparison$estimand == "primary_full_supported", , drop = FALSE]
if (nrow(primary) != length(LMV2_P5_PRODUCTION$cohorts) ||
    !identical(
      sort(as.integer(primary$cohort)), LMV2_P5_PRODUCTION$cohorts) ||
    any(primary$status != "complete")) {
  stop("Expected one complete primary-full P5 weight file per cohort")
}
for (index in seq_len(nrow(primary))) {
  if (!identical(
      lmv2_p3_file_hash(primary$path[[index]]),
      primary$checksum[[index]])) {
    stop("P5 weight checksum failed for cohort ", primary$cohort[[index]])
  }
}

sql_path <- function(path) {
  paste0("'", gsub("'", "''", normalizePath(
    path, winslash = "/", mustWork = TRUE)), "'")
}
weight_list <- paste(
  vapply(primary$path, sql_path, character(1)), collapse = ",")
roster_path <- file.path(output_dir, "p5_p6_primary_weighted_roster.parquet")

con <- DBI::dbConnect(
  duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=4")
DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")
DBI::dbExecute(con, sprintf("
COPY (
  WITH weights AS (
    SELECT * FROM read_parquet([%s])
  ),
  mapped AS (
    SELECT
      CAST(w.deal_id AS BIGINT) AS deal_id,
      CAST(w.cohort AS INTEGER) AS cohort,
      CASE WHEN w.treated = 1 THEN 'treated' ELSE 'control' END AS arm,
      CAST(w.codinv AS BIGINT) AS codinv,
      CAST(w.final_weight AS DOUBLE) AS weight,
      CASE WHEN w.treated = 1 THEN t.status_eligible ELSE TRUE END
        AS status_eligible,
      CAST(CASE WHEN w.treated = 1
        THEN t.target_group ELSE w.control_group END AS BIGINT)
        AS focal_group_1,
      CAST(CASE WHEN w.treated = 1
        THEN t.acquirer_group ELSE NULL END AS BIGINT)
        AS focal_group_2,
      (w.treated = 1) AS use_target_company_path,
      CASE WHEN w.treated = 1 THEN t.qualification_route ELSE NULL END
        AS qualification_route,
      CASE WHEN w.treated = 1
        THEN t.target_to_acquirer_transition_strict ELSE NULL END
        AS target_to_acquirer_transition_strict,
      CASE WHEN w.treated = 1
        THEN t.latest_pre_candidate_group_count ELSE NULL END
        AS latest_pre_candidate_group_count,
      CASE WHEN w.treated = 1
        THEN t.multi_exposure_inventor ELSE NULL END
        AS multi_exposure_inventor,
      CASE WHEN w.treated = 1 THEN t.big_deal ELSE NULL END
        AS big_deal,
      w.roster_row_id
    FROM weights w
    LEFT JOIN lmv2_treated_primary t
      ON w.treated = 1
     AND t.deal_id = w.deal_id
     AND CAST(t.codinv AS DOUBLE) = w.codinv
  )
  SELECT
    deal_id, cohort, arm, codinv,
    roster_row_id,
    weight, status_eligible, focal_group_1, focal_group_2,
    use_target_company_path, qualification_route,
    target_to_acquirer_transition_strict,
    latest_pre_candidate_group_count, multi_exposure_inventor,
    big_deal
  FROM mapped
  ORDER BY cohort, deal_id, arm DESC, codinv, focal_group_1, roster_row_id
) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD, OVERWRITE TRUE)",
  weight_list, gsub("\\\\", "/", roster_path)))

roster_sql <- sprintf(
  "read_parquet('%s')", gsub("\\\\", "/", roster_path))
checks <- data.frame(
  check = c(
    "all_amended_cohorts", "unique_roster_keys",
    "complete_treated_mapping", "treated_weight_one",
    "finite_nonnegative_weights", "cohort_weight_mass_equal",
    "control_membership", "minimum_two_control_firms_per_deal"),
  observed = c(
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(DISTINCT cohort) n FROM %s", roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) - COUNT(DISTINCT
         (cohort,deal_id,arm,codinv,focal_group_1)) n FROM %s",
      roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM %s
       WHERE arm='treated' AND
         (status_eligible IS NULL OR focal_group_1 IS NULL)", roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM %s
       WHERE arm='treated' AND weight <> 1", roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM %s
       WHERE weight IS NULL OR NOT isfinite(weight) OR weight < 0",
      roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT cohort FROM %s GROUP BY cohort
         HAVING ABS(SUM(weight) FILTER (arm='treated') -
                    SUM(weight) FILTER (arm='control')) > 1e-7)",
      roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM %s r
       WHERE r.arm='control' AND NOT EXISTS (
         SELECT 1 FROM lmv2_control_inventor_eligibility c
         WHERE c.cohort=r.cohort AND c.codinv=r.codinv
           AND CAST(c.control_group AS BIGINT)=r.focal_group_1)",
      roster_sql))$n,
    DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT cohort,deal_id FROM %s WHERE arm='control'
         GROUP BY cohort,deal_id
         HAVING COUNT(DISTINCT focal_group_1) < 2)", roster_sql))$n),
  expected = c(length(LMV2_P5_PRODUCTION$cohorts), rep(0, 7)),
  stringsAsFactors = FALSE)
checks$pass <- checks$observed == checks$expected
utils::write.csv(
  checks, file.path(output_dir, "p5_p6_roster_certification.csv"),
  row.names = FALSE)
if (!all(checks$pass)) {
  stop(
    "P5-P6 roster certification failed: ",
    paste(checks$check[!checks$pass], collapse = ", "))
}

roster_rows <- DBI::dbGetQuery(
  con, sprintf("SELECT COUNT(*) n FROM %s", roster_sql))$n[[1]]
source_hash <- lmv2_p3_file_hash(
  file.path(BASE, "R", "20g_build_lmv2_p5_p6_weighted_roster.R"))
design_hash <- digest::digest(
  list(
    production_freeze = LMV2_P5_PRODUCTION_FREEZE_SHA256,
    weight_checksums = primary$checksum,
    handoff_source = source_hash),
  algo = "sha256", serialize = TRUE)
manifest <- data.frame(
  roster_sha256 = lmv2_p3_file_hash(roster_path),
  roster_rows = roster_rows,
  p5a_design_hash = design_hash,
  certification_pass = TRUE,
  production_freeze_hash = LMV2_P5_PRODUCTION_FREEZE_SHA256,
  handoff_source_sha256 = source_hash,
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest, file.path(output_dir, "p5_p6_roster_manifest.csv"),
  row.names = FALSE)
message(
  "P5-P6 weighted roster certified: ", roster_rows,
  " rows | design_hash=", design_hash)

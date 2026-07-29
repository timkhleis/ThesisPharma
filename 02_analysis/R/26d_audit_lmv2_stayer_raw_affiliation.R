# Raw patent-level first-post affiliation audit required before P5b S3.

source(file.path("02_analysis", "R", "26a_lmv2_stayer_config.R"))

config <- lmv2_stayer_config()
dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
duckdb_bin <- Sys.which("duckdb")
if (!nzchar(duckdb_bin)) stop("DuckDB CLI is not on PATH")

treated_path <- file.path(
  config$output_dir, "treated_retention_partition.parquet")
control_path <- file.path(
  config$output_dir, "control_retained_candidates.parquet")
if (!file.exists(treated_path) || !file.exists(control_path)) {
  stop("Run 26_run_lmv2_stayer_s0_s2.R before the raw affiliation audit")
}

audit_path <- file.path(
  config$output_dir, "raw_first_post_affiliation_audit.parquet")
summary_path <- file.path(
  config$output_dir, "raw_first_post_affiliation_summary.csv")
certification_path <- file.path(
  config$output_dir, "raw_first_post_affiliation_certification.csv")
unlink(
  c(audit_path, summary_path, certification_path)[
    file.exists(c(audit_path, summary_path, certification_path))],
  force = TRUE)

sql <- "
ATTACH {{DB}} AS foundation (READ_ONLY);

CREATE TEMP TABLE treated_first_post AS
SELECT *
FROM read_parquet({{TREATED}})
WHERE first_post_year IS NOT NULL;

CREATE TEMP TABLE treated_raw AS
WITH links AS (
  SELECT
    t.retention_window,
    t.cohort,
    t.deal_id,
    t.codinv,
    t.retention_status,
    t.first_post_year,
    t.focal_group_1,
    t.focal_group_2,
    t.target_company_path,
    t.route_disagreement,
    CAST(pcl.id_group AS BIGINT) AS raw_group
  FROM treated_first_post t
  JOIN foundation.patent_inventor pi
    ON CAST(pi.codinv AS BIGINT) = t.codinv
  JOIN foundation.patent_company_link pcl
    ON pcl.appln_id = pi.appln_id
   AND pcl.year = t.first_post_year
), collapsed AS (
  SELECT
    retention_window,
    cohort,
    deal_id,
    codinv,
    retention_status,
    first_post_year,
    focal_group_1,
    focal_group_2,
    MAX(target_company_path::INTEGER)::BOOLEAN AS target_company_path,
    MAX(route_disagreement::INTEGER)::BOOLEAN AS route_disagreement,
    MAX((raw_group IN (focal_group_1, focal_group_2))::INTEGER)::BOOLEAN
      AS raw_focal_group_evidence,
    MAX((
      raw_group IS NOT NULL
      AND raw_group NOT IN (focal_group_1, focal_group_2)
    )::INTEGER)::BOOLEAN AS raw_outside_group_evidence,
    COUNT(DISTINCT raw_group) AS raw_group_count
  FROM links
  GROUP BY 1,2,3,4,5,6,7,8
)
SELECT
  'treated' AS arm,
  *,
  (raw_focal_group_evidence AND raw_outside_group_evidence)
    AS raw_group_mixed,
  (
    (raw_focal_group_evidence OR target_company_path)
    AND raw_outside_group_evidence
  ) AS any_focal_route_mixed,
  (target_company_path AND NOT raw_focal_group_evidence)
    AS target_company_only
FROM collapsed;

CREATE TEMP TABLE control_first_post AS
SELECT *
FROM read_parquet({{CONTROL}});

CREATE TEMP TABLE control_raw AS
WITH links AS (
  SELECT
    c.retention_window,
    c.cohort,
    c.codinv,
    c.control_group,
    c.first_post_year,
    CAST(pcl.id_group AS BIGINT) AS raw_group
  FROM control_first_post c
  JOIN foundation.patent_inventor pi
    ON CAST(pi.codinv AS BIGINT) = c.codinv
  JOIN foundation.patent_company_link pcl
    ON pcl.appln_id = pi.appln_id
   AND pcl.year = c.first_post_year
), collapsed AS (
  SELECT
    retention_window,
    cohort,
    codinv,
    control_group,
    first_post_year,
    MAX((raw_group = control_group)::INTEGER)::BOOLEAN
      AS raw_focal_group_evidence,
    MAX((
      raw_group IS NOT NULL AND raw_group <> control_group
    )::INTEGER)::BOOLEAN AS raw_outside_group_evidence,
    COUNT(DISTINCT raw_group) AS raw_group_count
  FROM links
  GROUP BY 1,2,3,4,5
)
SELECT
  'control' AS arm,
  retention_window,
  cohort,
  NULL::BIGINT AS deal_id,
  codinv,
  'initially_retained' AS retention_status,
  first_post_year,
  control_group AS focal_group_1,
  NULL::BIGINT AS focal_group_2,
  FALSE AS target_company_path,
  FALSE AS route_disagreement,
  raw_focal_group_evidence,
  raw_outside_group_evidence,
  raw_group_count,
  (raw_focal_group_evidence AND raw_outside_group_evidence)
    AS raw_group_mixed,
  (raw_focal_group_evidence AND raw_outside_group_evidence)
    AS any_focal_route_mixed,
  FALSE AS target_company_only
FROM collapsed;

COPY (
  SELECT * FROM treated_raw
  UNION ALL BY NAME
  SELECT * FROM control_raw
  ORDER BY retention_window, arm, cohort, deal_id, codinv
) TO {{AUDIT}} (FORMAT PARQUET, COMPRESSION ZSTD);

COPY (
  SELECT
    arm,
    retention_window,
    retention_status,
    COUNT(*) AS first_post_rows,
    SUM(raw_group_mixed::INTEGER) AS raw_group_mixed_rows,
    SUM(any_focal_route_mixed::INTEGER) AS any_focal_route_mixed_rows,
    SUM(target_company_only::INTEGER) AS target_company_only_rows,
    SUM(route_disagreement::INTEGER) AS route_disagreement_rows,
    SUM((raw_group_count > 1)::INTEGER) AS multi_group_rows,
    SUM(any_focal_route_mixed::INTEGER) * 1.0 / COUNT(*)
      AS any_focal_route_mixed_share
  FROM (
    SELECT * FROM treated_raw
    UNION ALL BY NAME
    SELECT * FROM control_raw
  )
  GROUP BY ALL
  ORDER BY retention_window, arm, retention_status
) TO {{SUMMARY}} (HEADER, DELIMITER ',');

COPY (
  WITH audit AS (
    SELECT * FROM treated_raw
    UNION ALL BY NAME
    SELECT * FROM control_raw
  ), expected AS (
    SELECT 'treated' arm, retention_window, COUNT(*) n
    FROM treated_first_post
    GROUP BY ALL
    UNION ALL
    SELECT 'control' arm, retention_window, COUNT(*) n
    FROM control_first_post
    GROUP BY ALL
  ), observed AS (
    SELECT arm, retention_window, COUNT(*) n
    FROM audit
    GROUP BY ALL
  )
  SELECT
    e.arm,
    e.retention_window,
    e.n AS expected_rows,
    o.n AS observed_rows,
    e.n - o.n AS missing_raw_rows,
    COUNT(*) FILTER (
      WHERE a.raw_group_count IS NULL OR a.raw_group_count < 1
    ) AS invalid_raw_group_rows
  FROM expected e
  JOIN observed o USING (arm, retention_window)
  JOIN audit a USING (arm, retention_window)
  GROUP BY 1,2,3,4,5
  ORDER BY 2,1
) TO {{CERT}} (HEADER, DELIMITER ',');
"

replacements <- c(
  DB = lmv2_sql_string(config$foundation_db),
  TREATED = lmv2_sql_string(treated_path),
  CONTROL = lmv2_sql_string(control_path),
  AUDIT = lmv2_sql_string(audit_path),
  SUMMARY = lmv2_sql_string(summary_path),
  CERT = lmv2_sql_string(certification_path))
for (name in names(replacements)) {
  sql <- gsub(
    paste0("{{", name, "}}"), replacements[[name]],
    sql, fixed = TRUE)
}

sql_file <- tempfile(fileext = ".sql")
on.exit(unlink(sql_file), add = TRUE)
writeLines(sql, sql_file, useBytes = TRUE)
command <- sprintf(
  ".read %s",
  lmv2_sql_string(normalizePath(sql_file, winslash = "/", mustWork = TRUE)))
log <- system2(
  duckdb_bin, c(":memory:", "-c", shQuote(command)),
  stdout = TRUE, stderr = TRUE)
status <- attr(log, "status")
if (!is.null(status) && status != 0L) {
  stop("Raw affiliation audit failed:\n", paste(log, collapse = "\n"))
}

cert <- read.csv(certification_path, stringsAsFactors = FALSE)
if (any(cert$missing_raw_rows != 0) ||
    any(cert$invalid_raw_group_rows != 0)) {
  stop("Raw affiliation audit failed its row-reconciliation gate")
}

summary <- read.csv(summary_path, stringsAsFactors = FALSE)
primary_treated <- summary[
  summary$arm == "treated" &
    summary$retention_window == "t1_t5_primary" &
    summary$retention_status == "initially_retained", ,
  drop = FALSE]
message(sprintf(
  paste0(
    "Raw affiliation audit complete: %d/%d primary retained treated rows ",
    "(%.2f%%) have focal and outside first-post evidence."),
  primary_treated$any_focal_route_mixed_rows,
  primary_treated$first_post_rows,
  100 * primary_treated$any_focal_route_mixed_share))

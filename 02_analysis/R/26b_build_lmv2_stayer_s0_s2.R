# Build P5b S0-S2 treated/control retention interfaces.
#
# The heavy transformations run in the DuckDB CLI so this stage does not
# depend on a locally compiled R duckdb package.

if (!exists("lmv2_stayer_config")) {
  source(file.path("02_analysis", "R", "26a_lmv2_stayer_config.R"))
}

lmv2_build_stayer_s0_s2 <- function(config = lmv2_stayer_config()) {
  dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
  duckdb_bin <- Sys.which("duckdb")
  if (!nzchar(duckdb_bin)) {
    stop("DuckDB CLI is not on PATH")
  }

  artifact_names <- c(
    "treated_retention_partition.parquet",
    "control_retained_candidates.parquet",
    "treated_retention_funnel.csv",
    "control_retention_funnel.csv",
    "treated_retention_power.csv",
    "control_group_continuity_by_firm.csv",
    "control_group_continuity_summary.csv",
    "inventor_affiliation_key_audit.csv",
    "partition_integrity_audit.csv"
  )
  existing_artifacts <- file.path(config$output_dir, artifact_names)
  unlink(existing_artifacts[file.exists(existing_artifacts)], force = TRUE)

  out <- function(name) lmv2_sql_string(file.path(config$output_dir, name))
  db <- lmv2_sql_string(config$foundation_db)
  min_post <- config$continuity$minimum_post_inventors
  modal_outside <- config$continuity$modal_outside_share
  max_same <- config$continuity$maximum_same_group_share

  sql <- "
ATTACH {{FOUNDATION_DB}} AS foundation (READ_ONLY);

CREATE TEMP TABLE stayer_windows AS
SELECT * FROM (VALUES
  ('t1_t5_primary', 1, 5, TRUE),
  ('t2_t5_sensitivity', 2, 5, FALSE)
) AS w(retention_window, first_event_time, last_event_time, is_primary);

CREATE TEMP TABLE treated_base AS
SELECT
  CAST(cohort AS INTEGER) AS cohort,
  CAST(deal_id AS BIGINT) AS deal_id,
  CAST(codinv AS BIGINT) AS codinv,
  CAST(target_group AS BIGINT) AS focal_group_1,
  CAST(acquirer_group AS BIGINT) AS focal_group_2,
  qualification_route,
  target_to_acquirer_transition_strict,
  latest_pre_candidate_group_count
FROM foundation.lmv2_treated_primary
WHERE status_eligible;

CREATE TEMP TABLE treated_window AS
SELECT b.*, w.*
FROM treated_base b
CROSS JOIN stayer_windows w;

CREATE TEMP TABLE treated_first_post AS
SELECT
  tw.retention_window,
  tw.deal_id,
  tw.codinv,
  MIN(a.year) AS first_post_year
FROM treated_window tw
JOIN foundation.inventor_affiliation_own a
  ON CAST(a.codinv AS BIGINT) = tw.codinv
 AND a.year BETWEEN tw.cohort + tw.first_event_time
                AND tw.cohort + tw.last_event_time
GROUP BY 1, 2, 3;

CREATE TEMP TABLE treated_first_post_company AS
SELECT DISTINCT
  fp.retention_window,
  fp.deal_id,
  fp.codinv
FROM treated_first_post fp
JOIN foundation.deal_target_company_strict dtc
  ON dtc.deal_id = fp.deal_id
JOIN foundation.patent_company_link pcl
  ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
 AND pcl.year = fp.first_post_year
JOIN foundation.patent_inventor pi
  ON pi.appln_id = pcl.appln_id
 AND CAST(pi.codinv AS BIGINT) = fp.codinv;

CREATE TEMP TABLE treated_partition AS
WITH evidence AS (
  SELECT
    tw.*,
    fp.first_post_year,
    CAST(a.resolved_group AS BIGINT) AS first_post_group,
    COALESCE(a.affiliation_ambiguous, FALSE) AS affiliation_ambiguous,
    (tc.codinv IS NOT NULL) AS target_company_path,
    COALESCE(
      CAST(a.resolved_group AS BIGINT) IN
        (tw.focal_group_1, tw.focal_group_2),
      FALSE) AS focal_group_path
  FROM treated_window tw
  LEFT JOIN treated_first_post fp
    ON fp.retention_window = tw.retention_window
   AND fp.deal_id = tw.deal_id
   AND fp.codinv = tw.codinv
  LEFT JOIN foundation.inventor_affiliation_own a
    ON CAST(a.codinv AS BIGINT) = tw.codinv
   AND a.year = fp.first_post_year
  LEFT JOIN treated_first_post_company tc
    ON tc.retention_window = tw.retention_window
   AND tc.deal_id = tw.deal_id
   AND tc.codinv = tw.codinv
)
SELECT
  *,
  (focal_group_path OR target_company_path) AS initially_retained,
  (
    target_company_path
    AND first_post_group IS NOT NULL
    AND first_post_group NOT IN (focal_group_1, focal_group_2)
  ) AS route_disagreement,
  CASE
    WHEN first_post_year IS NULL THEN 'no_post_patent'
    WHEN focal_group_path OR target_company_path THEN 'initially_retained'
    WHEN first_post_group IS NULL THEN 'unresolved'
    ELSE 'leaver'
  END AS retention_status
FROM evidence;

CREATE TEMP TABLE control_base AS
SELECT
  CAST(cohort AS INTEGER) AS cohort,
  CAST(codinv AS BIGINT) AS codinv,
  CAST(control_group AS BIGINT) AS control_group,
  latest_pre_affiliation_year,
  qualifying_gap
FROM foundation.lmv2_control_inventor_eligibility
WHERE NOT control_firm_exits_before_g_plus_5;

CREATE TEMP TABLE control_window AS
SELECT b.*, w.*
FROM control_base b
CROSS JOIN stayer_windows w;

CREATE TEMP TABLE control_first_post AS
SELECT
  cw.retention_window,
  cw.cohort,
  cw.codinv,
  cw.control_group,
  MIN(a.year) AS first_post_year
FROM control_window cw
JOIN foundation.inventor_affiliation_own a
  ON CAST(a.codinv AS BIGINT) = cw.codinv
 AND a.year BETWEEN cw.cohort + cw.first_event_time
                AND cw.cohort + cw.last_event_time
GROUP BY 1, 2, 3, 4;

CREATE TEMP TABLE control_partition AS
SELECT
  cw.*,
  fp.first_post_year,
  CAST(a.resolved_group AS BIGINT) AS first_post_group,
  COALESCE(a.affiliation_ambiguous, FALSE) AS affiliation_ambiguous,
  CASE
    WHEN fp.first_post_year IS NULL THEN 'no_post_patent'
    WHEN CAST(a.resolved_group AS BIGINT) = cw.control_group
      THEN 'initially_retained'
    WHEN a.resolved_group IS NULL THEN 'unresolved'
    ELSE 'leaver'
  END AS retention_status
FROM control_window cw
LEFT JOIN control_first_post fp
  ON fp.retention_window = cw.retention_window
 AND fp.cohort = cw.cohort
 AND fp.codinv = cw.codinv
 AND fp.control_group = cw.control_group
LEFT JOIN foundation.inventor_affiliation_own a
  ON CAST(a.codinv AS BIGINT) = cw.codinv
 AND a.year = fp.first_post_year;

COPY (
  SELECT *
  FROM treated_partition
  ORDER BY retention_window, cohort, deal_id, codinv
) TO {{TREATED_PARTITION}} (FORMAT PARQUET, COMPRESSION ZSTD);

COPY (
  SELECT *
  FROM control_partition
  WHERE retention_status = 'initially_retained'
  ORDER BY retention_window, cohort, control_group, codinv
) TO {{CONTROL_CANDIDATES}} (FORMAT PARQUET, COMPRESSION ZSTD);

COPY (
  SELECT
    retention_window,
    is_primary,
    retention_status,
    COUNT(*) AS inventor_deal_rows,
    COUNT(DISTINCT codinv) AS inventors,
    COUNT(DISTINCT deal_id) AS deals,
    SUM(route_disagreement::INTEGER) AS route_disagreements
  FROM treated_partition
  GROUP BY ALL
  ORDER BY retention_window, retention_status
) TO {{TREATED_FUNNEL}} (HEADER, DELIMITER ',');

COPY (
  SELECT
    retention_window,
    is_primary,
    retention_status,
    COUNT(*) AS inventor_cohort_rows,
    COUNT(DISTINCT codinv) AS inventors,
    COUNT(DISTINCT control_group) AS firms
  FROM control_partition
  GROUP BY ALL
  ORDER BY retention_window, retention_status
) TO {{CONTROL_FUNNEL}} (HEADER, DELIMITER ',');

COPY (
  WITH deal_counts AS (
    SELECT retention_window, is_primary, deal_id, COUNT(*) AS n
    FROM treated_partition
    WHERE retention_status = 'initially_retained'
    GROUP BY ALL
  )
  SELECT
    retention_window,
    is_primary,
    SUM(n) AS retained_inventors,
    COUNT(*) AS retained_deals,
    SUM(n) * SUM(n) * 1.0 / SUM(n * n) AS raw_effective_deals,
    MAX(n) AS largest_deal_inventors,
    MAX(n) * 1.0 / SUM(n) AS largest_deal_share
  FROM deal_counts
  GROUP BY retention_window, is_primary
  ORDER BY retention_window
) TO {{TREATED_POWER}} (HEADER, DELIMITER ',');

CREATE TEMP TABLE control_destination_counts AS
SELECT
  retention_window,
  cohort,
  control_group,
  first_post_group AS destination_group,
  COUNT(*) AS n
FROM control_partition
WHERE first_post_year IS NOT NULL
  AND first_post_group IS NOT NULL
GROUP BY ALL;

CREATE TEMP TABLE control_destination_ranked AS
SELECT
  *,
  ROW_NUMBER() OVER (
    PARTITION BY retention_window, cohort, control_group
    ORDER BY n DESC, destination_group
  ) AS destination_rank
FROM control_destination_counts;

CREATE TEMP TABLE control_continuity AS
WITH totals AS (
  SELECT
    retention_window,
    cohort,
    control_group,
    COUNT(*) AS n_eligible,
    COUNT(*) FILTER (WHERE first_post_year IS NOT NULL) AS n_post,
    COUNT(*) FILTER (
      WHERE first_post_year IS NOT NULL
        AND first_post_group = control_group) AS n_same_group,
    COUNT(*) FILTER (
      WHERE first_post_year IS NOT NULL
        AND first_post_group <> control_group) AS n_outside_group
  FROM control_partition
  GROUP BY ALL
)
SELECT
  t.*,
  r.destination_group AS modal_destination_group,
  r.n AS modal_destination_n,
  r.n * 1.0 / NULLIF(t.n_post, 0) AS modal_destination_share_post,
  t.n_same_group * 1.0 / NULLIF(t.n_post, 0) AS same_group_share_post,
  (
    t.n_post >= {{MIN_POST}}
    AND r.destination_group <> t.control_group
    AND r.n * 1.0 / t.n_post >= {{MODAL_OUTSIDE}}
    AND t.n_same_group * 1.0 / t.n_post <= {{MAX_SAME}}
  ) AS suspected_group_id_discontinuity
FROM totals t
LEFT JOIN control_destination_ranked r
  ON r.retention_window = t.retention_window
 AND r.cohort = t.cohort
 AND r.control_group = t.control_group
 AND r.destination_rank = 1;

COPY (
  SELECT *
  FROM control_continuity
  ORDER BY retention_window, suspected_group_id_discontinuity DESC,
           n_post DESC, cohort, control_group
) TO {{CONTINUITY_FIRM}} (HEADER, DELIMITER ',');

COPY (
  SELECT
    retention_window,
    COUNT(*) AS firm_cohorts,
    SUM(suspected_group_id_discontinuity::INTEGER) AS flagged_firm_cohorts,
    SUM(n_post) AS post_inventor_cohort_rows,
    SUM(n_post) FILTER (
      WHERE suspected_group_id_discontinuity) AS affected_post_rows,
    COALESCE(
      SUM(n_post) FILTER (WHERE suspected_group_id_discontinuity) * 1.0
        / NULLIF(SUM(n_post), 0),
      0) AS affected_post_share
  FROM control_continuity
  GROUP BY retention_window
  ORDER BY retention_window
) TO {{CONTINUITY_SUMMARY}} (HEADER, DELIMITER ',');

COPY (
  SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT (CAST(codinv AS VARCHAR) || ':' ||
                    CAST(year AS VARCHAR))) AS distinct_inventor_years,
    COUNT(*) - COUNT(DISTINCT (CAST(codinv AS VARCHAR) || ':' ||
                    CAST(year AS VARCHAR))) AS duplicate_inventor_year_rows
  FROM foundation.inventor_affiliation_own
) TO {{AFFILIATION_KEY_AUDIT}} (HEADER, DELIMITER ',');

COPY (
  SELECT
    'treated' AS arm,
    retention_window,
    COUNT(*) AS rows,
    COUNT(DISTINCT (
      CAST(deal_id AS VARCHAR) || ':' || CAST(codinv AS VARCHAR)
    )) AS distinct_keys,
    COUNT(*) - COUNT(DISTINCT (
      CAST(deal_id AS VARCHAR) || ':' || CAST(codinv AS VARCHAR)
    )) AS duplicate_keys,
    COUNT(*) FILTER (
      WHERE first_post_year IS NOT NULL
        AND first_post_year NOT BETWEEN cohort + first_event_time
                                    AND cohort + last_event_time
    ) AS wrong_timing_rows,
    COUNT(*) FILTER (
      WHERE retention_status NOT IN (
        'initially_retained', 'leaver', 'no_post_patent', 'unresolved')
    ) AS invalid_status_rows,
    COUNT(*) FILTER (
      WHERE retention_status = 'initially_retained'
        AND NOT (focal_group_path OR target_company_path)
    ) AS incoherent_retained_rows
  FROM treated_partition
  GROUP BY retention_window
  UNION ALL
  SELECT
    'control' AS arm,
    retention_window,
    COUNT(*) AS rows,
    COUNT(DISTINCT (
      CAST(cohort AS VARCHAR) || ':' || CAST(codinv AS VARCHAR) || ':' ||
      CAST(control_group AS VARCHAR)
    )) AS distinct_keys,
    COUNT(*) - COUNT(DISTINCT (
      CAST(cohort AS VARCHAR) || ':' || CAST(codinv AS VARCHAR) || ':' ||
      CAST(control_group AS VARCHAR)
    )) AS duplicate_keys,
    COUNT(*) FILTER (
      WHERE first_post_year IS NOT NULL
        AND first_post_year NOT BETWEEN cohort + first_event_time
                                    AND cohort + last_event_time
    ) AS wrong_timing_rows,
    COUNT(*) FILTER (
      WHERE retention_status NOT IN (
        'initially_retained', 'leaver', 'no_post_patent', 'unresolved')
    ) AS invalid_status_rows,
    COUNT(*) FILTER (
      WHERE retention_status = 'initially_retained'
        AND first_post_group <> control_group
    ) AS incoherent_retained_rows
  FROM control_partition
  GROUP BY retention_window
  ORDER BY retention_window, arm
) TO {{PARTITION_INTEGRITY}} (HEADER, DELIMITER ',');
"

  replacements <- c(
    FOUNDATION_DB = db,
    TREATED_PARTITION = out("treated_retention_partition.parquet"),
    CONTROL_CANDIDATES = out("control_retained_candidates.parquet"),
    TREATED_FUNNEL = out("treated_retention_funnel.csv"),
    CONTROL_FUNNEL = out("control_retention_funnel.csv"),
    TREATED_POWER = out("treated_retention_power.csv"),
    MIN_POST = as.character(min_post),
    MODAL_OUTSIDE = formatC(modal_outside, format = "f", digits = 8),
    MAX_SAME = formatC(max_same, format = "f", digits = 8),
    CONTINUITY_FIRM = out("control_group_continuity_by_firm.csv"),
    CONTINUITY_SUMMARY = out("control_group_continuity_summary.csv"),
    AFFILIATION_KEY_AUDIT = out("inventor_affiliation_key_audit.csv"),
    PARTITION_INTEGRITY = out("partition_integrity_audit.csv")
  )
  for (name in names(replacements)) {
    sql <- gsub(
      paste0("{{", name, "}}"), replacements[[name]],
      sql, fixed = TRUE)
  }

  sql_file <- tempfile(fileext = ".sql")
  log_file <- file.path(config$output_dir, "build_s0_s2.log")
  on.exit(unlink(sql_file), add = TRUE)
  writeLines(sql, sql_file, useBytes = TRUE)

  command <- sprintf(
    ".read %s",
    lmv2_sql_string(normalizePath(sql_file, winslash = "/", mustWork = TRUE)))
  log <- system2(
    duckdb_bin,
    c(":memory:", "-c", shQuote(command)),
    stdout = TRUE,
    stderr = TRUE)
  writeLines(log, log_file, useBytes = TRUE)
  status <- attr(log, "status")
  if (!is.null(status) && status != 0L) {
    stop("DuckDB S0-S2 build failed. See ", log_file)
  }

  required <- file.path(config$output_dir, artifact_names)
  missing <- required[!file.exists(required)]
  if (length(missing) > 0L) {
    stop("S0-S2 build did not create:\n", paste(missing, collapse = "\n"))
  }
  invisible(required)
}

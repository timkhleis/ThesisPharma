# Build the outcome-blind initially-outside classification and audits.

if (!exists("lmv2_io_config")) {
  source(file.path("02_analysis", "R",
                   "71a_lmv2_initially_outside_config.R"))
}

lmv2_build_initially_outside_s0_s2 <- function(config = lmv2_io_config()) {
  dir.create(config$s0_dir, recursive = TRUE, showWarnings = FALSE)
  duckdb_bin <- Sys.which("duckdb")
  if (!nzchar(duckdb_bin)) stop("DuckDB CLI is not on PATH")

  out <- function(name) lmv2_io_sql_string(file.path(config$s0_dir, name))
  db <- lmv2_io_sql_string(config$foundation_db)
  p5c <- lmv2_io_sql_string(config$p5c_weight_glob)
  retained <- lmv2_io_sql_string(config$retained_s3_weights)
  has_retained <- file.exists(config$retained_s3_weights)

  sql <- "
ATTACH {{FOUNDATION_DB}} AS foundation (READ_ONLY);

CREATE TEMP TABLE event_grid AS
SELECT * FROM range(-5, 6) AS t(event_time);

CREATE TEMP TABLE treated_base AS
SELECT
  CAST(cohort AS INTEGER) AS cohort,
  CAST(deal_id AS BIGINT) AS deal_id,
  CAST(codinv AS BIGINT) AS codinv,
  CAST(target_group AS BIGINT) AS target_group,
  CAST(acquirer_group AS BIGINT) AS acquirer_group,
  qualification_route,
  target_to_acquirer_transition_strict,
  latest_pre_candidate_group_count,
  NOT regexp_matches(CAST(CAST(acquirer_group AS BIGINT) AS VARCHAR),
                     '^999[0-9]+$') AS acquirer_known_nonplaceholder
FROM foundation.lmv2_treated_primary
WHERE status_eligible AND cohort BETWEEN 1993 AND 2010;

CREATE TEMP TABLE control_base AS
SELECT
  CAST(cohort AS INTEGER) AS cohort,
  CAST(codinv AS BIGINT) AS codinv,
  CAST(control_group AS BIGINT) AS control_group,
  latest_pre_affiliation_year,
  qualifying_gap
FROM foundation.lmv2_control_inventor_eligibility
WHERE NOT control_firm_exits_before_g_plus_5
  AND cohort BETWEEN 1993 AND 2010;

CREATE TEMP TABLE treated_first AS
SELECT b.cohort, b.deal_id, b.codinv, MIN(a.year) AS first_post_year
FROM treated_base b
LEFT JOIN foundation.inventor_affiliation_own a
  ON CAST(a.codinv AS BIGINT) = b.codinv
 AND a.year BETWEEN b.cohort + 1 AND b.cohort + 5
GROUP BY 1,2,3;

CREATE TEMP TABLE control_first AS
SELECT b.cohort, b.codinv, b.control_group,
       MIN(a.year) AS first_post_year
FROM control_base b
LEFT JOIN foundation.inventor_affiliation_own a
  ON CAST(a.codinv AS BIGINT) = b.codinv
 AND a.year BETWEEN b.cohort + 1 AND b.cohort + 5
GROUP BY 1,2,3;

CREATE TEMP TABLE treated_target_company AS
SELECT DISTINCT f.cohort, f.deal_id, f.codinv
FROM treated_first f
JOIN foundation.deal_target_company_strict dtc
  ON dtc.deal_id = f.deal_id
JOIN foundation.patent_company_link pcl
  ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
 AND pcl.year = f.first_post_year
JOIN foundation.patent_inventor pi
  ON pi.appln_id = pcl.appln_id
 AND CAST(pi.codinv AS BIGINT) = f.codinv;

CREATE TEMP TABLE treated_mixed AS
SELECT
  f.cohort, f.deal_id, f.codinv,
  COUNT(*) FILTER (WHERE g.id_group IN (b.target_group, b.acquirer_group)) > 0
    AS any_combined_group,
  COUNT(*) FILTER (WHERE g.id_group NOT IN
                    (b.target_group, b.acquirer_group)) > 0 AS any_outside_group
FROM treated_first f
JOIN treated_base b USING (cohort, deal_id, codinv)
LEFT JOIN foundation.p6.lmv2_inventor_group_patent_year g
  ON g.codinv = f.codinv AND g.year = f.first_post_year
GROUP BY 1,2,3;

CREATE TEMP TABLE control_mixed AS
SELECT
  f.cohort, f.codinv, f.control_group,
  COUNT(*) FILTER (WHERE g.id_group = f.control_group) > 0 AS any_focal_group,
  COUNT(*) FILTER (WHERE g.id_group <> f.control_group) > 0 AS any_outside_group
FROM control_first f
LEFT JOIN foundation.p6.lmv2_inventor_group_patent_year g
  ON g.codinv = f.codinv AND g.year = f.first_post_year
GROUP BY 1,2,3;

CREATE TEMP TABLE treated_partition AS
WITH evidence AS (
  SELECT
    b.*, f.first_post_year,
    CAST(a.resolved_group AS BIGINT) AS first_post_group,
    COALESCE(a.affiliation_ambiguous, FALSE) AS affiliation_ambiguous,
    tc.codinv IS NOT NULL AS target_company_path,
    COALESCE(m.any_combined_group AND m.any_outside_group, FALSE)
      AS mixed_combined_outside
  FROM treated_base b
  LEFT JOIN treated_first f USING (cohort, deal_id, codinv)
  LEFT JOIN foundation.inventor_affiliation_own a
    ON CAST(a.codinv AS BIGINT) = b.codinv AND a.year = f.first_post_year
  LEFT JOIN treated_target_company tc USING (cohort, deal_id, codinv)
  LEFT JOIN treated_mixed m USING (cohort, deal_id, codinv)
)
SELECT
  *,
  target_company_path AND first_post_group IS NOT NULL
    AND first_post_group NOT IN (target_group, acquirer_group)
    AS route_disagreement,
  CASE
    WHEN first_post_year IS NULL THEN 'no_post_patent'
    WHEN first_post_group IS NULL THEN 'unresolved'
    WHEN target_company_path OR
         first_post_group IN (target_group, acquirer_group)
      THEN 'inside_combined_entity'
    ELSE 'initially_outside'
  END AS primary_status,
  first_post_year IS NOT NULL AND first_post_group IS NOT NULL
    AND NOT target_company_path
    AND first_post_group NOT IN (target_group, acquirer_group)
    AND acquirer_known_nonplaceholder AS primary_initially_outside,
  first_post_year IS NOT NULL AND first_post_group IS NOT NULL
    AND NOT target_company_path AND first_post_group <> target_group
    AS target_only_initially_outside
FROM evidence;

CREATE TEMP TABLE control_partition AS
SELECT
  b.*, f.first_post_year,
  CAST(a.resolved_group AS BIGINT) AS first_post_group,
  COALESCE(a.affiliation_ambiguous, FALSE) AS affiliation_ambiguous,
  COALESCE(m.any_focal_group AND m.any_outside_group, FALSE)
    AS mixed_focal_outside,
  CASE
    WHEN f.first_post_year IS NULL THEN 'no_post_patent'
    WHEN a.resolved_group IS NULL THEN 'unresolved'
    WHEN CAST(a.resolved_group AS BIGINT) = b.control_group
      THEN 'inside_original_group'
    ELSE 'initially_outside'
  END AS primary_status,
  f.first_post_year IS NOT NULL AND a.resolved_group IS NOT NULL
    AND CAST(a.resolved_group AS BIGINT) <> b.control_group
    AS primary_initially_outside
FROM control_base b
LEFT JOIN control_first f USING (cohort, codinv, control_group)
LEFT JOIN foundation.inventor_affiliation_own a
  ON CAST(a.codinv AS BIGINT) = b.codinv AND a.year = f.first_post_year
LEFT JOIN control_mixed m USING (cohort, codinv, control_group);

CREATE TEMP TABLE broad_variants AS
SELECT 'treated' AS arm,
       'primary_initially_outside_t1_t5' AS support_variant,
       cohort, deal_id, codinv, target_group AS focal_group,
       primary_status, first_post_year, first_post_group
FROM treated_partition WHERE primary_initially_outside
UNION ALL
SELECT 'control', 'primary_initially_outside_t1_t5',
       cohort, NULL, codinv, control_group,
       primary_status, first_post_year, first_post_group
FROM control_partition WHERE primary_initially_outside
UNION ALL
SELECT 'treated', 'route_consistent_initially_outside_t1_t5',
       cohort, deal_id, codinv, target_group,
       primary_status, first_post_year, first_post_group
FROM treated_partition
WHERE primary_initially_outside AND NOT route_disagreement
UNION ALL
SELECT 'control', 'route_consistent_initially_outside_t1_t5',
       cohort, NULL, codinv, control_group,
       primary_status, first_post_year, first_post_group
FROM control_partition WHERE primary_initially_outside
UNION ALL
SELECT 'treated', 'raw_unmixed_initially_outside_t1_t5',
       cohort, deal_id, codinv, target_group,
       primary_status, first_post_year, first_post_group
FROM treated_partition
WHERE primary_initially_outside AND NOT mixed_combined_outside
UNION ALL
SELECT 'control', 'raw_unmixed_initially_outside_t1_t5',
       cohort, NULL, codinv, control_group,
       primary_status, first_post_year, first_post_group
FROM control_partition
WHERE primary_initially_outside AND NOT mixed_focal_outside
UNION ALL
SELECT 'treated', 'early_initially_outside_t1_t2',
       cohort, deal_id, codinv, target_group,
       primary_status, first_post_year, first_post_group
FROM treated_partition
WHERE primary_initially_outside AND first_post_year <= cohort + 2
UNION ALL
SELECT 'control', 'early_initially_outside_t1_t2',
       cohort, NULL, codinv, control_group,
       primary_status, first_post_year, first_post_group
FROM control_partition
WHERE primary_initially_outside AND first_post_year <= cohort + 2
UNION ALL
SELECT 'treated', 'target_only_initially_outside_t1_t5',
       cohort, deal_id, codinv, target_group,
       primary_status, first_post_year, first_post_group
FROM treated_partition WHERE target_only_initially_outside
UNION ALL
SELECT 'control', 'target_only_initially_outside_t1_t5',
       cohort, NULL, codinv, control_group,
       primary_status, first_post_year, first_post_group
FROM control_partition WHERE primary_initially_outside
UNION ALL
SELECT 'treated', 'censoring_clean_initially_outside_1993_2008',
       cohort, deal_id, codinv, target_group,
       primary_status, first_post_year, first_post_group
FROM treated_partition
WHERE primary_initially_outside AND cohort <= 2008
UNION ALL
SELECT 'control', 'censoring_clean_initially_outside_1993_2008',
       cohort, NULL, codinv, control_group,
       primary_status, first_post_year, first_post_group
FROM control_partition
WHERE primary_initially_outside AND cohort <= 2008;

CREATE TEMP TABLE p5c AS
SELECT * FROM read_parquet({{P5C_GLOB}})
WHERE scheme = 'primary' AND variant = 'count_active';

CREATE TEMP TABLE nested_roster AS
SELECT v.support_variant, p.*,
       v.first_post_year, v.first_post_group
FROM p5c p
JOIN broad_variants v
  ON v.arm = CASE WHEN p.treated = 1 THEN 'treated' ELSE 'control' END
 AND v.cohort = p.cohort
 AND v.codinv = CAST(p.codinv AS BIGINT)
 AND ((p.treated = 1 AND v.deal_id = p.deal_id)
   OR (p.treated = 0 AND v.focal_group = CAST(p.control_group AS BIGINT)));

COPY (SELECT * FROM treated_partition ORDER BY cohort,deal_id,codinv)
TO {{TREATED_PARTITION}} (FORMAT PARQUET, COMPRESSION ZSTD);
COPY (SELECT * FROM control_partition ORDER BY cohort,control_group,codinv)
TO {{CONTROL_PARTITION}} (FORMAT PARQUET, COMPRESSION ZSTD);
COPY (SELECT * FROM broad_variants ORDER BY support_variant,arm,cohort,codinv)
TO {{BROAD_VARIANTS}} (FORMAT PARQUET, COMPRESSION ZSTD);
COPY (SELECT * FROM nested_roster
      ORDER BY support_variant,cohort,treated,deal_id,codinv)
TO {{NESTED_ROSTER}} (FORMAT PARQUET, COMPRESSION ZSTD);

COPY (
  SELECT 'treated' AS arm, primary_status AS status, cohort,
         COUNT(*) AS n_rows, COUNT(DISTINCT codinv) AS inventors,
         COUNT(DISTINCT deal_id) AS focal_entities
  FROM treated_partition GROUP BY ALL
  UNION ALL
  SELECT 'control', primary_status, cohort,
         COUNT(*), COUNT(DISTINCT codinv), COUNT(DISTINCT control_group)
  FROM control_partition GROUP BY ALL
  ORDER BY arm,cohort,status
) TO {{FUNNEL}} (HEADER, DELIMITER ',');

COPY (
  WITH denominators AS (
    SELECT 'treated' arm, cohort, COUNT(*) denominator
    FROM treated_partition GROUP BY ALL
    UNION ALL
    SELECT 'control', cohort, COUNT(*) FROM control_partition GROUP BY ALL
  ), numerators AS (
    SELECT arm,support_variant,cohort,COUNT(*) numerator
    FROM broad_variants GROUP BY ALL
  )
  SELECT n.*, d.denominator,
         n.numerator::DOUBLE / d.denominator AS selection_rate
  FROM numerators n JOIN denominators d USING (arm,cohort)
  ORDER BY support_variant,arm,cohort
) TO {{SELECTION_RATES}} (HEADER, DELIMITER ',');

COPY (
  SELECT 'treated' arm, cohort,
         first_post_year - cohort AS first_post_event_time,
         primary_status AS status, COUNT(*) n_rows
  FROM treated_partition GROUP BY ALL
  UNION ALL
  SELECT 'control', cohort, first_post_year - cohort,
         primary_status, COUNT(*)
  FROM control_partition GROUP BY ALL
  ORDER BY arm,cohort,first_post_event_time,status
) TO {{FIRST_TIMING}} (HEADER, DELIMITER ',');

COPY (
  WITH broad AS (
    SELECT support_variant,arm,cohort,COUNT(*) broad_rows,
           COUNT(DISTINCT codinv) broad_inventors
    FROM broad_variants GROUP BY ALL
  ), nested AS (
    SELECT support_variant,
           CASE WHEN treated=1 THEN 'treated' ELSE 'control' END arm,
           cohort, COUNT(*) nested_rows,
           COUNT(DISTINCT codinv) nested_inventors,
           COUNT(DISTINCT deal_id) nested_deal_stacks
    FROM nested_roster GROUP BY ALL
  )
  SELECT b.*, COALESCE(n.nested_rows,0) nested_rows,
         COALESCE(n.nested_inventors,0) nested_inventors,
         COALESCE(n.nested_deal_stacks,0) nested_deal_stacks,
         COALESCE(n.nested_inventors,0)::DOUBLE / b.broad_inventors
           AS inventor_retention
  FROM broad b LEFT JOIN nested n USING (support_variant,arm,cohort)
  ORDER BY support_variant,arm,cohort
) TO {{NESTING}} (HEADER, DELIMITER ',');

COPY (
  WITH entities AS (
    SELECT DISTINCT 'treated_target' arm_entity, cohort, deal_id focal_id,
                    target_group group_id FROM treated_base
    UNION ALL
    SELECT DISTINCT 'treated_acquirer', cohort, deal_id, acquirer_group
    FROM treated_base
    UNION ALL
    SELECT DISTINCT 'control_focal', cohort, control_group, control_group
    FROM control_base
  ), activity AS (
    SELECT DISTINCT CAST(id_group AS BIGINT) group_id, year
    FROM foundation.group_ipc_year
  )
  SELECT e.arm_entity,e.cohort,g.event_time,e.cohort+g.event_time calendar_year,
         COUNT(*) entity_rows,
         COUNT(*) FILTER (WHERE ys.id_group IS NOT NULL) existence_rows,
         COUNT(*) FILTER (WHERE a.group_id IS NOT NULL) patent_active_rows
  FROM entities e CROSS JOIN event_grid g
  LEFT JOIN foundation.group_year_status ys
    ON CAST(ys.id_group AS BIGINT)=e.group_id
   AND ys.year=e.cohort+g.event_time
  LEFT JOIN activity a
    ON a.group_id=e.group_id AND a.year=e.cohort+g.event_time
  GROUP BY 1,2,3,4 ORDER BY 1,2,3
) TO {{GROUP_EXISTENCE}} (HEADER, DELIMITER ',');

COPY (
  WITH years AS (
    SELECT patent_year calendar_year,COUNT(*) patent_applications
    FROM foundation.patent_application GROUP BY 1
  )
  SELECT c.cohort,e.event_time,c.cohort+e.event_time calendar_year,
         COALESCE(y.patent_applications,0) patent_applications
  FROM (SELECT * FROM range(1993,2011) AS x(cohort)) c
  CROSS JOIN event_grid e
  LEFT JOIN years y ON y.calendar_year=c.cohort+e.event_time
  ORDER BY cohort,event_time
) TO {{CALENDAR_COVERAGE}} (HEADER, DELIMITER ',');

COPY (
  SELECT
    COUNT(*) treated_rows,
    COUNT(DISTINCT deal_id) treated_deals,
    COUNT(*) FILTER (WHERE NOT acquirer_known_nonplaceholder)
      placeholder_rows,
    COUNT(DISTINCT deal_id) FILTER (WHERE NOT acquirer_known_nonplaceholder)
      placeholder_deals,
    COUNT(*) FILTER (WHERE primary_initially_outside)
      primary_outside_rows,
    COUNT(*) FILTER (WHERE target_only_initially_outside)
      target_only_outside_rows,
    COUNT(*) FILTER (WHERE target_only_initially_outside
                       AND NOT primary_initially_outside)
      target_only_additional_rows
  FROM treated_partition
) TO {{PLACEHOLDER}} (HEADER, DELIMITER ',');

COPY (
  SELECT 'treated' arm, COUNT(*) n_rows,
         COUNT(DISTINCT CAST(cohort AS VARCHAR)||':'||CAST(deal_id AS VARCHAR)
                        ||':'||CAST(codinv AS VARCHAR)) distinct_keys,
         COUNT(*) FILTER (WHERE first_post_year IS NOT NULL AND
          first_post_year NOT BETWEEN cohort+1 AND cohort+5) wrong_timing,
         COUNT(*) FILTER (WHERE primary_status='initially_outside'
                           AND NOT primary_initially_outside
                           AND acquirer_known_nonplaceholder) incoherent_status
  FROM treated_partition
  UNION ALL
  SELECT 'control',COUNT(*),
         COUNT(DISTINCT CAST(cohort AS VARCHAR)||':'||CAST(control_group AS VARCHAR)
                        ||':'||CAST(codinv AS VARCHAR)),
         COUNT(*) FILTER (WHERE first_post_year IS NOT NULL AND
          first_post_year NOT BETWEEN cohort+1 AND cohort+5),
         COUNT(*) FILTER (WHERE primary_status='initially_outside'
                           AND NOT primary_initially_outside)
  FROM control_partition
) TO {{INTEGRITY}} (HEADER, DELIMITER ',');
"

  replacements <- c(
    FOUNDATION_DB = db,
    P5C_GLOB = p5c,
    TREATED_PARTITION = out("treated_status_partition.parquet"),
    CONTROL_PARTITION = out("control_status_partition.parquet"),
    BROAD_VARIANTS = out("broad_initially_outside_variants.parquet"),
    NESTED_ROSTER = out("p5c_nested_initially_outside_roster.parquet"),
    FUNNEL = out("classification_funnel.csv"),
    SELECTION_RATES = out("selection_rates.csv"),
    FIRST_TIMING = out("first_post_timing.csv"),
    NESTING = out("p5c_nesting_audit.csv"),
    GROUP_EXISTENCE = out("group_existence_audit.csv"),
    CALENDAR_COVERAGE = out("calendar_coverage.csv"),
    PLACEHOLDER = out("placeholder_target_only_audit.csv"),
    INTEGRITY = out("classification_integrity.csv"))
  for (nm in names(replacements)) {
    sql <- gsub(paste0("{{", nm, "}}"), replacements[[nm]], sql,
                fixed = TRUE)
  }

  sql_file <- tempfile(fileext = ".sql")
  on.exit(unlink(sql_file), add = TRUE)
  writeLines(sql, sql_file, useBytes = TRUE)
  log_file <- file.path(config$s0_dir, "build_s0_s2.log")
  command <- sprintf(
    ".read %s",
    lmv2_io_sql_string(normalizePath(
      sql_file, winslash = "/", mustWork = TRUE)))
  output <- system2(
    duckdb_bin, c(":memory:", "-c", shQuote(command)),
    stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  writeLines(output, log_file, useBytes = TRUE)
  if (!is.null(status) && status != 0L) {
    stop("DuckDB S0-S2 build failed; see ", log_file, "\n",
         paste(tail(output, 30L), collapse = "\n"))
  }

  if (has_retained) {
    command <- paste0(
      "SELECT COUNT(DISTINCT deal_id) AS retained_deals FROM read_parquet(",
      retained, ") WHERE treated=1;")
    retained_count <- system2(duckdb_bin, c("-csv", "-c", shQuote(command)),
                              stdout = TRUE, stderr = TRUE)
    writeLines(retained_count,
               file.path(config$s0_dir, "retained_deal_overlap_source.csv"),
               useBytes = TRUE)
  }
  invisible(config$s0_dir)
}

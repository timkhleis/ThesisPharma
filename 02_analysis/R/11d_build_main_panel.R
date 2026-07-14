# ============================================================================
# 11d_build_main_panel.R -- Main DiD v1: never-target weighted event panel
# ----------------------------------------------------------------------------
# Builds the delta=0 analysis panel for the never-observed-target control arm.
# The authoritative analysis-unit roster is the final Stage-2 weight file from
# 11h; this script never reconstructs control eligibility or renormalizes weights.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))

for (pkg in c("DBI", "duckdb"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({ library(DBI); library(duckdb) })

EVENT_WINDOW_11D <- -5L:5L
REFERENCE_11D <- -1L
POST_PERIODS_11D <- 1L:5L
WEIGHTS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_never_target_weights.parquet")
PANEL_PARQUET_11D <- file.path(DERIVED_PAR, "main_did_v1_panel.parquet")

sql_path <- function(path) gsub("\\\\", "/", path)

banner("11d NEVER-TARGET MAIN PANEL (delta = 0, event window [-5,+5])")

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='10GB'")
dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sql_path(DUCKDB_TMP)))

weights_pq <- sql_path(WEIGHTS_PARQUET)
units_pq <- sql_path(UNITS_PARQUET)
panel_pq <- sql_path(PANEL_PARQUET_11D)

if (!file.exists(WEIGHTS_PARQUET)) stop("Missing Stage-2 weights: ", WEIGHTS_PARQUET)
if (!file.exists(UNITS_PARQUET)) stop("Missing treated metadata units: ", UNITS_PARQUET)

# ---------------------------------------------------------------------------
# Authoritative unit roster and treated metadata checks
# ---------------------------------------------------------------------------
banner("Unit roster validation")

unit_counts <- dbGetQuery(con, sprintf("
  WITH w AS (SELECT * FROM read_parquet('%s'))
  SELECT
    COUNT(*) AS n_rows,
    COUNT(DISTINCT CAST(CAST(codinv AS BIGINT) AS VARCHAR) || '|' || CAST(stack AS VARCHAR)) AS n_unit_keys,
    SUM(CASE WHEN treated = 1 THEN 1 ELSE 0 END) AS n_treated,
    SUM(CASE WHEN treated = 0 THEN 1 ELSE 0 END) AS n_control,
    SUM(CASE WHEN treated = 1 AND ABS(final_weight - 1) > 1e-8 THEN 1 ELSE 0 END) AS n_treated_weight_not_one,
    SUM(CASE WHEN treated = 0 AND (final_weight <= 0 OR NOT isfinite(final_weight)) THEN 1 ELSE 0 END) AS n_bad_control_weight,
    SUM(CASE WHEN final_weight <= 0 OR NOT isfinite(final_weight) THEN 1 ELSE 0 END) AS n_bad_any_weight
  FROM w", weights_pq))
write_audit(unit_counts, "main_panel_unit_roster_check.csv")
print(unit_counts)
if (unit_counts$n_rows != unit_counts$n_unit_keys) stop("Stage-2 weights are not one row per codinv x stack.")
if (unit_counts$n_treated_weight_not_one > 0) stop("Some treated Stage-2 weights differ from 1.")
if (unit_counts$n_bad_control_weight > 0 || unit_counts$n_bad_any_weight > 0) stop("Non-finite or non-positive weights found.")

treated_meta_check <- dbGetQuery(con, sprintf("
  WITH tm AS (
    SELECT CAST(codinv AS BIGINT) AS codinv, CAST(stack AS INTEGER) AS stack,
           COUNT(*) AS n_rows, COUNT(DISTINCT focal_deal_id) AS n_deals
    FROM read_parquet('%s')
    WHERE treated = 1
    GROUP BY 1, 2
  )
  SELECT COUNT(*) AS n_treated_meta_keys,
         SUM(CASE WHEN n_rows <> 1 OR n_deals <> 1 THEN 1 ELSE 0 END) AS n_bad_keys
  FROM tm", units_pq))
write_audit(treated_meta_check, "main_panel_treated_metadata_check.csv")
if (treated_meta_check$n_bad_keys > 0) stop("Treated metadata is not one-to-one by codinv x stack.")

join_check <- dbGetQuery(con, sprintf("
  WITH
  w AS (SELECT CAST(codinv AS BIGINT) AS codinv, CAST(stack AS INTEGER) AS stack, treated
        FROM read_parquet('%s')),
  tm AS (SELECT CAST(codinv AS BIGINT) AS codinv, CAST(stack AS INTEGER) AS stack,
                CAST(focal_deal_id AS BIGINT) AS focal_deal_id
         FROM read_parquet('%s') WHERE treated = 1),
  joined AS (
    SELECT w.*, tm.focal_deal_id
    FROM w LEFT JOIN tm ON w.treated = 1 AND w.codinv = tm.codinv AND w.stack = tm.stack
  ),
  extra_tm AS (
    SELECT COUNT(*) AS n
    FROM tm LEFT JOIN w ON w.treated = 1 AND w.codinv = tm.codinv AND w.stack = tm.stack
    WHERE w.codinv IS NULL
  )
  SELECT
    COUNT(*) AS n_weight_rows,
    SUM(CASE WHEN treated = 1 AND focal_deal_id IS NULL THEN 1 ELSE 0 END) AS n_unmatched_treated,
    (SELECT n FROM extra_tm) AS n_extra_treated_metadata
  FROM joined", weights_pq, units_pq))
write_audit(join_check, "main_panel_weight_metadata_join_check.csv")
print(join_check)
if (join_check$n_unmatched_treated > 0 || join_check$n_extra_treated_metadata > 0)
  stop("Stage-2 weight roster and treated metadata do not join one-to-one.")

# Materialize lightweight temp tables inside DuckDB. These are session-local only.
dbExecute(con, sprintf("
  CREATE TEMP TABLE treated_meta_11d AS
  SELECT CAST(codinv AS BIGINT) AS codinv, CAST(stack AS INTEGER) AS stack,
         CAST(focal_deal_id AS BIGINT) AS focal_deal_id
  FROM read_parquet('%s')
  WHERE treated = 1", units_pq))

dbExecute(con, sprintf("
  CREATE TEMP TABLE analysis_units_11d AS
  SELECT
    CAST(w.codinv AS BIGINT) AS codinv,
    CAST(w.underlying_group_id AS BIGINT) AS underlying_group_id,
    CAST(w.stack AS INTEGER) AS stack,
    CAST(w.treated AS INTEGER) AS treated,
    CAST(w.final_weight AS DOUBLE) AS final_weight,
    CAST(w.n_qualifying_inventors AS INTEGER) AS n_qualifying_inventors,
    tm.focal_deal_id,
    CAST(CAST(w.codinv AS BIGINT) AS VARCHAR) || '|' || CAST(w.stack AS VARCHAR) AS uid_stack,
    'T_deal_' || CAST(tm.focal_deal_id AS VARCHAR) AS cluster_entity
  FROM read_parquet('%s') w
  JOIN treated_meta_11d tm
    ON CAST(w.codinv AS BIGINT) = tm.codinv
   AND CAST(w.stack AS INTEGER) = tm.stack
  WHERE w.treated = 1
  UNION ALL
  SELECT
    CAST(w.codinv AS BIGINT) AS codinv,
    CAST(w.underlying_group_id AS BIGINT) AS underlying_group_id,
    CAST(w.stack AS INTEGER) AS stack,
    CAST(w.treated AS INTEGER) AS treated,
    CAST(w.final_weight AS DOUBLE) AS final_weight,
    CAST(w.n_qualifying_inventors AS INTEGER) AS n_qualifying_inventors,
    CAST(NULL AS BIGINT) AS focal_deal_id,
    CAST(CAST(w.codinv AS BIGINT) AS VARCHAR) || '|' || CAST(w.stack AS VARCHAR) AS uid_stack,
    'C_group_' || CAST(CAST(w.underlying_group_id AS BIGINT) AS VARCHAR) AS cluster_entity
  FROM read_parquet('%s') w
  WHERE w.treated = 0", weights_pq, weights_pq))

cluster_check <- dbGetQuery(con, "
  SELECT
    COUNT(*) AS n_units,
    SUM(CASE WHEN cluster_entity IS NULL OR cluster_entity = '' THEN 1 ELSE 0 END) AS n_missing_cluster_entity,
    SUM(CASE WHEN codinv IS NULL THEN 1 ELSE 0 END) AS n_missing_codinv_cluster,
    SUM(CASE WHEN treated = 1 AND focal_deal_id IS NULL THEN 1 ELSE 0 END) AS n_missing_treated_deal,
    COUNT(DISTINCT cluster_entity) AS n_cluster_entities,
    COUNT(DISTINCT codinv) AS n_codinv_clusters
  FROM analysis_units_11d")
write_audit(cluster_check, "main_panel_cluster_key_check.csv")
print(cluster_check)
if (cluster_check$n_missing_cluster_entity > 0 || cluster_check$n_missing_codinv_cluster > 0 ||
    cluster_check$n_missing_treated_deal > 0)
  stop("Missing clustering variables in analysis unit roster.")

weight_by_stack <- dbGetQuery(con, "
  SELECT stack, treated, COUNT(*) AS n_units, SUM(final_weight) AS total_weight,
         MIN(final_weight) AS min_weight, MAX(final_weight) AS max_weight
  FROM analysis_units_11d
  GROUP BY stack, treated
  ORDER BY stack, treated")
write_audit(weight_by_stack, "main_panel_weight_totals_by_stack.csv")

# ---------------------------------------------------------------------------
# Acquirer exposure audit for never-target controls, using pre-deal acquirer IDs
# ---------------------------------------------------------------------------
banner("Acquirer exposure audit (pre-deal acquirer identity)")

acquirer_audit <- dbGetQuery(con, "
  WITH acq_raw AS (
    SELECT CAST(deal_year AS INTEGER) AS deal_year, CAST(acquirer_group AS BIGINT) AS grp
    FROM cassi_deal_spine
    WHERE deal_year IS NOT NULL AND acquirer_group IS NOT NULL
    UNION ALL
    SELECT CAST(deal_year AS INTEGER) AS deal_year, CAST(acquirer_group_pre AS BIGINT) AS grp
    FROM cassi_deal_spine
    WHERE deal_year IS NOT NULL AND acquirer_group_pre IS NOT NULL
    UNION ALL
    SELECT CAST(s.deal_year AS INTEGER) AS deal_year, CAST(fg.id_group AS BIGINT) AS grp
    FROM cassi_deal_spine s
    JOIN firm_group fg
      ON fg.compcod = s.acquirer_compcod
     AND fg.year = CAST(s.deal_year AS INTEGER) - 1
    WHERE s.deal_year IS NOT NULL AND s.acquirer_compcod IS NOT NULL
  ),
  acq_events AS (
    SELECT DISTINCT deal_year, grp FROM acq_raw WHERE grp IS NOT NULL
  ),
  control_cells AS (
    SELECT DISTINCT stack, underlying_group_id
    FROM analysis_units_11d
    WHERE treated = 0
  ),
  cell_flags AS (
    SELECT
      c.stack, c.underlying_group_id,
      MAX(CASE WHEN a.deal_year = c.stack - 1 THEN 1 ELSE 0 END) AS acq_g_minus_1,
      MAX(CASE WHEN a.deal_year = c.stack THEN 1 ELSE 0 END) AS acq_g,
      MAX(CASE WHEN a.deal_year BETWEEN c.stack + 1 AND c.stack + 3 THEN 1 ELSE 0 END) AS acq_g_plus_1_3,
      MAX(CASE WHEN a.deal_year BETWEEN c.stack + 4 AND c.stack + 5 THEN 1 ELSE 0 END) AS acq_g_plus_4_5,
      MAX(CASE WHEN a.deal_year BETWEEN c.stack - 1 AND c.stack + 5 THEN 1 ELSE 0 END) AS acq_g_minus_1_plus_5
    FROM control_cells c
    LEFT JOIN acq_events a
      ON a.grp = c.underlying_group_id
     AND a.deal_year BETWEEN c.stack - 1 AND c.stack + 5
    GROUP BY c.stack, c.underlying_group_id
  ),
  flags AS (
    SELECT u.codinv, u.stack, u.underlying_group_id, u.final_weight,
           cf.acq_g_minus_1, cf.acq_g, cf.acq_g_plus_1_3,
           cf.acq_g_plus_4_5, cf.acq_g_minus_1_plus_5
    FROM analysis_units_11d u
    JOIN cell_flags cf
      ON cf.stack = u.stack AND cf.underlying_group_id = u.underlying_group_id
    WHERE u.treated = 0
  )
  SELECT exposure_window,
         SUM(flag) AS n_control_units_exposed,
         COUNT(*) AS n_control_units,
         SUM(final_weight * flag) AS exposed_weight,
         SUM(final_weight) AS total_control_weight,
         SUM(final_weight * flag) / SUM(final_weight) AS exposed_weight_share
  FROM (
    SELECT 'g_minus_1' AS exposure_window, acq_g_minus_1 AS flag, final_weight FROM flags
    UNION ALL SELECT 'g', acq_g, final_weight FROM flags
    UNION ALL SELECT 'g_plus_1_to_3', acq_g_plus_1_3, final_weight FROM flags
    UNION ALL SELECT 'g_plus_4_to_5', acq_g_plus_4_5, final_weight FROM flags
    UNION ALL SELECT 'g_minus_1_to_plus_5', acq_g_minus_1_plus_5, final_weight FROM flags
  )
  GROUP BY exposure_window
  ORDER BY CASE exposure_window
    WHEN 'g_minus_1' THEN 1 WHEN 'g' THEN 2 WHEN 'g_plus_1_to_3' THEN 3
    WHEN 'g_plus_4_to_5' THEN 4 ELSE 5 END")
write_audit(acquirer_audit, "main_panel_never_target_acquirer_exposure.csv")
print(acquirer_audit)

# ---------------------------------------------------------------------------
# Deduplicated patent/citation outcome panel
# ---------------------------------------------------------------------------
banner("Writing panel parquet")

max_patent_year <- dbGetQuery(con, "SELECT MAX(patent_year) AS max_patent_year FROM patent_enriched")$max_patent_year
citation_filing_cutoff <- as.integer(max_patent_year) - 5L
citation_stack_cutoff <- citation_filing_cutoff - max(POST_PERIODS_11D)
citation_followup <- data.frame(
  source = "patent_enriched",
  max_patent_year_in_db = as.integer(max_patent_year),
  conservative_filing_cutoff_for_fwd_cits5 = citation_filing_cutoff,
  stack_cutoff_for_full_t_plus_5_followup = citation_stack_cutoff,
  certification_status = "provisional_db_filing_cutoff_no_raw_citing_years"
)
write_audit(citation_followup, "main_panel_citation_followup_cutoff.csv")
print(citation_followup)

copy_sql <- sprintf("
COPY (
  WITH
  event_grid AS (
    SELECT CAST(event_time AS INTEGER) AS event_time
    FROM range(%d, %d) AS r(event_time)
  ),
  patent_rows AS (
    SELECT DISTINCT
      CAST(pi.codinv AS BIGINT) AS codinv,
      CAST(pi.appln_id AS DOUBLE) AS appln_id,
      CAST(pa.patent_year AS INTEGER) AS filing_year
    FROM patent_inventor pi
    JOIN patent_application pa ON pa.appln_id = pi.appln_id
  ),
  patent_enriched_one AS (
    SELECT
      appln_id,
      MAX(CAST(fwd_cits5 AS DOUBLE)) FILTER (WHERE fwd_cits5 IS NOT NULL) AS fwd_cits5,
      COUNT(*) AS n_enriched_rows,
      COUNT(fwd_cits5) AS n_nonmissing_fwd_cits5
    FROM patent_enriched
    GROUP BY appln_id
  ),
  inventor_year_outcomes AS (
    SELECT
      pr.codinv,
      pr.filing_year AS calendar_year,
      COUNT(*) AS n_patents,
      SUM(CASE WHEN pe.n_nonmissing_fwd_cits5 IS NULL OR pe.n_nonmissing_fwd_cits5 = 0 THEN 1 ELSE 0 END) AS n_patents_missing_fwd_cits5,
      SUM(pe.fwd_cits5) AS sum_observed_fwd_cits5
    FROM patent_rows pr
    LEFT JOIN patent_enriched_one pe ON pe.appln_id = pr.appln_id
    GROUP BY pr.codinv, pr.filing_year
  )
  SELECT
    u.codinv,
    u.underlying_group_id,
    u.stack,
    u.treated,
    u.final_weight,
    u.n_qualifying_inventors,
    u.focal_deal_id,
    u.uid_stack,
    u.cluster_entity,
    e.event_time,
    u.stack + e.event_time AS calendar_year,
    CAST(COALESCE(iyo.n_patents, 0) AS DOUBLE) AS patent_count,
    CAST(CASE WHEN COALESCE(iyo.n_patents, 0) > 0 THEN 1 ELSE 0 END AS INTEGER) AS active_patenting,
    CASE
      WHEN iyo.n_patents IS NULL THEN CAST(0 AS DOUBLE)
      WHEN iyo.n_patents_missing_fwd_cits5 = 0 THEN CAST(COALESCE(iyo.sum_observed_fwd_cits5, 0) AS DOUBLE)
      ELSE NULL
    END AS fwd_cits5,
    CAST(COALESCE(iyo.n_patents, 0) AS BIGINT) AS n_patents_for_cites,
    CAST(COALESCE(iyo.n_patents_missing_fwd_cits5, 0) AS BIGINT) AS n_patents_missing_fwd_cits5,
    CASE
      WHEN iyo.n_patents IS NULL THEN TRUE
      WHEN iyo.n_patents_missing_fwd_cits5 = 0 THEN TRUE
      ELSE FALSE
    END AS citation_complete,
    CAST(%d AS INTEGER) AS citation_filing_cutoff_year,
    CAST(u.stack <= %d AS BOOLEAN) AS fwd_cits5_stack_sample
  FROM analysis_units_11d u
  CROSS JOIN event_grid e
  LEFT JOIN inventor_year_outcomes iyo
    ON iyo.codinv = u.codinv
   AND iyo.calendar_year = u.stack + e.event_time
) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  min(EVENT_WINDOW_11D), max(EVENT_WINDOW_11D) + 1L,
  citation_filing_cutoff, citation_stack_cutoff, panel_pq)
dbExecute(con, copy_sql)
message("Wrote panel: ", PANEL_PARQUET_11D)

# ---------------------------------------------------------------------------
# Panel validation and citation coverage audits
# ---------------------------------------------------------------------------
banner("Panel validation")

panel_counts <- dbGetQuery(con, sprintf("
  WITH p AS (SELECT * FROM read_parquet('%s')),
  unit_rows AS (
    SELECT codinv, stack, COUNT(*) AS n_rows
    FROM p GROUP BY codinv, stack
  ),
  dup_keys AS (
    SELECT codinv, stack, event_time, COUNT(*) AS n
    FROM p GROUP BY codinv, stack, event_time HAVING COUNT(*) > 1
  )
  SELECT
    COUNT(*) AS n_panel_rows,
    COUNT(DISTINCT CAST(codinv AS VARCHAR) || '|' || CAST(stack AS VARCHAR)) AS n_units,
    MIN(n_rows) AS min_rows_per_unit,
    MAX(n_rows) AS max_rows_per_unit,
    SUM(CASE WHEN n_rows <> 11 THEN 1 ELSE 0 END) AS n_bad_unit_row_counts,
    (SELECT COUNT(*) FROM dup_keys) AS n_duplicate_panel_keys,
    SUM(CASE WHEN active_patenting <> CAST(patent_count > 0 AS INTEGER) THEN 1 ELSE 0 END) AS n_bad_active_patenting,
    SUM(CASE WHEN cluster_entity IS NULL OR cluster_entity = '' OR codinv IS NULL THEN 1 ELSE 0 END) AS n_missing_cluster_vars
  FROM p
  JOIN unit_rows USING (codinv, stack)", panel_pq))
write_audit(panel_counts, "main_panel_row_validation.csv")
print(panel_counts)
if (panel_counts$min_rows_per_unit != 11 || panel_counts$max_rows_per_unit != 11 ||
    panel_counts$n_bad_unit_row_counts > 0 || panel_counts$n_duplicate_panel_keys > 0 ||
    panel_counts$n_bad_active_patenting > 0 || panel_counts$n_missing_cluster_vars > 0)
  stop("Panel validation failed; inspect main_panel_row_validation.csv.")

citation_coverage <- dbGetQuery(con, sprintf("
  SELECT
    calendar_year, event_time, treated,
    COUNT(*) AS n_rows,
    COUNT(DISTINCT CAST(codinv AS VARCHAR) || '|' || CAST(stack AS VARCHAR)) AS n_units,
    SUM(final_weight) AS weighted_observation_mass,
    SUM(CASE WHEN n_patents_for_cites > 0 THEN 1 ELSE 0 END) AS n_rows_with_patents,
    SUM(CASE WHEN n_patents_for_cites > 0 THEN final_weight ELSE 0 END) AS weighted_patent_row_mass,
    SUM(CASE WHEN n_patents_for_cites > 0 AND fwd_cits5 IS NULL THEN 1 ELSE 0 END) AS n_rows_missing_fwd_cits5,
    SUM(CASE WHEN n_patents_for_cites > 0 AND fwd_cits5 IS NULL THEN final_weight ELSE 0 END) AS weighted_missing_fwd_cits5_mass,
    SUM(n_patents_for_cites) AS n_patents,
    SUM(n_patents_missing_fwd_cits5) AS n_patents_missing_fwd_cits5,
    MIN(CAST(fwd_cits5_stack_sample AS INTEGER)) AS all_rows_in_restricted_citation_stack_sample
  FROM read_parquet('%s')
  GROUP BY calendar_year, event_time, treated
  ORDER BY event_time, calendar_year, treated", panel_pq))
write_audit(citation_coverage, "main_panel_citation_coverage_by_year_event_treated.csv")

citation_sample_by_stack <- dbGetQuery(con, sprintf("
  SELECT stack, fwd_cits5_stack_sample, COUNT(DISTINCT CAST(codinv AS VARCHAR) || '|' || CAST(stack AS VARCHAR)) AS n_units,
         SUM(final_weight) / 11 AS total_unit_weight
  FROM read_parquet('%s')
  GROUP BY stack, fwd_cits5_stack_sample
  ORDER BY stack", panel_pq))
write_audit(citation_sample_by_stack, "main_panel_citation_restricted_stacks.csv")
print(citation_sample_by_stack)

banner("11d DONE")
message("Panel: ", PANEL_PARQUET_11D)

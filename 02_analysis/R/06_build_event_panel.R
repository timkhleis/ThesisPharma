# Build balanced zero-filled event panel for all pre-deal target inventors
#
# Run from project root after 04c:
#   Rscript 02_analysis/R/06_build_event_panel.R
#
# Outputs:
#   DuckDB tables : target_cohort_event_panel, cs2021_estimation_panel,
#                   stayer_attrition_panel
#   Parquet       : 02_analysis/output/parquet/derived/target_cohort_event_panel.parquet
#                   02_analysis/output/parquet/derived/cs2021_estimation_panel.parquet
#                   02_analysis/output/parquet/derived/stayer_attrition_panel.parquet
#   Audit CSVs    : 02_analysis/output/audit/event_panel/
#
# cs2021_estimation_panel also carries a five-state mutually-exclusive annual
# outcome (with_entity / moved_thirdparty / active_unknown_affiliation /
# inactive_silent_gap / career_exited) plus 0/1 indicator columns of the same
# names, for use directly as att_gt() yname. See cs_outcome_prevalence_by_event.csv
# (own-cohort event-time trajectory) and cs_state_by_calendar_year.csv
# (not-yet-treated control-pool composition by calendar year) before deciding
# which states are viable causal outcomes vs. descriptive-only.

BASE         <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB       <- file.path(BASE, "output", "thesis_foundation.duckdb")
DERIVED_PAR  <- file.path(BASE, "output", "parquet", "derived")
AUDIT        <- file.path(BASE, "output", "audit", "event_panel")

source(file.path(BASE, "R", "00_utils.R"))
load_packages()
library(duckdb)

dir.create(DERIVED_PAR, recursive = TRUE, showWarnings = FALSE)
dir.create(AUDIT,       recursive = TRUE, showWarnings = FALSE)

banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")

copy_to_parquet <- function(con, table_name, parquet_dir) {
  parquet_file <- file.path(parquet_dir, paste0(table_name, ".parquet"))
  parquet_sql  <- gsub("\\\\", "/", parquet_file)
  DBI::dbExecute(
    con,
    sprintf(
      "COPY %s TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
      DBI::dbQuoteIdentifier(con, table_name),
      parquet_sql
    )
  )
  parquet_file
}

write_csv_base <- function(df, filename) {
  utils::write.csv(df, file.path(AUDIT, filename), row.names = FALSE, na = "")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB)
on.exit({ DBI::dbDisconnect(con, shutdown = TRUE) }, add = TRUE)

# Enforce RAM limits to prevent OOM on 32GB machines during heavy cross-joins
DBI::dbExecute(con, "PRAGMA memory_limit='8GB'")
DBI::dbExecute(con, "PRAGMA threads=4") # Adjust based on your CPU cores
tmp_dir <- file.path(BASE, "output", "duckdb_tmp")
dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf("PRAGMA temp_directory='%s'", gsub("\\\\", "/", tmp_dir)))

banner("EVENT PANEL BUILD")

required_tables <- c(
  "target_cohort_own",
  "inventor_status_own",
  "inventor_year",
  "inventor_affiliation_own"
)
missing_tables  <- required_tables[
  !vapply(required_tables, DBI::dbExistsTable, logical(1), conn = con)
]
if (length(missing_tables) > 0) {
  stop(
    "Missing required DuckDB tables: ", paste(missing_tables, collapse = ", "),
    "\n  target_cohort_own / inventor_status_own <- run 04c_build_prelim_own_status.R",
    "\n  inventor_year          <- run 02_build_derived_tables.R",
    "\n  inventor_affiliation_own <- run 04a_build_inventor_affiliation.R"
  )
}

# ── 1. Full-cohort balanced event panel ──────────────────────────────────────
section("Building target_cohort_event_panel")

DBI::dbExecute(con, "
CREATE OR REPLACE TABLE target_cohort_event_panel AS
WITH

-- Clean sample: 1993-2010 ensures full 5-year pre- and post-windows within panel
cohort AS (
  SELECT
    t.codinv,
    t.deal_id,
    t.cassi_deal_group_id,
    t.dealnumber,
    t.deal_year,
    t.deal_value,
    t.target_group,
    t.acquirer_group,
    t.acquirer_group_source,
    t.big_deal,
    t.target_assignment_rule,
    t.n_candidate_exposures,
    t.multi_exposure_inventor,
    CASE WHEN s.codinv IS NOT NULL THEN TRUE ELSE FALSE END AS status_available,
    s.type,
    COALESCE(s.retained_conservative, FALSE) AS retained_conservative,
    COALESCE(s.retained_expanded, FALSE) AS retained_expanded,
    COALESCE(s.persistent_stayer_2, FALSE) AS persistent_stayer_2,
    COALESCE(s.persistent_stayer_3, FALSE) AS persistent_stayer_3,
    COALESCE(s.persistent_stayer_5, FALSE) AS persistent_stayer_5,
    COALESCE(s.patent_active_survivor_2, FALSE) AS patent_active_survivor_2,
    COALESCE(s.patent_active_survivor_3, FALSE) AS patent_active_survivor_3,
    COALESCE(s.patent_active_survivor_5, FALSE) AS patent_active_survivor_5,
    COALESCE(s.career_exit_before_2, FALSE) AS career_exit_before_2,
    COALESCE(s.career_exit_before_3, FALSE) AS career_exit_before_3,
    COALESCE(s.career_exit_before_5, FALSE) AS career_exit_before_5,
    s.career_end_year
  FROM target_cohort_own t
  LEFT JOIN inventor_status_own s
    ON t.codinv = s.codinv
   AND t.deal_id = s.deal_id
  WHERE t.deal_year BETWEEN 1993 AND 2010
),

event_grid AS (
  SELECT -5 AS event_time UNION ALL SELECT -4 UNION ALL SELECT -3
  UNION ALL SELECT -2 UNION ALL SELECT -1 UNION ALL SELECT  0
  UNION ALL SELECT  1 UNION ALL SELECT  2 UNION ALL SELECT  3
  UNION ALL SELECT  4 UNION ALL SELECT  5
),

-- Guard against duplicate codinv-year rows in inventor_year
inventor_year_one AS (
  SELECT
    codinv,
    year,
    MAX(patent_count)            AS patent_count,
    MAX(fractional_patent_count) AS fractional_patent_count
  FROM inventor_year
  GROUP BY codinv, year
),

panel AS (
  SELECT
    c.codinv,
    c.deal_id,
    c.cassi_deal_group_id,
    c.dealnumber,
    c.deal_year,
    c.deal_value,
    c.target_group,
    c.acquirer_group,
    c.acquirer_group_source,
    c.big_deal,
    CASE WHEN c.big_deal THEN 'Big deals' ELSE 'Small deals' END AS deal_size_group,
    c.target_assignment_rule,
    c.n_candidate_exposures,
    c.multi_exposure_inventor,
    c.status_available,
    c.type,
    c.retained_conservative,
    c.retained_expanded,
    c.persistent_stayer_2,
    c.persistent_stayer_3,
    c.persistent_stayer_5,
    c.patent_active_survivor_2,
    c.patent_active_survivor_3,
    c.patent_active_survivor_5,
    c.career_exit_before_2,
    c.career_exit_before_3,
    c.career_exit_before_5,
    c.career_end_year,
    eg.event_time,
    c.deal_year + eg.event_time AS calendar_year
  FROM cohort c
  CROSS JOIN event_grid eg
)

SELECT
  p.*,
  COALESCE(iy.patent_count,            0)     AS patent_count,
  COALESCE(iy.fractional_patent_count, 0)     AS fractional_patent_count,
  CASE WHEN iy.codinv IS NULL THEN TRUE ELSE FALSE END AS zero_filled_row
FROM panel p
LEFT JOIN inventor_year_one iy
  ON p.codinv       = iy.codinv
 AND p.calendar_year = iy.year
")

panel_path <- copy_to_parquet(con, "target_cohort_event_panel", DERIVED_PAR)
message("Written: ", panel_path)

section("Building cs2021_estimation_panel")

DBI::dbExecute(con, "
CREATE OR REPLACE TABLE cs2021_estimation_panel AS
WITH cohort AS (
  SELECT
    t.codinv,
    t.deal_id,
    t.dealnumber,
    CAST(t.deal_year AS INTEGER) AS deal_year,
    t.deal_value,
    t.big_deal,
    t.target_group,
    t.acquirer_group,
    t.acquirer_group_source,
    t.target_assignment_rule,
    t.n_candidate_exposures,
    t.multi_exposure_inventor,
    CASE WHEN s.codinv IS NOT NULL THEN TRUE ELSE FALSE END AS status_available,
    -- narrow cohort window flag: last pre-deal patent >= deal_year-3 (robustness spec)
    CASE WHEN t.last_pre_affiliation_year >= t.deal_year - 3
         THEN TRUE ELSE FALSE END AS in_narrow_cohort_window,
    s.type,
    COALESCE(s.retained_conservative, FALSE) AS retained_conservative,
    COALESCE(s.retained_expanded, FALSE) AS retained_expanded,
    COALESCE(s.persistent_stayer_2, FALSE) AS persistent_stayer_2,
    COALESCE(s.persistent_stayer_3, FALSE) AS persistent_stayer_3,
    COALESCE(s.persistent_stayer_5, FALSE) AS persistent_stayer_5,
    COALESCE(s.patent_active_survivor_2, FALSE) AS patent_active_survivor_2,
    COALESCE(s.patent_active_survivor_3, FALSE) AS patent_active_survivor_3,
    COALESCE(s.patent_active_survivor_5, FALSE) AS patent_active_survivor_5,
    COALESCE(s.career_exit_before_2, FALSE) AS career_exit_before_2,
    COALESCE(s.career_exit_before_3, FALSE) AS career_exit_before_3,
    COALESCE(s.career_exit_before_5, FALSE) AS career_exit_before_5,
    s.career_end_year AS status_career_end_year
  FROM target_cohort_own t
  LEFT JOIN inventor_status_own s
    ON t.codinv = s.codinv
   AND t.deal_id = s.deal_id
  WHERE t.deal_year BETWEEN 1993 AND 2015
),
calendar_grid AS (
  SELECT CAST(calendar_year AS INTEGER) AS calendar_year
  FROM range(1988, 2016) years(calendar_year)
),
inventor_year_one AS (
  SELECT
    CAST(codinv AS BIGINT) AS codinv,
    CAST(year AS INTEGER) AS calendar_year,
    MAX(patent_count) AS patent_count,
    MAX(fractional_patent_count) AS fractional_patent_count
  FROM inventor_year
  WHERE year BETWEEN 1988 AND 2015
  GROUP BY codinv, year
),
inventor_career AS (
  SELECT
    CAST(codinv AS BIGINT) AS codinv,
    MIN(year) FILTER (WHERE patent_count > 0) AS career_first_year,
    MAX(year) FILTER (WHERE patent_count > 0) AS career_end_year
  FROM inventor_year
  GROUP BY codinv
),
predeal_productivity AS (
  SELECT
    c.codinv,
    c.deal_id,
    COALESCE(SUM(iy.patent_count), 0) AS predeal_patent_stock_5y,
    COUNT(DISTINCT iy.year) FILTER (WHERE iy.patent_count > 0) / 5.0
      AS predeal_active_rate_5y
  FROM cohort c
  LEFT JOIN inventor_year iy
    ON CAST(iy.codinv AS BIGINT) = c.codinv
   AND iy.year BETWEEN c.deal_year - 5 AND c.deal_year - 1
  GROUP BY c.codinv, c.deal_id
),
target_patent_history AS (
  SELECT
    c.codinv,
    c.deal_id,
    MIN(ia.year) FILTER (
      WHERE ia.resolved_group = c.target_group
         OR COALESCE(
              list_contains(
                string_split(ia.candidate_group_list, ';'),
                CAST(CAST(c.target_group AS BIGINT) AS VARCHAR)
              ),
              FALSE
            )
    ) AS first_target_patent_year,
    COUNT(DISTINCT ia.year) FILTER (
      WHERE ia.resolved_group = c.target_group
         OR COALESCE(
              list_contains(
                string_split(ia.candidate_group_list, ';'),
                CAST(CAST(c.target_group AS BIGINT) AS VARCHAR)
              ),
              FALSE
            )
    ) AS target_patenting_years_predeal
  FROM cohort c
  LEFT JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = c.codinv
   AND ia.year < c.deal_year
  GROUP BY c.codinv, c.deal_id
),
merged_entity_history AS (
  SELECT
    c.codinv,
    c.deal_id,
    MAX(ia.year) FILTER (
      WHERE ia.resolved_group = c.target_group
         OR COALESCE(
              list_contains(
                string_split(ia.candidate_group_list, ';'),
                CAST(CAST(c.target_group AS BIGINT) AS VARCHAR)
              ),
              FALSE
            )
         OR (
              c.status_available
          AND (
                ia.resolved_group = c.acquirer_group
             OR COALESCE(
                  list_contains(
                    string_split(ia.candidate_group_list, ';'),
                    CAST(CAST(c.acquirer_group AS BIGINT) AS VARCHAR)
                  ),
                  FALSE
                )
          )
         )
    ) AS last_merged_entity_patent_year
  FROM cohort c
  LEFT JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = c.codinv
  GROUP BY c.codinv, c.deal_id
),
outside_after_merged AS (
  SELECT
    c.codinv,
    c.deal_id,
    MIN(ia.year) AS first_known_outside_after_merged_year
  FROM cohort c
  JOIN merged_entity_history mh
    ON c.codinv = mh.codinv
   AND c.deal_id = mh.deal_id
  JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = c.codinv
   AND ia.year > mh.last_merged_entity_patent_year
  WHERE c.status_available
    AND ia.resolved_group IS NOT NULL
    AND CAST(ia.resolved_group AS VARCHAR) NOT LIKE '999%'
    AND ia.resolved_group <> c.target_group
    AND ia.resolved_group <> c.acquirer_group
  GROUP BY c.codinv, c.deal_id
),
-- Pre-deal cohort size per deal: count of inventors in the estimation sample
-- itself (target_cohort_own), used as a lean, predetermined group-size xformla
-- covariate (log_group_size). Deliberately the cohort headcount, not a broader
-- firm-size measure from group_ipc_year/inventor_group_year.
deal_predeal_size AS (
  SELECT deal_id, COUNT(DISTINCT codinv) AS n_predeal_inventors
  FROM target_cohort_own
  GROUP BY deal_id
),
-- Modal pre-deal IPC section (1-char: A/B/C/D/E/F/G/H) per inventor-deal, over
-- the same deal_year-5..deal_year-1 window used elsewhere for pre-deal covariates.
-- Section level (not subclass/main-group) is used deliberately: subclass level
-- has 630 distinct codes in this data (too sparse for a categorical covariate
-- feeding a per-group-time propensity model on ~450 deals); section level has
-- 8 codes with genuine cross-sectional variation (C and A each ~5.4M rows,
-- G/H ~2.2M, B ~1.4M, F/D/E smaller). DealSim's own similarity vectors continue
-- to use finer IPC granularity; this is a coarser xformla covariate only.
predeal_ipc_section AS (
  SELECT
    c.codinv,
    c.deal_id,
    SUBSTR(iy.ipc_code, 1, 1) AS ipc_section,
    SUM(iy.patent_count) AS section_patent_count
  FROM cohort c
  LEFT JOIN inventor_ipc_year iy
    ON CAST(iy.codinv AS BIGINT) = c.codinv
   AND iy.year BETWEEN c.deal_year - 5 AND c.deal_year - 1
  WHERE iy.ipc_code IS NOT NULL
  GROUP BY c.codinv, c.deal_id, SUBSTR(iy.ipc_code, 1, 1)
),
predeal_ipc_primary AS (
  SELECT codinv, deal_id, ipc_section AS ipc_primary_field
  FROM (
    SELECT
      codinv, deal_id, ipc_section,
      ROW_NUMBER() OVER (
        PARTITION BY codinv, deal_id
        ORDER BY section_patent_count DESC, ipc_section ASC
      ) AS rn
    FROM predeal_ipc_section
  )
  WHERE rn = 1
),
cohort_enriched AS (
  SELECT
    c.*,
    ic.career_first_year,
    ic.career_end_year,
    pp.predeal_patent_stock_5y,
    pp.predeal_active_rate_5y,
    c.deal_year - ic.career_first_year AS career_age_at_deal,
    POWER(c.deal_year - ic.career_first_year, 2) AS career_age_sq_at_deal,
    c.deal_year - tph.first_target_patent_year AS observed_target_patent_tenure,
    tph.target_patenting_years_predeal,
    LN(1 + pp.predeal_patent_stock_5y) AS log_predeal_patent_stock,
    LN(1 + c.deal_year - ic.career_first_year) AS log_career_age_at_deal,
    LN(1 + c.deal_year - tph.first_target_patent_year)
      AS log_observed_target_patent_tenure,
    LN(1 + c.deal_value) AS log_deal_value,
    dps.n_predeal_inventors,
    LN(1 + dps.n_predeal_inventors) AS log_group_size,
    COALESCE(pip.ipc_primary_field, 'UNKNOWN') AS ipc_primary_field,
    mh.last_merged_entity_patent_year,
    oam.first_known_outside_after_merged_year
  FROM cohort c
  LEFT JOIN inventor_career ic
    ON c.codinv = ic.codinv
  LEFT JOIN predeal_productivity pp
    ON c.codinv = pp.codinv
   AND c.deal_id = pp.deal_id
  LEFT JOIN target_patent_history tph
    ON c.codinv = tph.codinv
   AND c.deal_id = tph.deal_id
  LEFT JOIN merged_entity_history mh
    ON c.codinv = mh.codinv
   AND c.deal_id = mh.deal_id
  LEFT JOIN outside_after_merged oam
    ON c.codinv = oam.codinv
   AND c.deal_id = oam.deal_id
  LEFT JOIN deal_predeal_size dps
    ON c.deal_id = dps.deal_id
  LEFT JOIN predeal_ipc_primary pip
    ON c.codinv = pip.codinv
   AND c.deal_id = pip.deal_id
),
panel_base AS (
  SELECT
    c.*,
    y.calendar_year,
    y.calendar_year - c.deal_year AS event_time,
    COALESCE(iy.patent_count, 0) AS patent_count,
    COALESCE(iy.fractional_patent_count, 0) AS fractional_patent_count,
    CASE WHEN COALESCE(iy.patent_count, 0) > 0 THEN 1 ELSE 0 END AS active_patenting,
    LN(1 + COALESCE(iy.patent_count, 0)) AS log_patent_count,
    -- rd_activity: absorbing survival (Verginer: file at least one patent on or after year t).
    -- Read from career_end_year; no event-time override.
    CASE
      WHEN c.career_end_year >= y.calendar_year THEN 1
      ELSE                                           0
    END AS rd_activity,
    -- left_this_year: contemporaneous flow (Verginer: No Longer Active). Equals 1 only
    -- in the year after the inventor's last entity filing. Non-absorbing, testable pre-trend.
    CASE
      WHEN NOT c.status_available THEN NULL
      WHEN c.last_merged_entity_patent_year = y.calendar_year - 1 THEN 1
      ELSE 0
    END AS left_this_year,
    CASE
      WHEN NOT c.status_available THEN NULL
      WHEN c.first_known_outside_after_merged_year IS NOT NULL
       AND y.calendar_year >= c.first_known_outside_after_merged_year THEN 1
      ELSE 0
    END AS known_outside_switch,
    CASE WHEN iy.codinv IS NULL THEN TRUE ELSE FALSE END AS zero_filled_row,
    ia.resolved_group AS annual_resolved_group,
    ia.candidate_group_list AS annual_candidate_group_list
  FROM cohort_enriched c
  CROSS JOIN calendar_grid y
  LEFT JOIN inventor_year_one iy
    ON c.codinv = iy.codinv
   AND y.calendar_year = iy.calendar_year
  LEFT JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = c.codinv
   AND ia.year = y.calendar_year
),
-- Five mutually-exclusive annual states (priority order below == precedence):
--   1. with_entity                : resolved (or candidate-list) affiliation is target OR acquirer group
--   2. moved_thirdparty           : resolved affiliation is a KNOWN outside group (not target/acquirer,
--                                   not a 999xxxx placeholder acquirer)
--   3. active_unknown_affiliation : patented this year but affiliation unresolved/placeholder
--   4. inactive_silent_gap        : no patent this year, but career has not yet ended (will patent again)
--   5. career_exited              : no patent this year, and career_end_year has already passed
-- Reuses the same target/acquirer-group matching logic as merged_entity_history above.
state_labeled AS (
  SELECT
    p.*,
    CASE
      WHEN p.annual_resolved_group = p.target_group
        OR COALESCE(
             list_contains(
               string_split(p.annual_candidate_group_list, ';'),
               CAST(CAST(p.target_group AS BIGINT) AS VARCHAR)
             ),
             FALSE
           )
        THEN 'with_entity'
      WHEN p.status_available AND (
           p.annual_resolved_group = p.acquirer_group
        OR COALESCE(
             list_contains(
               string_split(p.annual_candidate_group_list, ';'),
               CAST(CAST(p.acquirer_group AS BIGINT) AS VARCHAR)
             ),
             FALSE
           ))
        THEN 'with_entity'
      WHEN p.annual_resolved_group IS NOT NULL
       AND CAST(p.annual_resolved_group AS VARCHAR) NOT LIKE '999%'
       AND p.annual_resolved_group <> p.target_group
       AND (NOT p.status_available OR p.annual_resolved_group <> p.acquirer_group)
        THEN 'moved_thirdparty'
      WHEN p.patent_count > 0
        THEN 'active_unknown_affiliation'
      WHEN p.rd_activity = 1
        THEN 'inactive_silent_gap'
      ELSE 'career_exited'
    END AS inventor_annual_state
  FROM panel_base p
)
SELECT
  s.*,
  CASE WHEN s.inventor_annual_state = 'with_entity'                THEN 1 ELSE 0 END AS with_entity,
  CASE WHEN s.inventor_annual_state = 'moved_thirdparty'           THEN 1 ELSE 0 END AS moved_thirdparty,
  CASE WHEN s.inventor_annual_state = 'active_unknown_affiliation' THEN 1 ELSE 0 END AS active_unknown_affiliation,
  CASE WHEN s.inventor_annual_state = 'inactive_silent_gap'        THEN 1 ELSE 0 END AS inactive_silent_gap,
  CASE WHEN s.inventor_annual_state = 'career_exited'               THEN 1 ELSE 0 END AS career_exited
FROM state_labeled s
")

cs_path <- copy_to_parquet(con, "cs2021_estimation_panel", DERIVED_PAR)
message("Written: ", cs_path)

# ── 2. Stayer attrition panel ────────────────────────────────────────────────
section("Building stayer_attrition_panel")

# Attrition state logic (mutually exclusive, ordered by priority):
#   1. active_with_acquirer : resolved_group is acquirer OR target (target now owned by acquirer;
#                             target-group post-deal patents are assignee-name lag / subsidiary)
#   2. outside_departure    : known outside group patent (not acquirer, not target, not placeholder)
#   3. career_exit          : career_end_year has passed by this event year
#   4. silent_gap           : no patent observed, career still ongoing
DBI::dbExecute(con, "
CREATE OR REPLACE TABLE stayer_attrition_panel AS
WITH

stayed AS (
  SELECT
    codinv,
    cassi_deal_group_id,
    deal_year,
    target_group,
    acquirer_group,
    career_end_year
  FROM inventor_status_own
  WHERE type = 'T_Ever_Stayed'
    AND deal_year BETWEEN 1993 AND 2010
),

post_grid AS (
  SELECT 0 AS event_time UNION ALL SELECT 1 UNION ALL SELECT 2
  UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
),

stayer_post AS (
  SELECT
    s.codinv,
    s.cassi_deal_group_id,
    s.deal_year,
    s.target_group,
    s.acquirer_group,
    s.career_end_year,
    pg.event_time,
    s.deal_year + pg.event_time AS calendar_year
  FROM stayed s
  CROSS JOIN post_grid pg
)

SELECT
  sp.codinv,
  sp.cassi_deal_group_id,
  sp.deal_year,
  sp.event_time,
  sp.calendar_year,
  ia.resolved_group,
  CASE
    WHEN ia.resolved_group = sp.acquirer_group
      OR ia.resolved_group = sp.target_group
      THEN 'active_with_acquirer'
    WHEN ia.resolved_group IS NOT NULL
     AND CAST(ia.resolved_group AS VARCHAR) NOT LIKE '999%'
     AND ia.resolved_group <> sp.acquirer_group
     AND ia.resolved_group <> sp.target_group
      THEN 'outside_departure'
    WHEN sp.career_end_year <= sp.calendar_year
      THEN 'career_exit'
    ELSE
      'silent_gap'
  END AS attrition_state
FROM stayer_post sp
LEFT JOIN inventor_affiliation_own ia
  ON ia.codinv = sp.codinv
 AND ia.year   = sp.calendar_year
")

attrition_path <- copy_to_parquet(con, "stayer_attrition_panel", DERIVED_PAR)
message("Written: ", attrition_path)

# ── 3. Audit outputs ─────────────────────────────────────────────────────────
section("Writing audit outputs")

event_panel_counts <- DBI::dbGetQuery(con, "
SELECT
  type,
  event_time,
  COUNT(*)              AS n_rows,
  COUNT(DISTINCT codinv) AS n_inventors,
  COUNT(DISTINCT cassi_deal_group_id) AS n_deals
FROM target_cohort_event_panel
GROUP BY type, event_time
ORDER BY type, event_time
")

zero_fill_by_event <- DBI::dbGetQuery(con, "
SELECT
  event_time,
  COUNT(*)  AS n_rows,
  COUNT(DISTINCT codinv) AS n_inventors,
  AVG(CASE WHEN zero_filled_row THEN 1.0 ELSE 0.0 END) AS share_zero_filled
FROM target_cohort_event_panel
GROUP BY event_time
ORDER BY event_time
")

panel_dimension_checks <- DBI::dbGetQuery(con, "
SELECT
  'target_cohort_event_panel' AS panel,
  COUNT(*) AS n_rows,
  COUNT(DISTINCT codinv) AS n_inventors,
  COUNT(DISTINCT CAST(codinv AS VARCHAR) || '|' || CAST(calendar_year AS VARCHAR)) AS n_id_year,
  COUNT(DISTINCT codinv) * 11 AS expected_rows
FROM target_cohort_event_panel
UNION ALL
SELECT
  'cs2021_estimation_panel' AS panel,
  COUNT(*) AS n_rows,
  COUNT(DISTINCT codinv) AS n_inventors,
  COUNT(DISTINCT CAST(codinv AS VARCHAR) || '|' || CAST(calendar_year AS VARCHAR)) AS n_id_year,
  COUNT(DISTINCT codinv) * 28 AS expected_rows
FROM cs2021_estimation_panel
UNION ALL
SELECT
  'stayer_attrition_panel' AS panel,
  COUNT(*) AS n_rows,
  COUNT(DISTINCT codinv) AS n_inventors,
  COUNT(DISTINCT CAST(codinv AS VARCHAR) || '|' || CAST(calendar_year AS VARCHAR)) AS n_id_year,
  COUNT(DISTINCT codinv) * 6 AS expected_rows
FROM stayer_attrition_panel
")

cs_cohort_support <- DBI::dbGetQuery(con, "
SELECT
  deal_year,
  COUNT(DISTINCT codinv) AS n_inventors,
  COUNT(DISTINCT deal_id) AS n_deals,
  MIN(calendar_year) AS min_calendar_year,
  MAX(calendar_year) AS max_calendar_year
FROM cs2021_estimation_panel
GROUP BY deal_year
ORDER BY deal_year
")

cs_covariate_audit <- DBI::dbGetQuery(con, "
WITH unit AS (
  SELECT DISTINCT
    codinv,
    deal_id,
    predeal_patent_stock_5y,
    predeal_active_rate_5y,
    career_age_at_deal,
    career_age_sq_at_deal,
    observed_target_patent_tenure,
    target_patenting_years_predeal,
    deal_value,
    n_predeal_inventors
  FROM cs2021_estimation_panel
),
long AS (
  SELECT codinv, deal_id, 'predeal_patent_stock_5y' AS variable,
         CAST(predeal_patent_stock_5y AS DOUBLE) AS value FROM unit
  UNION ALL
  SELECT codinv, deal_id, 'predeal_active_rate_5y',
         CAST(predeal_active_rate_5y AS DOUBLE) FROM unit
  UNION ALL
  SELECT codinv, deal_id, 'career_age_at_deal',
         CAST(career_age_at_deal AS DOUBLE) FROM unit
  UNION ALL
  SELECT codinv, deal_id, 'career_age_sq_at_deal',
         CAST(career_age_sq_at_deal AS DOUBLE) FROM unit
  UNION ALL
  SELECT codinv, deal_id, 'observed_target_patent_tenure',
         CAST(observed_target_patent_tenure AS DOUBLE) FROM unit
  UNION ALL
  SELECT codinv, deal_id, 'target_patenting_years_predeal',
         CAST(target_patenting_years_predeal AS DOUBLE) FROM unit
  UNION ALL
  SELECT codinv, deal_id, 'deal_value',
         CAST(deal_value AS DOUBLE) FROM unit
  UNION ALL
  SELECT codinv, deal_id, 'n_predeal_inventors',
         CAST(n_predeal_inventors AS DOUBLE) FROM unit
)
SELECT
  variable,
  COUNT(*) AS n,
  SUM(value IS NULL) AS n_missing,
  AVG(value) AS mean,
  STDDEV_SAMP(value) AS sd,
  MIN(value) AS min,
  QUANTILE_CONT(value, 0.25) AS p25,
  QUANTILE_CONT(value, 0.50) AS median,
  QUANTILE_CONT(value, 0.75) AS p75,
  MAX(value) AS max
FROM long
GROUP BY variable
ORDER BY variable
")

cs_covariate_correlations <- DBI::dbGetQuery(con, "
WITH unit AS (
  SELECT DISTINCT
    codinv,
    deal_id,
    log_predeal_patent_stock,
    predeal_active_rate_5y,
    log_career_age_at_deal,
    log_observed_target_patent_tenure
  FROM cs2021_estimation_panel
)
SELECT
  CORR(log_predeal_patent_stock, predeal_active_rate_5y)
    AS corr_log_stock_active_rate,
  CORR(log_career_age_at_deal, log_observed_target_patent_tenure)
    AS corr_log_career_age_target_tenure
FROM unit
")

cs_ipc_primary_field_distribution <- DBI::dbGetQuery(con, "
SELECT
  ipc_primary_field,
  COUNT(DISTINCT codinv || '|' || CAST(deal_id AS VARCHAR)) AS n_units,
  COUNT(DISTINCT deal_id) AS n_deals
FROM cs2021_estimation_panel
GROUP BY ipc_primary_field
ORDER BY n_units DESC
")

cs_outcome_prevalence <- DBI::dbGetQuery(con, "
SELECT
  event_time,
  COUNT(DISTINCT codinv) AS n_full_sample,
  COUNT(DISTINCT codinv) FILTER (WHERE status_available) AS n_left_sample,
  AVG(CAST(left_this_year AS DOUBLE)) AS share_left_this_year,
  AVG(CAST(rd_activity AS DOUBLE)) AS share_rd_active,
  AVG(CAST(active_patenting AS DOUBLE)) AS share_patenting_this_year,
  AVG(CAST(known_outside_switch AS DOUBLE)) AS share_known_outside_switch,
  AVG(log_patent_count) AS mean_log_patent_count,
  AVG(CAST(with_entity AS DOUBLE)) AS share_with_entity,
  AVG(CAST(moved_thirdparty AS DOUBLE)) AS share_moved_thirdparty,
  AVG(CAST(active_unknown_affiliation AS DOUBLE)) AS share_active_unknown_affiliation,
  AVG(CAST(inactive_silent_gap AS DOUBLE)) AS share_inactive_silent_gap,
  AVG(CAST(career_exited AS DOUBLE)) AS share_career_exited
FROM cs2021_estimation_panel
WHERE event_time BETWEEN -5 AND 5
GROUP BY event_time
ORDER BY event_time
")

# Calendar-year cross-section: state shares among inventors who are CURRENTLY
# not-yet-treated (their own deal_year is still in the future relative to this
# calendar year) vs currently treated (deal_year <= calendar_year). This is the
# population composition CS(2021) actually draws not-yet-treated controls from
# at each point in calendar time -- distinct from the own-event-time table above,
# which mixes calendar years together. Watch for active_unknown_affiliation or
# moved_thirdparty trending WITHIN the not-yet-treated pool across calendar years.
cs_state_by_calendar_year <- DBI::dbGetQuery(con, "
SELECT
  calendar_year,
  CASE WHEN deal_year > calendar_year THEN 'not_yet_treated'
       ELSE 'treated_or_post' END AS control_pool,
  COUNT(DISTINCT codinv) AS n_inventors,
  AVG(CAST(with_entity AS DOUBLE)) AS share_with_entity,
  AVG(CAST(moved_thirdparty AS DOUBLE)) AS share_moved_thirdparty,
  AVG(CAST(active_unknown_affiliation AS DOUBLE)) AS share_active_unknown_affiliation,
  AVG(CAST(inactive_silent_gap AS DOUBLE)) AS share_inactive_silent_gap,
  AVG(CAST(career_exited AS DOUBLE)) AS share_career_exited
FROM cs2021_estimation_panel
GROUP BY calendar_year, control_pool
ORDER BY calendar_year, control_pool
")

cs_outcome_samples <- DBI::dbGetQuery(con, "
SELECT
  'left_this_year' AS outcome,
  COUNT(DISTINCT codinv) FILTER (WHERE status_available) AS n_inventors,
  COUNT(DISTINCT deal_id) FILTER (WHERE status_available) AS n_deals
FROM cs2021_estimation_panel
UNION ALL
SELECT
  'rd_activity', COUNT(DISTINCT codinv), COUNT(DISTINCT deal_id)
FROM cs2021_estimation_panel
UNION ALL
SELECT
  'log_patent_count', COUNT(DISTINCT codinv), COUNT(DISTINCT deal_id)
FROM cs2021_estimation_panel
UNION ALL
SELECT
  'known_outside_switch',
  COUNT(DISTINCT codinv) FILTER (WHERE status_available),
  COUNT(DISTINCT deal_id) FILTER (WHERE status_available)
FROM cs2021_estimation_panel
")

cs_outcome_invariants <- DBI::dbGetQuery(con, "
WITH unit AS (
  SELECT DISTINCT
    codinv,
    deal_id,
    predeal_patent_stock_5y,
    predeal_active_rate_5y,
    career_age_at_deal,
    career_age_sq_at_deal,
    observed_target_patent_tenure,
    target_patenting_years_predeal,
    career_end_year,
    last_merged_entity_patent_year,
    log_deal_value,
    log_group_size,
    ipc_primary_field
  FROM cs2021_estimation_panel
)
SELECT
  (SELECT COUNT(*) FROM unit) AS n_units,
  (SELECT COUNT(*) FROM unit
    WHERE predeal_patent_stock_5y IS NULL
       OR predeal_active_rate_5y IS NULL
       OR career_age_at_deal IS NULL
       OR career_age_sq_at_deal IS NULL
       OR observed_target_patent_tenure IS NULL
       OR target_patenting_years_predeal IS NULL
       OR log_deal_value IS NULL
       OR log_group_size IS NULL
       OR ipc_primary_field IS NULL) AS n_units_missing_controls,
  (SELECT COUNT(*) FROM unit WHERE predeal_patent_stock_5y < 1) AS n_stock_below_one,
  (SELECT COUNT(*) FROM unit
    WHERE predeal_active_rate_5y < 0 OR predeal_active_rate_5y > 1)
    AS n_active_rate_out_of_bounds,
  (SELECT COUNT(*) FROM unit
    WHERE career_age_at_deal < 1 OR observed_target_patent_tenure < 1)
    AS n_nonpositive_age_or_tenure,
  -- rd_activity: data-driven absorbing survival; must equal CAST(career_end_year >= calendar_year AS INT)
  (SELECT COUNT(*) FROM cs2021_estimation_panel
    WHERE rd_activity <> CAST(career_end_year >= calendar_year AS INTEGER))
    AS n_rd_activity_mismatch,
  -- left_this_year: NULL only when status_available = FALSE; must be 0 or 1 otherwise
  (SELECT COUNT(*) FROM cs2021_estimation_panel
    WHERE status_available AND left_this_year IS NULL) AS n_missing_left_when_eligible,
  (SELECT COUNT(*) FROM cs2021_estimation_panel
    WHERE NOT status_available AND left_this_year IS NOT NULL)
    AS n_left_when_ineligible,
  -- left_this_year = 1 only in the year after last entity patent; check for double-firing
  (SELECT COUNT(*) FROM cs2021_estimation_panel
    WHERE left_this_year = 1
      AND last_merged_entity_patent_year <> calendar_year - 1)
    AS n_left_this_year_mismatch,
  (SELECT COUNT(*) FROM cs2021_estimation_panel
    WHERE ABS(log_patent_count - LN(1 + patent_count)) > 1e-12)
    AS n_log_patent_mismatch,
  -- five-state outcome must partition every row exactly once
  (SELECT COUNT(*) FROM cs2021_estimation_panel
    WHERE with_entity + moved_thirdparty + active_unknown_affiliation
        + inactive_silent_gap + career_exited <> 1)
    AS n_five_state_not_mece,
  (SELECT COUNT(*) FROM cs2021_estimation_panel
    WHERE inventor_annual_state IS NULL)
    AS n_five_state_null
")

cs_transition_cases <- DBI::dbGetQuery(con, "
WITH selected AS (
  SELECT DISTINCT codinv, deal_id
  FROM cs2021_estimation_panel
  WHERE first_known_outside_after_merged_year IS NOT NULL
  ORDER BY codinv, deal_id
  LIMIT 20
)
SELECT
  p.codinv,
  p.deal_id,
  p.deal_year,
  p.event_time,
  p.calendar_year,
  p.last_merged_entity_patent_year,
  p.first_known_outside_after_merged_year,
  p.career_end_year,
  p.left_this_year,
  p.rd_activity,
  p.active_patenting,
  p.known_outside_switch,
  p.patent_count
FROM cs2021_estimation_panel p
JOIN selected s USING (codinv, deal_id)
WHERE p.event_time BETWEEN -2 AND 5
ORDER BY p.codinv, p.deal_id, p.calendar_year
")

attrition_counts <- DBI::dbGetQuery(con, "
SELECT
  event_time,
  attrition_state,
  COUNT(*) AS n,
  COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (PARTITION BY event_time) AS share
FROM stayer_attrition_panel
GROUP BY event_time, attrition_state
ORDER BY event_time, attrition_state
")

# Report observed states; a state may be absent at a horizon when its count is zero.
attrition_state_check <- DBI::dbGetQuery(con, "
SELECT event_time, COUNT(DISTINCT attrition_state) AS n_states
FROM stayer_attrition_panel
GROUP BY event_time
ORDER BY event_time
")

write_csv_base(event_panel_counts,    "event_panel_sample_counts.csv")
write_csv_base(zero_fill_by_event,    "zero_fill_by_event_time.csv")
write_csv_base(panel_dimension_checks, "panel_dimension_checks.csv")
write_csv_base(cs_cohort_support,      "cs_cohort_support.csv")
write_csv_base(cs_covariate_audit,     "cs_covariate_audit.csv")
write_csv_base(cs_covariate_correlations, "cs_covariate_correlations.csv")
write_csv_base(cs_ipc_primary_field_distribution, "cs_ipc_primary_field_distribution.csv")
write_csv_base(cs_outcome_prevalence,  "cs_outcome_prevalence_by_event.csv")
write_csv_base(cs_state_by_calendar_year, "cs_state_by_calendar_year.csv")
write_csv_base(cs_outcome_samples,     "cs_outcome_sample_sizes.csv")
write_csv_base(cs_outcome_invariants,  "cs_outcome_invariants.csv")
write_csv_base(cs_transition_cases,    "cs_manual_transition_cases.csv")
write_csv_base(attrition_counts,      "attrition_state_counts.csv")
write_csv_base(attrition_state_check, "attrition_state_check.csv")

if (any(panel_dimension_checks$n_rows != panel_dimension_checks$expected_rows) ||
    any(panel_dimension_checks$n_rows != panel_dimension_checks$n_id_year)) {
  stop("Panel dimension invariant failed; inspect panel_dimension_checks.csv.")
}

if (any(unlist(cs_outcome_invariants[1, setdiff(names(cs_outcome_invariants), "n_units")]) != 0)) {
  stop("CS covariate/outcome invariant failed; inspect cs_outcome_invariants.csv.")
}

print(zero_fill_by_event)
print(panel_dimension_checks)
print(cs_covariate_audit)
print(cs_covariate_correlations)
print(cs_ipc_primary_field_distribution)
print(cs_outcome_samples)
print(cs_outcome_invariants)
print(cs_outcome_prevalence)
print(cs_state_by_calendar_year)
print(attrition_state_check)

message("\n", strrep("=", 60))
message("Event panel build complete.")
message("  Audits : ", AUDIT)
message(strrep("=", 60), "\n")

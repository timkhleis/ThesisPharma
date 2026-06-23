# Build own MECE post-acquisition inventor status classification from new Cassi files
#
# Run from project root after 04b and 04a:
#   Rscript 02_analysis/R/04c_build_prelim_own_status.R
#
# Outputs:
#   DuckDB tables : cassi_deal_spine, inventor_status_own
#   Parquet       : 02_analysis/output/parquet/helper/cassi_deal_spine.parquet
#                   02_analysis/output/parquet/derived/inventor_status_own.parquet
#   Audit CSVs    : 02_analysis/output/audit/prelim_own_status/

BASE <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
HELPER_PARQUET <- file.path(BASE, "output", "parquet", "helper")
DERIVED_PARQUET <- file.path(BASE, "output", "parquet", "derived")
AUDIT <- file.path(BASE, "output", "audit", "prelim_own_status")

source(file.path(BASE, "R", "00_utils.R"))
load_packages()
library(duckdb)

dir.create(HELPER_PARQUET, recursive = TRUE, showWarnings = FALSE)
dir.create(DERIVED_PARQUET, recursive = TRUE, showWarnings = FALSE)
dir.create(AUDIT, recursive = TRUE, showWarnings = FALSE)

banner <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")

copy_to_parquet <- function(con, table_name, parquet_dir) {
  parquet_file <- file.path(parquet_dir, paste0(table_name, ".parquet"))
  parquet_sql <- gsub("\\\\", "/", parquet_file)
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

banner("PRELIMINARY OWN STATUS CLASSIFICATION")

required_tables <- c(
  "cassi_group_history_target",
  "cassi_merge",
  "inventor_affiliation_own",
  "inventor_status_reference"
)
missing_tables <- required_tables[!vapply(required_tables, DBI::dbExistsTable, logical(1), conn = con)]
if (length(missing_tables) > 0) {
  stop("Missing required DuckDB tables: ", paste(missing_tables, collapse = ", "),
       ". Run 04b_import_cassi_deal_files.R and 04a_build_inventor_affiliation.R first.")
}

section("Building Cassi-backed deal spine")

DBI::dbExecute(con, "
CREATE OR REPLACE TABLE cassi_deal_spine AS
WITH target_events AS (
  SELECT DISTINCT
    CAST(gh.merger_nmb AS VARCHAR) AS dealnumber,
    gh.year AS deal_year,
    gh.merger_value AS deal_value_from_history,
    gh.compcod AS target_compcod,
    gh.id_group AS target_group_post,
    gh.target_nmb,
    gh.merger_status
  FROM cassi_group_history_target AS gh
  WHERE gh.merger_status = 'target'
    AND gh.merger_nmb IS NOT NULL
    AND TRIM(CAST(gh.merger_nmb AS VARCHAR)) <> ''
),
merge_keep AS (
  SELECT
    CAST(dealnumber AS VARCHAR) AS dealnumber,
    acquirer,
    target,
    dealtype,
    acquirorcountrycode,
    targetcountrycode,
    year_merge,
    value AS deal_value_from_merge,
    compcod_acquirer AS acquirer_compcod,
    compcod_target AS merge_target_compcod,
    divest,
    todrop_acq,
    todrop_tar
  FROM cassi_merge
),
target_with_merge AS (
  SELECT
    te.*,
    mk.acquirer,
    mk.target,
    mk.dealtype,
    mk.acquirorcountrycode,
    mk.targetcountrycode,
    mk.year_merge,
    mk.deal_value_from_merge,
    mk.acquirer_compcod,
    mk.merge_target_compcod,
    mk.divest,
    mk.todrop_acq,
    mk.todrop_tar
  FROM target_events te
  LEFT JOIN merge_keep mk
    ON te.dealnumber = mk.dealnumber
),
with_groups AS (
  SELECT
    twm.*,
    tgt_pre.id_group AS target_group_pre,
    acq_year.id_group AS acquirer_group_at_deal,
    acq_pre.id_group AS acquirer_group_pre,
    acq_post.id_group AS acquirer_group_post
  FROM target_with_merge twm
  LEFT JOIN cassi_group_history_target tgt_pre
    ON twm.target_compcod = tgt_pre.compcod
   AND twm.deal_year - 1 = tgt_pre.year
  LEFT JOIN cassi_group_history_target acq_year
    ON twm.acquirer_compcod = acq_year.compcod
   AND twm.deal_year = acq_year.year
  LEFT JOIN cassi_group_history_target acq_pre
    ON twm.acquirer_compcod = acq_pre.compcod
   AND twm.deal_year - 1 = acq_pre.year
  LEFT JOIN cassi_group_history_target acq_post
    ON twm.acquirer_compcod = acq_post.compcod
   AND twm.deal_year + 1 = acq_post.year
)
SELECT
  ROW_NUMBER() OVER (
    ORDER BY deal_year, dealnumber, target_compcod
  ) AS cassi_deal_row_id,
  dealnumber,
  deal_year,
  COALESCE(deal_value_from_merge, deal_value_from_history) AS deal_value,
  target_compcod,
  acquirer_compcod,
  merge_target_compcod,
  COALESCE(target_group_pre, target_group_post) AS target_group,
  target_group_pre,
  target_group_post,
  CASE
    WHEN COALESCE(acquirer_group_at_deal, acquirer_group_pre, acquirer_group_post) IS NOT NULL
      THEN COALESCE(acquirer_group_at_deal, acquirer_group_pre, acquirer_group_post)
    WHEN target_group_post IS NOT NULL
     AND target_group_pre IS NOT NULL
     AND target_group_post <> target_group_pre
     AND CAST(target_group_post AS VARCHAR) NOT LIKE '999%'
      THEN target_group_post
    ELSE NULL
  END AS acquirer_group,
  COALESCE(acquirer_group_at_deal, acquirer_group_pre, acquirer_group_post) AS acquirer_group_from_company,
  CASE
    WHEN COALESCE(acquirer_group_at_deal, acquirer_group_pre, acquirer_group_post) IS NOT NULL
      THEN 'explicit_acquirer_company'
    WHEN target_group_post IS NOT NULL
     AND target_group_pre IS NOT NULL
     AND target_group_post <> target_group_pre
     AND CAST(target_group_post AS VARCHAR) NOT LIKE '999%'
      THEN 'target_post_group_fallback'
    WHEN target_group_post IS NOT NULL
     AND CAST(target_group_post AS VARCHAR) LIKE '999%'
      THEN 'unresolved_placeholder_post_group'
    ELSE 'unresolved_missing_post_group'
  END AS acquirer_group_source,
  acquirer_group_at_deal,
  acquirer_group_pre,
  acquirer_group_post,
  target_nmb,
  acquirer,
  target,
  dealtype,
  acquirorcountrycode,
  targetcountrycode,
  year_merge,
  divest,
  todrop_acq,
  todrop_tar,
  CASE WHEN COALESCE(deal_value_from_merge, deal_value_from_history) > 5000000
       THEN TRUE ELSE FALSE END AS big_deal,
  CASE
    WHEN target_group_pre IS NULL THEN 'TARGET_PRE_MISSING'
    WHEN COALESCE(acquirer_group_at_deal, acquirer_group_pre, acquirer_group_post) IS NULL
      AND target_group_post IS NOT NULL
      AND target_group_pre IS NOT NULL
      AND target_group_post <> target_group_pre
      AND CAST(target_group_post AS VARCHAR) NOT LIKE '999%' THEN 'ACQUIRER_GROUP_FALLBACK'
    WHEN COALESCE(acquirer_group_at_deal, acquirer_group_pre, acquirer_group_post) IS NULL THEN 'ACQUIRER_GROUP_MISSING'
    WHEN year_merge IS NOT NULL AND year_merge <> deal_year THEN 'YEAR_MISMATCH'
    ELSE 'OK'
  END AS spine_issue
FROM with_groups
WHERE deal_year BETWEEN 1988 AND 2015
  AND (divest IS NULL OR divest <> 1)
")

spine_path <- copy_to_parquet(con, "cassi_deal_spine", HELPER_PARQUET)
message("Written: ", spine_path)

section("Building first-exposure target-side inventor classification")

DBI::dbExecute(con, "
CREATE OR REPLACE TABLE cassi_deal_group_spine AS
SELECT
  ROW_NUMBER() OVER (
    ORDER BY MIN(deal_year), dealnumber, target_group, acquirer_group
  ) AS cassi_deal_group_id,
  dealnumber,
  MIN(deal_year) AS deal_year,
  MAX(deal_value) AS deal_value,
  target_group,
  acquirer_group,
  MIN(acquirer_group_source) AS acquirer_group_source,
  BOOL_OR(big_deal) AS big_deal,
  COUNT(DISTINCT target_compcod) AS n_target_companies,
  string_agg(DISTINCT CAST(target_compcod AS VARCHAR), ';' ORDER BY CAST(target_compcod AS VARCHAR)) AS target_compcod_list,
  MIN(acquirer_compcod) AS acquirer_compcod,
  MIN(acquirer) AS acquirer,
  MIN(target) AS target,
  string_agg(DISTINCT spine_issue, ';' ORDER BY spine_issue) AS spine_issues
FROM cassi_deal_spine
WHERE target_group IS NOT NULL
  AND acquirer_group IS NOT NULL
GROUP BY dealnumber, target_group, acquirer_group
")

group_spine_path <- copy_to_parquet(con, "cassi_deal_group_spine", HELPER_PARQUET)
message("Written: ", group_spine_path)

DBI::dbExecute(con, "
CREATE OR REPLACE TABLE inventor_status_own AS
WITH usable_deals AS (
  SELECT *
  FROM cassi_deal_group_spine
),
target_side AS (
  SELECT
    ia.codinv,
    ud.cassi_deal_group_id,
    ud.dealnumber,
    ud.deal_year,
    ud.deal_value,
    ud.acquirer_compcod,
    ud.target_group,
    ud.acquirer_group,
    ud.acquirer_group_source,
    ud.big_deal,
    ud.n_target_companies,
    ud.target_compcod_list,
    MIN(ia.year) AS first_target_affiliation_year,
    MAX(ia.year) AS last_target_affiliation_year,
    COUNT(DISTINCT ia.year) AS n_target_pre_years
  FROM usable_deals ud
  JOIN inventor_affiliation_own ia
    ON ia.resolved_group = ud.target_group
   AND ia.year BETWEEN ud.deal_year - 5 AND ud.deal_year - 1
  GROUP BY
    ia.codinv,
    ud.cassi_deal_group_id,
    ud.dealnumber,
    ud.deal_year,
    ud.deal_value,
    ud.acquirer_compcod,
    ud.target_group,
    ud.acquirer_group,
    ud.acquirer_group_source,
    ud.big_deal,
    ud.n_target_companies,
    ud.target_compcod_list
),
last_pre_affiliation AS (
  SELECT
    ts.codinv,
    ts.cassi_deal_group_id,
    ia.year AS last_pre_affiliation_year,
    ia.resolved_group AS last_pre_affiliation_group,
    ROW_NUMBER() OVER (
      PARTITION BY ts.codinv, ts.cassi_deal_group_id
      ORDER BY ia.year DESC
    ) AS rn
  FROM target_side ts
  JOIN inventor_affiliation_own ia
    ON ia.codinv = ts.codinv
   AND ia.year BETWEEN ts.deal_year - 5 AND ts.deal_year - 1
),
target_side_current AS (
  SELECT
    ts.*,
    lp.last_pre_affiliation_year,
    lp.last_pre_affiliation_group
  FROM target_side ts
  JOIN last_pre_affiliation lp
    ON ts.codinv = lp.codinv
   AND ts.cassi_deal_group_id = lp.cassi_deal_group_id
   AND lp.rn = 1
   AND lp.last_pre_affiliation_group = ts.target_group
),
post_activity AS (
  SELECT
    ts.codinv,
    ts.cassi_deal_group_id,
    MIN(ia.year) AS first_post_patent_year,
    MIN(CASE WHEN ia.resolved_group = ts.acquirer_group THEN ia.year END) AS first_acquirer_year,
    MIN(CASE
          WHEN ia.resolved_group IS NOT NULL
           AND CAST(ia.resolved_group AS VARCHAR) NOT LIKE '999%'
           AND ia.resolved_group <> ts.acquirer_group
           AND ia.resolved_group <> ts.target_group
          THEN ia.year
        END) AS first_other_known_year,
    COUNT(DISTINCT ia.year) AS n_post_patent_years,
    COUNT(DISTINCT CASE WHEN ia.resolved_group = ts.acquirer_group THEN ia.year END) AS n_acquirer_post_years,
    COUNT(DISTINCT CASE WHEN ia.resolved_group = ts.target_group THEN ia.year END) AS n_target_post_years,
    COUNT(DISTINCT CASE
      WHEN ia.resolved_group IS NOT NULL
       AND CAST(ia.resolved_group AS VARCHAR) NOT LIKE '999%'
       AND ia.resolved_group <> ts.acquirer_group
       AND ia.resolved_group <> ts.target_group THEN ia.year END) AS n_other_post_years,
    COUNT(DISTINCT CASE
      WHEN ia.resolved_group IS NULL
        OR CAST(ia.resolved_group AS VARCHAR) LIKE '999%' THEN ia.year END) AS n_unclassified_post_years
  FROM target_side_current ts
  LEFT JOIN inventor_affiliation_own ia
    ON ia.codinv = ts.codinv
   AND ia.year BETWEEN ts.deal_year AND ts.deal_year + 5
  GROUP BY ts.codinv, ts.cassi_deal_group_id
),
unrestricted_activity AS (
  SELECT
    ts.codinv,
    ts.cassi_deal_group_id,
    COUNT(DISTINCT CASE WHEN ia.resolved_group = ts.acquirer_group THEN ia.year END)
      AS n_acquirer_unrestricted_years,
    COUNT(DISTINCT CASE
      WHEN ia.resolved_group IS NOT NULL
       AND CAST(ia.resolved_group AS VARCHAR) NOT LIKE '999%'
       AND ia.resolved_group <> ts.acquirer_group
       AND ia.resolved_group <> ts.target_group THEN ia.year END)
      AS n_other_unrestricted_years,
    COUNT(DISTINCT CASE
      WHEN ia.resolved_group = ts.acquirer_group
       AND ia.year > ts.deal_year + 5 THEN ia.year END)
      AS n_late_acquirer_years,
    COUNT(DISTINCT CASE
      WHEN ia.resolved_group IS NOT NULL
       AND CAST(ia.resolved_group AS VARCHAR) NOT LIKE '999%'
       AND ia.resolved_group <> ts.acquirer_group
       AND ia.resolved_group <> ts.target_group
       AND ia.year > ts.deal_year + 5 THEN ia.year END)
      AS n_late_other_years
  FROM target_side_current ts
  LEFT JOIN inventor_affiliation_own ia
    ON ia.codinv = ts.codinv
   AND ia.year >= ts.deal_year
  GROUP BY ts.codinv, ts.cassi_deal_group_id
),
outside_after_acquirer AS (
  SELECT
    ts.codinv,
    ts.cassi_deal_group_id,
    MIN(ia.year) AS first_outside_year
  FROM target_side_current ts
  JOIN post_activity pa
    ON ts.codinv = pa.codinv
   AND ts.cassi_deal_group_id = pa.cassi_deal_group_id
  JOIN inventor_affiliation_own ia
    ON ia.codinv = ts.codinv
   AND ia.year > pa.first_acquirer_year
   AND ia.year BETWEEN ts.deal_year AND ts.deal_year + 5
   AND ia.resolved_group IS NOT NULL
   AND CAST(ia.resolved_group AS VARCHAR) NOT LIKE '999%'
   AND ia.resolved_group <> ts.acquirer_group
   AND ia.resolved_group <> ts.target_group
  WHERE pa.first_acquirer_year IS NOT NULL
  GROUP BY ts.codinv, ts.cassi_deal_group_id
),
horizon_outside AS (
  SELECT
    ts.codinv,
    ts.cassi_deal_group_id,
    COUNT(DISTINCT CASE
      WHEN ia.year BETWEEN ts.deal_year AND ts.deal_year + 2 THEN ia.year END) AS n_outside_through_2,
    COUNT(DISTINCT CASE
      WHEN ia.year BETWEEN ts.deal_year AND ts.deal_year + 3 THEN ia.year END) AS n_outside_through_3,
    COUNT(DISTINCT CASE
      WHEN ia.year BETWEEN ts.deal_year AND ts.deal_year + 5 THEN ia.year END) AS n_outside_through_5
  FROM target_side_current ts
  LEFT JOIN inventor_affiliation_own ia
    ON ia.codinv = ts.codinv
   AND ia.year BETWEEN ts.deal_year AND ts.deal_year + 5
   AND ia.resolved_group IS NOT NULL
   AND CAST(ia.resolved_group AS VARCHAR) NOT LIKE '999%'
   AND ia.resolved_group <> ts.acquirer_group
   AND ia.resolved_group <> ts.target_group
  GROUP BY ts.codinv, ts.cassi_deal_group_id
),
career_end AS (
  SELECT
    codinv,
    MAX(year) AS career_end_year
  FROM inventor_year
  WHERE patent_count > 0
  GROUP BY codinv
),
classified AS (
  SELECT
    ts.*,
    pa.first_post_patent_year,
    pa.first_acquirer_year,
    pa.first_other_known_year,
    oa.first_outside_year,
    ce.career_end_year,
    COALESCE(pa.n_post_patent_years, 0) AS n_post_patent_years,
    COALESCE(pa.n_acquirer_post_years, 0) AS n_acquirer_post_years,
    COALESCE(pa.n_target_post_years, 0) AS n_target_post_years,
    COALESCE(pa.n_other_post_years, 0) AS n_other_post_years,
    COALESCE(pa.n_unclassified_post_years, 0) AS n_unclassified_post_years,
    CASE WHEN COALESCE(pa.n_post_patent_years, 0) > 0 THEN TRUE ELSE FALSE END AS has_post_patent,
    CASE WHEN COALESCE(pa.n_acquirer_post_years, 0) > 0 THEN TRUE ELSE FALSE END AS has_acquirer_post_patent,
    CASE WHEN COALESCE(pa.n_target_post_years, 0) > 0 THEN TRUE ELSE FALSE END AS has_target_post_patent,
    CASE WHEN COALESCE(pa.n_other_post_years, 0) > 0 THEN TRUE ELSE FALSE END AS has_other_known_post_patent,
    CASE WHEN COALESCE(pa.n_unclassified_post_years, 0) > 0 THEN TRUE ELSE FALSE END AS has_unclassified_post_patent,
    CASE WHEN COALESCE(ua.n_acquirer_unrestricted_years, 0) > 0 THEN TRUE ELSE FALSE END AS ever_stayed_unrestricted,
    CASE WHEN COALESCE(ua.n_other_unrestricted_years, 0) > 0
       AND COALESCE(ua.n_acquirer_unrestricted_years, 0) = 0 THEN TRUE ELSE FALSE END AS leaver_unrestricted,
    CASE WHEN COALESCE(ua.n_acquirer_unrestricted_years, 0) > 0
       OR COALESCE(ua.n_other_unrestricted_years, 0) > 0 THEN TRUE ELSE FALSE END AS active_unrestricted,
    CASE WHEN COALESCE(ua.n_late_acquirer_years, 0) > 0 THEN TRUE ELSE FALSE END AS late_acquirer_after_5,
    CASE WHEN COALESCE(ua.n_late_other_years, 0) > 0 THEN TRUE ELSE FALSE END AS late_outside_after_5,
    CASE WHEN COALESCE(ua.n_late_acquirer_years, 0) > 0
       OR COALESCE(ua.n_late_other_years, 0) > 0 THEN TRUE ELSE FALSE END AS late_active_after_5,
    CASE
      WHEN COALESCE(pa.n_acquirer_post_years, 0) > 0 THEN 'T_Ever_Stayed'
      WHEN COALESCE(pa.n_target_post_years, 0) > 0
       AND COALESCE(pa.n_other_post_years, 0) = 0
       AND COALESCE(pa.n_unclassified_post_years, 0) = 0 THEN 'T_TARGET_CONTINUING'
      WHEN COALESCE(pa.n_post_patent_years, 0) = 0 THEN 'T_NO_POST_5Y'
      WHEN COALESCE(pa.n_other_post_years, 0) > 0 THEN 'T_LEAVER'
      ELSE 'T_UNCLASSIFIED_POST_GROUP'
    END AS type,
    COALESCE(ho.n_outside_through_2, 0) AS n_outside_through_2,
    COALESCE(ho.n_outside_through_3, 0) AS n_outside_through_3,
    COALESCE(ho.n_outside_through_5, 0) AS n_outside_through_5
  FROM target_side_current ts
  LEFT JOIN post_activity pa
    ON ts.codinv = pa.codinv
   AND ts.cassi_deal_group_id = pa.cassi_deal_group_id
  LEFT JOIN unrestricted_activity ua
    ON ts.codinv = ua.codinv
   AND ts.cassi_deal_group_id = ua.cassi_deal_group_id
  LEFT JOIN outside_after_acquirer oa
    ON ts.codinv = oa.codinv
   AND ts.cassi_deal_group_id = oa.cassi_deal_group_id
  LEFT JOIN horizon_outside ho
    ON ts.codinv = ho.codinv
   AND ts.cassi_deal_group_id = ho.cassi_deal_group_id
  LEFT JOIN career_end ce
    ON ts.codinv = ce.codinv
),
with_diagnostics AS (
  SELECT
    *,
    CASE WHEN type = 'T_Ever_Stayed' THEN TRUE ELSE FALSE END AS retained_conservative,
    CASE WHEN type IN ('T_Ever_Stayed', 'T_TARGET_CONTINUING') THEN TRUE ELSE FALSE END AS retained_expanded,
    CASE WHEN type = 'T_Ever_Stayed' AND first_outside_year <= deal_year + 1 THEN TRUE ELSE FALSE END AS short_stayer_1y,
    CASE WHEN type = 'T_Ever_Stayed' AND first_outside_year <= deal_year + 2 THEN TRUE ELSE FALSE END AS short_stayer,
    CASE WHEN type = 'T_Ever_Stayed' AND first_outside_year <= deal_year + 3 THEN TRUE ELSE FALSE END AS short_stayer_3y,
    CASE WHEN type = 'T_Ever_Stayed'
       AND first_acquirer_year <= deal_year + 2
       AND n_outside_through_2 = 0 THEN TRUE ELSE FALSE END AS persistent_stayer_2,
    CASE WHEN type = 'T_Ever_Stayed'
       AND first_acquirer_year <= deal_year + 3
       AND n_outside_through_3 = 0 THEN TRUE ELSE FALSE END AS persistent_stayer_3,
    CASE WHEN type = 'T_Ever_Stayed'
       AND first_acquirer_year <= deal_year + 5
       AND n_outside_through_5 = 0 THEN TRUE ELSE FALSE END AS persistent_stayer_5,
    CASE WHEN type = 'T_Ever_Stayed'
       AND first_acquirer_year <= deal_year + 2
       AND n_outside_through_2 = 0
       AND career_end_year >= deal_year + 2 THEN TRUE ELSE FALSE END AS patent_active_survivor_2,
    CASE WHEN type = 'T_Ever_Stayed'
       AND first_acquirer_year <= deal_year + 3
       AND n_outside_through_3 = 0
       AND career_end_year >= deal_year + 3 THEN TRUE ELSE FALSE END AS patent_active_survivor_3,
    CASE WHEN type = 'T_Ever_Stayed'
       AND first_acquirer_year <= deal_year + 5
       AND n_outside_through_5 = 0
       AND career_end_year >= deal_year + 5 THEN TRUE ELSE FALSE END AS patent_active_survivor_5,
    CASE WHEN type = 'T_Ever_Stayed'
       AND career_end_year < deal_year + 2 THEN TRUE ELSE FALSE END AS career_exit_before_2,
    CASE WHEN type = 'T_Ever_Stayed'
       AND career_end_year < deal_year + 3 THEN TRUE ELSE FALSE END AS career_exit_before_3,
    CASE WHEN type = 'T_Ever_Stayed'
       AND career_end_year < deal_year + 5 THEN TRUE ELSE FALSE END AS career_exit_before_5
  FROM classified
),
ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY codinv
      ORDER BY deal_year, cassi_deal_group_id
    ) AS exposure_rank,
    COUNT(*) OVER (PARTITION BY codinv) AS n_candidate_exposures
  FROM with_diagnostics
)
SELECT
  codinv,
  cassi_deal_group_id,
  cassi_deal_group_id AS cassi_deal_row_id,
  dealnumber,
  deal_year,
  deal_value,
  acquirer_compcod,
  target_group,
  acquirer_group,
  acquirer_group_source,
  big_deal,
  n_target_companies,
  target_compcod_list,
  type,
  retained_conservative,
  retained_expanded,
  first_target_affiliation_year,
  last_target_affiliation_year,
  last_pre_affiliation_year,
  last_pre_affiliation_group,
  n_target_pre_years,
  first_post_patent_year,
  first_acquirer_year,
  first_acquirer_year AS first_acquirer_affiliation_year,
  first_other_known_year,
  first_outside_year,
  career_end_year,
  n_post_patent_years,
  n_acquirer_post_years,
  n_target_post_years,
  n_other_post_years,
  n_unclassified_post_years,
  has_post_patent,
  has_acquirer_post_patent,
  has_target_post_patent,
  has_other_known_post_patent,
  has_unclassified_post_patent,
  ever_stayed_unrestricted,
  leaver_unrestricted,
  active_unrestricted,
  late_acquirer_after_5,
  late_outside_after_5,
  late_active_after_5,
  n_outside_through_2,
  n_outside_through_3,
  n_outside_through_5,
  short_stayer_1y,
  short_stayer,
  short_stayer_3y,
  persistent_stayer_2,
  persistent_stayer_3,
  persistent_stayer_5,
  patent_active_survivor_2,
  patent_active_survivor_3,
  patent_active_survivor_5,
  career_exit_before_2,
  career_exit_before_3,
  career_exit_before_5,
  n_candidate_exposures,
  exposure_rank,
  CASE WHEN n_candidate_exposures > 1 THEN TRUE ELSE FALSE END AS multi_exposure_inventor
FROM ranked
WHERE exposure_rank = 1
")

status_path <- copy_to_parquet(con, "inventor_status_own", DERIVED_PARQUET)
message("Written: ", status_path)

section("Validation and audit outputs")

spine_summary <- DBI::dbGetQuery(con, "
SELECT
  COUNT(*) AS n_rows,
  COUNT(DISTINCT dealnumber) AS n_dealnumbers,
  COUNT(DISTINCT target_compcod) AS n_target_compcod,
  COUNT(DISTINCT target_group) AS n_target_groups,
  COUNT(DISTINCT acquirer_group) AS n_acquirer_groups,
  SUM(CASE WHEN spine_issue = 'OK' THEN 1 ELSE 0 END) AS n_ok,
  SUM(CASE WHEN target_group_pre IS NULL THEN 1 ELSE 0 END) AS n_target_pre_missing,
  SUM(CASE WHEN acquirer_group IS NULL THEN 1 ELSE 0 END) AS n_acquirer_missing,
  MIN(deal_year) AS min_deal_year,
  MAX(deal_year) AS max_deal_year
FROM cassi_deal_spine
")

status_counts <- DBI::dbGetQuery(con, "
SELECT
  type,
  COUNT(*) AS n_inventor_deals,
  COUNT(DISTINCT codinv) AS n_inventors,
  COUNT(DISTINCT cassi_deal_group_id) AS n_deal_rows
FROM inventor_status_own
GROUP BY type
ORDER BY type
")

status_counts_clean <- DBI::dbGetQuery(con, "
SELECT
  type,
  COUNT(*) AS n_inventor_deals,
  COUNT(DISTINCT codinv) AS n_inventors,
  COUNT(DISTINCT cassi_deal_group_id) AS n_deal_rows
FROM inventor_status_own
WHERE deal_year BETWEEN 1993 AND 2010
GROUP BY type
ORDER BY type
")

status_counts_by_year <- DBI::dbGetQuery(con, "
SELECT
  deal_year,
  type,
  COUNT(*) AS n_inventor_deals,
  COUNT(DISTINCT codinv) AS n_inventors,
  COUNT(DISTINCT cassi_deal_group_id) AS n_deal_rows
FROM inventor_status_own
GROUP BY deal_year, type
ORDER BY deal_year, type
")

horizon_stayer_counts <- DBI::dbGetQuery(con, "
SELECT
  COUNT(*) AS n_total,
  SUM(CASE WHEN type = 'T_Ever_Stayed' THEN 1 ELSE 0 END) AS n_t_ever_stayed,
  SUM(CASE WHEN persistent_stayer_2 THEN 1 ELSE 0 END) AS n_persistent_stayer_2,
  SUM(CASE WHEN persistent_stayer_3 THEN 1 ELSE 0 END) AS n_persistent_stayer_3,
  SUM(CASE WHEN persistent_stayer_5 THEN 1 ELSE 0 END) AS n_persistent_stayer_5,
  SUM(CASE WHEN patent_active_survivor_2 THEN 1 ELSE 0 END) AS n_patent_active_survivor_2,
  SUM(CASE WHEN patent_active_survivor_3 THEN 1 ELSE 0 END) AS n_patent_active_survivor_3,
  SUM(CASE WHEN patent_active_survivor_5 THEN 1 ELSE 0 END) AS n_patent_active_survivor_5,
  SUM(CASE WHEN career_exit_before_2 THEN 1 ELSE 0 END) AS n_career_exit_before_2,
  SUM(CASE WHEN career_exit_before_3 THEN 1 ELSE 0 END) AS n_career_exit_before_3,
  SUM(CASE WHEN career_exit_before_5 THEN 1 ELSE 0 END) AS n_career_exit_before_5,
  SUM(CASE WHEN short_stayer THEN 1 ELSE 0 END) AS n_short_stayer_2
FROM inventor_status_own
")

retained_sample_counts <- DBI::dbGetQuery(con, "
SELECT
  SUM(CASE WHEN retained_conservative THEN 1 ELSE 0 END) AS n_retained_conservative,
  SUM(CASE WHEN retained_expanded THEN 1 ELSE 0 END) AS n_retained_expanded,
  SUM(CASE WHEN type = 'T_TARGET_CONTINUING' THEN 1 ELSE 0 END) AS n_target_continuing,
  SUM(CASE WHEN retained_conservative AND deal_year BETWEEN 1993 AND 2010 THEN 1 ELSE 0 END)
    AS n_retained_conservative_clean,
  SUM(CASE WHEN retained_expanded AND deal_year BETWEEN 1993 AND 2010 THEN 1 ELSE 0 END)
    AS n_retained_expanded_clean
FROM inventor_status_own
")

multi_exposure_counts <- DBI::dbGetQuery(con, "
SELECT
  n_candidate_exposures,
  COUNT(*) AS n_inventors
FROM inventor_status_own
GROUP BY n_candidate_exposures
ORDER BY n_candidate_exposures
")

validation <- DBI::dbGetQuery(con, "
WITH ref AS (
  SELECT DISTINCT
    codinv,
    target_year AS deal_year,
    CAST(target_value AS DOUBLE) AS deal_value,
    type
  FROM inventor_status_reference
  WHERE type IN ('T_STAYER', 'T_LEAVER')
    AND target_year IS NOT NULL
),
own AS (
  SELECT DISTINCT
    codinv,
    deal_year,
    type
  FROM inventor_status_own
),
comparisons AS (
  SELECT
    'own_conservative_stayer_vs_ref_T_STAYER' AS comparison,
    'T_STAYER' AS ref_type,
    'T_Ever_Stayed' AS own_type,
    FALSE AS include_target_continuing
  UNION ALL
  SELECT
    'own_expanded_stayer_vs_ref_T_STAYER' AS comparison,
    'T_STAYER' AS ref_type,
    'T_Ever_Stayed' AS own_type,
    TRUE AS include_target_continuing
  UNION ALL
  SELECT
    'own_leaver_vs_ref_T_LEAVER' AS comparison,
    'T_LEAVER' AS ref_type,
    'T_LEAVER' AS own_type,
    FALSE AS include_target_continuing
)
SELECT
  c.comparison,
  c.ref_type,
  CASE
    WHEN c.include_target_continuing THEN 'T_Ever_Stayed + T_TARGET_CONTINUING'
    ELSE c.own_type
  END AS own_type_mapping,
  (SELECT COUNT(*) FROM ref WHERE ref.type = c.ref_type) AS benchmark_count,
  (SELECT COUNT(*)
   FROM own
   WHERE own.type = c.own_type
      OR (c.include_target_continuing AND own.type = 'T_TARGET_CONTINUING')) AS own_count,
  (SELECT COUNT(*)
   FROM own
   INNER JOIN ref
     ON own.codinv = ref.codinv
    AND own.deal_year = ref.deal_year
    AND ref.type = c.ref_type
   WHERE own.type = c.own_type
      OR (c.include_target_continuing AND own.type = 'T_TARGET_CONTINUING')) AS overlap_count,
  CAST((SELECT COUNT(*)
        FROM own
        INNER JOIN ref
          ON own.codinv = ref.codinv
         AND own.deal_year = ref.deal_year
         AND ref.type = c.ref_type
        WHERE own.type = c.own_type
           OR (c.include_target_continuing AND own.type = 'T_TARGET_CONTINUING')) AS DOUBLE)
    / NULLIF((SELECT COUNT(*) FROM ref WHERE ref.type = c.ref_type), 0) AS benchmark_match_rate
FROM comparisons c
")

# deal_map is a derived table built by the main pipeline (02_build_derived_tables.R).
# If it is missing, run the pipeline first:
#   Rscript analysis/R/01_build_data_foundation.R
#   Rscript analysis/R/02_build_derived_tables.R
# or together:
#   Rscript analysis/R/run_pipeline.R
deal_map_comparison <- tryCatch(
  DBI::dbGetQuery(con, "
WITH cassi AS (
  SELECT
    deal_year,
    ROUND(deal_value, 0) AS deal_value_rounded,
    COUNT(*) AS n_cassi_rows
  FROM cassi_deal_spine
  GROUP BY deal_year, ROUND(deal_value, 0)
),
old AS (
  SELECT
    target_year AS deal_year,
    ROUND(target_value, 0) AS deal_value_rounded,
    COUNT(*) AS n_old_rows
  FROM deal_map
  GROUP BY target_year, ROUND(target_value, 0)
)
SELECT
  COUNT(*) AS n_cassi_year_value_keys,
  SUM(CASE WHEN old.n_old_rows IS NOT NULL THEN 1 ELSE 0 END) AS n_keys_matching_old_deal_map,
  SUM(CASE WHEN old.n_old_rows IS NULL THEN 1 ELSE 0 END) AS n_keys_not_in_old_deal_map
FROM cassi
LEFT JOIN old
  ON cassi.deal_year = old.deal_year
 AND cassi.deal_value_rounded = old.deal_value_rounded
"),
  error = function(e) {
    message("deal_map table not found — skipping deal_map_comparison audit.")
    message("To build it, run: Rscript analysis/R/run_pipeline.R")
    data.frame(note = "deal_map table not available — run run_pipeline.R first")
  }
)

sample_waterfall <- DBI::dbGetQuery(con, "
SELECT 'cassi_deal_group_spine_rows' AS step, COUNT(*) AS n FROM cassi_deal_group_spine
UNION ALL
SELECT 'inventor_status_own_rows', COUNT(*) FROM inventor_status_own
UNION ALL
SELECT 'clean_window_rows', COUNT(*) FROM inventor_status_own WHERE deal_year BETWEEN 1993 AND 2010
UNION ALL
SELECT 'multi_exposure_inventors', COUNT(*) FROM inventor_status_own WHERE multi_exposure_inventor
UNION ALL
SELECT 'unclassified_post_group_rows', COUNT(*) FROM inventor_status_own WHERE type = 'T_UNCLASSIFIED_POST_GROUP'
")

unrestricted_status_comparison <- DBI::dbGetQuery(con, "
WITH scoped AS (
  SELECT 'full_sample' AS sample, * FROM inventor_status_own
  UNION ALL
  SELECT 'clean_1993_2010' AS sample, * FROM inventor_status_own
  WHERE deal_year BETWEEN 1993 AND 2010
),
summary AS (
  SELECT
    sample,
    COUNT(*) AS n_inventors,
    SUM(CASE WHEN type = 'T_Ever_Stayed' THEN 1 ELSE 0 END) AS five_year_stayers,
    SUM(CASE WHEN type = 'T_LEAVER' THEN 1 ELSE 0 END) AS five_year_leavers,
    SUM(CASE WHEN type IN ('T_Ever_Stayed', 'T_LEAVER') THEN 1 ELSE 0 END) AS five_year_active,
    SUM(CASE WHEN ever_stayed_unrestricted THEN 1 ELSE 0 END) AS unrestricted_stayers,
    SUM(CASE WHEN leaver_unrestricted THEN 1 ELSE 0 END) AS unrestricted_leavers,
    SUM(CASE WHEN active_unrestricted THEN 1 ELSE 0 END) AS unrestricted_active,
    SUM(CASE WHEN active_unrestricted AND type NOT IN ('T_Ever_Stayed', 'T_LEAVER') THEN 1 ELSE 0 END)
      AS additional_active_unrestricted,
    SUM(CASE WHEN late_active_after_5 THEN 1 ELSE 0 END) AS late_active_after_5,
    9779 AS cassi_ornaghi_active_benchmark
  FROM scoped
  GROUP BY sample
)
SELECT
  *,
  cassi_ornaghi_active_benchmark - five_year_active AS gap_to_cassi_5y,
  cassi_ornaghi_active_benchmark - unrestricted_active AS gap_to_cassi_unrestricted,
  CAST(unrestricted_stayers AS DOUBLE) / NULLIF(unrestricted_active, 0) AS unrestricted_stayer_share
FROM summary
ORDER BY sample
")

unrestricted_status_by_current_type <- DBI::dbGetQuery(con, "
WITH scoped AS (
  SELECT 'full_sample' AS sample, * FROM inventor_status_own
  UNION ALL
  SELECT 'clean_1993_2010' AS sample, * FROM inventor_status_own
  WHERE deal_year BETWEEN 1993 AND 2010
),
labeled AS (
  SELECT
    sample,
    type,
    CASE
      WHEN ever_stayed_unrestricted THEN 'T_Ever_Stayed_unrestricted'
      WHEN leaver_unrestricted THEN 'T_LEAVER_unrestricted'
      ELSE 'no_unrestricted_acquirer_or_outside'
    END AS unrestricted_status,
    late_active_after_5,
    late_acquirer_after_5,
    late_outside_after_5
  FROM scoped
)
SELECT
  sample,
  type,
  unrestricted_status,
  COUNT(*) AS n_inventors,
  SUM(CASE WHEN late_active_after_5 THEN 1 ELSE 0 END) AS n_late_active_after_5,
  SUM(CASE WHEN late_acquirer_after_5 THEN 1 ELSE 0 END) AS n_late_acquirer_after_5,
  SUM(CASE WHEN late_outside_after_5 THEN 1 ELSE 0 END) AS n_late_outside_after_5
FROM labeled
GROUP BY sample, type, unrestricted_status
ORDER BY sample, type, unrestricted_status
")

late_post5_activity_cases <- DBI::dbGetQuery(con, "
SELECT
  s.codinv,
  s.cassi_deal_group_id,
  s.dealnumber,
  s.deal_year,
  s.target_group,
  s.acquirer_group,
  s.type,
  s.ever_stayed_unrestricted,
  s.leaver_unrestricted,
  s.late_acquirer_after_5,
  s.late_outside_after_5,
  MIN(CASE WHEN ia.resolved_group = s.acquirer_group THEN ia.year END) AS first_late_acquirer_year,
  MIN(CASE
        WHEN ia.resolved_group IS NOT NULL
         AND CAST(ia.resolved_group AS VARCHAR) NOT LIKE '999%'
         AND ia.resolved_group <> s.acquirer_group
         AND ia.resolved_group <> s.target_group
        THEN ia.year
      END) AS first_late_outside_year
FROM inventor_status_own s
LEFT JOIN inventor_affiliation_own ia
  ON ia.codinv = s.codinv
 AND ia.year > s.deal_year + 5
WHERE s.type = 'T_NO_POST_5Y'
  AND s.late_active_after_5
GROUP BY
  s.codinv,
  s.cassi_deal_group_id,
  s.dealnumber,
  s.deal_year,
  s.target_group,
  s.acquirer_group,
  s.type,
  s.ever_stayed_unrestricted,
  s.leaver_unrestricted,
  s.late_acquirer_after_5,
  s.late_outside_after_5
ORDER BY s.deal_year, s.dealnumber, s.codinv
LIMIT 500
")

target_continuing_cases <- DBI::dbGetQuery(con, "
SELECT *
FROM inventor_status_own
WHERE type = 'T_TARGET_CONTINUING'
ORDER BY deal_year, dealnumber, codinv
LIMIT 500
")

unclassified_post_group_cases <- DBI::dbGetQuery(con, "
SELECT *
FROM inventor_status_own
WHERE type = 'T_UNCLASSIFIED_POST_GROUP'
ORDER BY deal_year, dealnumber, codinv
LIMIT 500
")

write_csv_base(spine_summary, "cassi_deal_spine_summary.csv")
write_csv_base(status_counts, "inventor_status_own_counts.csv")
write_csv_base(status_counts_clean, "inventor_status_own_counts_clean_window.csv")
write_csv_base(status_counts_by_year, "inventor_status_own_counts_by_deal_year.csv")
write_csv_base(horizon_stayer_counts, "horizon_stayer_counts.csv")
write_csv_base(retained_sample_counts, "retained_sample_counts.csv")
write_csv_base(multi_exposure_counts, "multi_exposure_counts.csv")
write_csv_base(validation, "validation_vs_reference.csv")
write_csv_base(deal_map_comparison, "deal_map_comparison.csv")
write_csv_base(sample_waterfall, "sample_waterfall.csv")
write_csv_base(unrestricted_status_comparison, "unrestricted_status_comparison.csv")
write_csv_base(unrestricted_status_by_current_type, "unrestricted_status_by_current_type.csv")
write_csv_base(late_post5_activity_cases, "late_post5_activity_cases.csv")
write_csv_base(target_continuing_cases, "target_continuing_cases.csv")
write_csv_base(unclassified_post_group_cases, "unclassified_post_group_cases.csv")
write_csv_base(DBI::dbGetQuery(con, "
  SELECT spine_issue, COUNT(*) AS n
  FROM cassi_deal_spine
  GROUP BY spine_issue
  ORDER BY n DESC
"), "cassi_deal_spine_issues.csv")

print(spine_summary)
print(status_counts)
print(status_counts_clean)
print(horizon_stayer_counts)
print(retained_sample_counts)
print(validation)
print(unrestricted_status_comparison)
print(deal_map_comparison)

message("\n", strrep("=", 60))
message("Preliminary inventor_status_own built. Imperfect validation is expected at this stage.")
message(strrep("=", 60), "\n")

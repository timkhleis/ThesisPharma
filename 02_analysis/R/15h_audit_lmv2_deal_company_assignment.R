# ============================================================================
# 15h_audit_lmv2_deal_company_assignment.R
# Read-only P2 audit of deal, target-company, and inventor assignment.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))

for (pkg in c("DBI", "duckdb", "haven")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

db_path <- file.path(BASE, "output", "thesis_foundation.duckdb")
audit_dir <- file.path(
  BASE, "output", "audit", "local_match_v2", "P2", "deal_company_review"
)
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

con <- DBI::dbConnect(duckdb::duckdb(), db_path)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

required <- c(
  "deal_assignment", "deal_target_company_strict",
  "deal_target_company_expanded", "inventor_status_reference",
  "patent_company_link", "patent_inventor", "inventor_year",
  "inventor_production", "inventor_affiliation_own", "target_cohort_own",
  "lmv2_treated_primary", "firm_group", "cassi_merge"
)
missing <- required[!vapply(
  required, function(table_name) DBI::dbExistsTable(con, table_name), logical(1)
)]
if (length(missing)) stop("Missing audit inputs: ", paste(missing, collapse = ", "))

write_query <- function(name, sql) {
  out <- DBI::dbGetQuery(con, sql)
  out$design_version <- LMV2_DESIGN_VERSION
  out$design_hash <- LMV2_DESIGN_HASH
  out <- out[, c("design_version", "design_hash", setdiff(
    names(out), c("design_version", "design_hash")
  ))]
  path <- file.path(audit_dir, paste0(name, ".csv"))
  utils::write.csv(out, path, row.names = FALSE, na = "")
  message("Written: ", normalizePath(path, mustWork = TRUE))
}

write_query("deal_route_funnel", "
SELECT
  match_source,
  COUNT(*) AS listed_deals,
  SUM(strict_eligible::INTEGER) AS strict_deals,
  SUM(expanded_eligible::INTEGER) AS expanded_deals,
  SUM(status_eligible::INTEGER) AS status_eligible_deals,
  SUM((target_year BETWEEN 1994 AND 2010)::INTEGER) AS listed_1994_2010,
  SUM((target_year BETWEEN 1994 AND 2010 AND strict_eligible)::INTEGER)
    AS strict_1994_2010,
  SUM((target_year BETWEEN 1994 AND 2010 AND expanded_eligible)::INTEGER)
    AS expanded_1994_2010
FROM deal_assignment
GROUP BY match_source
ORDER BY match_source
")

write_query("supplementary_rule_audit", "
SELECT
  deal_id, target_year, target_value, target_nmb, matched_dealnumber,
  n_target_nmb, year_gap, value_gap, n_target_groups, target_group,
  n_acquirer_groups, acquirer_group, todrop_tar, todrop_acq, divest,
  (
    match_source = 'MERGE_ID_SUPPLEMENT'
    AND n_target_nmb = 1
    AND year_gap = 0
    AND value_gap = 0
    AND n_target_groups = 1
    AND target_group IS NOT NULL
    AND n_acquirer_groups = 1
    AND acquirer_group IS NOT NULL
    AND NOT todrop_tar
    AND NOT todrop_acq
    AND NOT divest
  ) AS high_confidence_promotion,
  CASE
    WHEN divest THEN 'exclude_divestiture'
    WHEN todrop_tar THEN 'exclude_target_drop'
    WHEN todrop_acq OR acquirer_group IS NULL THEN 'exclude_acquirer_unusable'
    WHEN target_year NOT BETWEEN 1994 AND 2010 THEN 'outside_analysis_window'
    ELSE 'promote_by_rule'
  END AS audit_disposition
FROM deal_assignment
WHERE match_source = 'MERGE_ID_SUPPLEMENT'
ORDER BY deal_id
")

write_query("cassi_stayer_deal_crosswalk", "
WITH co AS (
  SELECT
    da.deal_id,
    da.target_year,
    da.target_value,
    da.target_nmb,
    da.match_source,
    da.strict_eligible,
    da.expanded_eligible,
    da.status_eligible,
    da.todrop_tar,
    da.todrop_acq,
    da.divest,
    da.n_target_groups,
    da.n_acquirer_groups,
    COUNT(*) AS cassi_stayers
  FROM inventor_status_reference r
  JOIN deal_assignment da USING (target_year, target_value)
  WHERE r.type = 'T_STAYER'
    AND r.stayer = 1
    AND r.target_year BETWEEN 1994 AND 2010
  GROUP BY ALL
)
SELECT
  *,
  CASE
    WHEN strict_eligible THEN 'strict_primary'
    WHEN match_source = 'MERGE_ID_SUPPLEMENT'
     AND target_year BETWEEN 1994 AND 2010
     AND expanded_eligible
     AND status_eligible
     AND NOT todrop_tar AND NOT todrop_acq AND NOT divest
     AND n_target_groups = 1 AND n_acquirer_groups = 1
      THEN 'promote_by_explicit_rule'
    WHEN match_source LIKE 'UNRESOLVED%' THEN 'unresolved_identifier_or_event'
    WHEN divest THEN 'excluded_divestiture'
    WHEN todrop_tar THEN 'excluded_target_drop'
    WHEN todrop_acq OR NOT status_eligible THEN 'excluded_acquirer_unusable'
    ELSE 'excluded_other'
  END AS audit_disposition
FROM co
ORDER BY strict_eligible, cassi_stayers DESC, deal_id
")

write_query("cassi_stayer_assignment_funnel", "
WITH co AS (
  SELECT r.*, da.deal_id, da.strict_eligible
  FROM inventor_status_reference r
  JOIN deal_assignment da USING (target_year, target_value)
  WHERE r.type = 'T_STAYER'
    AND r.stayer = 1
    AND r.target_year BETWEEN 1994 AND 2010
), tagged AS (
  SELECT
    co.*,
    EXISTS (
      SELECT 1
      FROM deal_target_company_strict dtc
      JOIN patent_company_link pcl
        ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
       AND pcl.year BETWEEN co.target_year - 5 AND co.target_year - 1
      JOIN patent_inventor pi
        ON pi.appln_id = pcl.appln_id
       AND CAST(pi.codinv AS BIGINT) = CAST(co.codinv AS BIGINT)
      WHERE dtc.deal_id = co.deal_id
    ) AS direct_target_company_pre5,
    t.codinv IS NOT NULL AS retained_earliest_exposure,
    p.codinv IS NOT NULL AS retained_primary_affiliation,
    COALESCE(p.status_eligible, FALSE) AS retained_status_eligible,
    p.qualification_route
  FROM co
  LEFT JOIN target_cohort_own t
    ON t.deal_id = co.deal_id
   AND t.codinv = CAST(co.codinv AS BIGINT)
  LEFT JOIN lmv2_treated_primary p
    ON p.deal_id = co.deal_id
   AND p.codinv = CAST(co.codinv AS BIGINT)
)
SELECT
  strict_eligible,
  direct_target_company_pre5,
  retained_earliest_exposure,
  retained_primary_affiliation,
  retained_status_eligible,
  qualification_route,
  COUNT(*) AS cassi_stayer_rows,
  COUNT(DISTINCT deal_id) AS deals
FROM tagged
GROUP BY ALL
ORDER BY ALL
")

write_query("cassi_stayer_company_rule_categories", "
WITH co AS (
  SELECT r.*, da.deal_id, da.target_group, da.acquirer_group
  FROM inventor_status_reference r
  JOIN deal_assignment da USING (target_year, target_value)
  WHERE r.type = 'T_STAYER'
    AND r.stayer = 1
    AND r.target_year BETWEEN 1994 AND 2010
    AND da.strict_eligible
), lost AS (
  SELECT co.*
  FROM co
  WHERE NOT EXISTS (
    SELECT 1
    FROM deal_target_company_strict dtc
    JOIN patent_company_link pcl
      ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
     AND pcl.year BETWEEN co.target_year - 5 AND co.target_year - 1
    JOIN patent_inventor pi
      ON pi.appln_id = pcl.appln_id
     AND CAST(pi.codinv AS BIGINT) = CAST(co.codinv AS BIGINT)
    WHERE dtc.deal_id = co.deal_id
  )
), evidence AS (
  SELECT
    l.*,
    EXISTS (
      SELECT 1 FROM patent_inventor pi
      WHERE CAST(pi.codinv AS BIGINT) = CAST(l.codinv AS BIGINT)
    ) AS in_canonical_patent_inventor,
    EXISTS (
      SELECT 1 FROM inventor_year iy
      WHERE iy.codinv = CAST(l.codinv AS BIGINT)
        AND iy.year BETWEEN l.target_year - 5 AND l.target_year - 1
    ) AS canonical_patent_in_pre5,
    EXISTS (
      SELECT 1
      FROM patent_inventor pi
      JOIN patent_company_link pcl ON pcl.appln_id = pi.appln_id
      WHERE CAST(pi.codinv AS BIGINT) = CAST(l.codinv AS BIGINT)
        AND pcl.year BETWEEN l.target_year - 5 AND l.target_year - 1
        AND pcl.id_group = l.target_group
    ) AS linked_to_target_group_pre5,
    EXISTS (
      SELECT 1
      FROM patent_inventor pi
      JOIN patent_company_link pcl ON pcl.appln_id = pi.appln_id
      WHERE CAST(pi.codinv AS BIGINT) = CAST(l.codinv AS BIGINT)
        AND pcl.year BETWEEN l.target_year - 5 AND l.target_year - 1
        AND pcl.id_group = l.acquirer_group
    ) AS linked_to_acquirer_group_pre5
  FROM lost l
)
SELECT
  (year BETWEEN target_year - 5 AND target_year - 1) AS cassi_status_year_in_pre5,
  in_canonical_patent_inventor,
  canonical_patent_in_pre5,
  linked_to_target_group_pre5,
  linked_to_acquirer_group_pre5,
  COUNT(*) AS cassi_stayer_rows,
  COUNT(DISTINCT deal_id) AS deals
FROM evidence
GROUP BY ALL
ORDER BY ALL
")

ownership_bucket_cte <- "
WITH co AS (
  SELECT r.*, da.deal_id, da.target_group, da.acquirer_group
  FROM inventor_status_reference r
  JOIN deal_assignment da USING (target_year, target_value)
  WHERE r.type = 'T_STAYER'
    AND r.stayer = 1
    AND r.target_year BETWEEN 1994 AND 2010
    AND da.strict_eligible
    AND r.year BETWEEN r.target_year - 5 AND r.target_year - 1
), ownership_bucket AS (
  SELECT co.*
  FROM co
  WHERE NOT EXISTS (
    SELECT 1
    FROM deal_target_company_strict dtc
    JOIN patent_company_link pcl
      ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
     AND pcl.year BETWEEN co.target_year - 5 AND co.target_year - 1
    JOIN patent_inventor pi
      ON pi.appln_id = pcl.appln_id
     AND CAST(pi.codinv AS BIGINT) = CAST(co.codinv AS BIGINT)
    WHERE dtc.deal_id = co.deal_id
  )
  AND EXISTS (
    SELECT 1
    FROM patent_inventor pi
    JOIN patent_company_link pcl ON pcl.appln_id = pi.appln_id
    WHERE CAST(pi.codinv AS BIGINT) = CAST(co.codinv AS BIGINT)
      AND pcl.year BETWEEN co.target_year - 5 AND co.target_year - 1
      AND pcl.id_group = co.acquirer_group
  )
)
"

write_query("ownership_relabel_census", paste0(ownership_bucket_cte, "
, history AS (
  SELECT
    b.deal_id,
    b.codinv,
    b.target_group,
    b.acquirer_group,
    MAX(CASE WHEN fg.year = b.target_year - 1 THEN fg.id_group END) AS group_gm1,
    MAX(CASE WHEN fg.year = b.target_year THEN fg.id_group END) AS group_g0,
    MAX(CASE WHEN fg.year = b.target_year + 1 THEN fg.id_group END) AS group_gp1
  FROM ownership_bucket b
  LEFT JOIN firm_group fg
    ON CAST(fg.compcod AS BIGINT) = CAST(b.compcod AS BIGINT)
   AND fg.year BETWEEN b.target_year - 1 AND b.target_year + 1
  GROUP BY b.deal_id, b.codinv, b.target_group, b.acquirer_group
)
SELECT
  COUNT(*) AS inventor_deal_rows,
  SUM((group_gm1 = target_group)::INTEGER) AS target_company_in_target_at_gm1,
  SUM((group_g0 = acquirer_group)::INTEGER) AS target_company_in_acquirer_at_g0,
  SUM((group_gp1 = acquirer_group)::INTEGER) AS target_company_in_acquirer_at_gp1,
  SUM((group_gm1 = target_group AND group_g0 = acquirer_group)::INTEGER)
    AS ownership_switch_at_deal,
  SUM((group_gm1 = target_group AND group_g0 = acquirer_group
       AND group_gp1 = acquirer_group)::INTEGER) AS switch_stable_through_gp1
FROM history
"))

write_query("ownership_relabel_spotcheck_20", paste0(ownership_bucket_cte, "
, picked AS (
  SELECT *
  FROM ownership_bucket
  QUALIFY ROW_NUMBER() OVER (PARTITION BY deal_id ORDER BY hash(codinv)) = 1
  ORDER BY hash(deal_id, codinv)
  LIMIT 20
), applications AS (
  SELECT
    p.deal_id,
    CAST(p.codinv AS BIGINT) AS codinv,
    COUNT(DISTINCT pcl.appln_id) AS acquirer_labelled_pre_apps,
    string_agg(
      DISTINCT CAST(CAST(pcl.appln_id AS BIGINT) AS VARCHAR), ';'
      ORDER BY CAST(CAST(pcl.appln_id AS BIGINT) AS VARCHAR)
    ) AS appln_ids,
    string_agg(
      DISTINCT CAST(CAST(pcl.compcod AS BIGINT) AS VARCHAR), ';'
      ORDER BY CAST(CAST(pcl.compcod AS BIGINT) AS VARCHAR)
    ) AS patent_owner_compcods
  FROM picked p
  JOIN patent_inventor pi
    ON CAST(pi.codinv AS BIGINT) = CAST(p.codinv AS BIGINT)
  JOIN patent_company_link pcl
    ON pcl.appln_id = pi.appln_id
   AND pcl.year BETWEEN p.target_year - 5 AND p.target_year - 1
   AND pcl.id_group = p.acquirer_group
  GROUP BY p.deal_id, p.codinv
), history AS (
  SELECT
    p.deal_id,
    CAST(p.codinv AS BIGINT) AS codinv,
    MAX(CASE WHEN fg.year = p.target_year - 1 THEN fg.id_group END) AS group_gm1,
    MAX(CASE WHEN fg.year = p.target_year THEN fg.id_group END) AS group_g0,
    MAX(CASE WHEN fg.year = p.target_year + 1 THEN fg.id_group END) AS group_gp1
  FROM picked p
  LEFT JOIN firm_group fg
    ON CAST(fg.compcod AS BIGINT) = CAST(p.compcod AS BIGINT)
   AND fg.year BETWEEN p.target_year - 1 AND p.target_year + 1
  GROUP BY p.deal_id, p.codinv
)
SELECT
  p.deal_id,
  CAST(p.codinv AS BIGINT) AS codinv,
  CAST(p.target_year AS INTEGER) AS target_year,
  CAST(p.year AS INTEGER) AS cassi_status_year,
  CAST(p.compcod AS BIGINT) AS cassi_target_compcod,
  f.name AS cassi_target_company,
  p.target_group,
  p.acquirer_group,
  h.group_gm1,
  h.group_g0,
  h.group_gp1,
  a.acquirer_labelled_pre_apps,
  a.appln_ids,
  a.patent_owner_compcods
FROM picked p
JOIN applications a
  ON a.deal_id = p.deal_id AND a.codinv = CAST(p.codinv AS BIGINT)
JOIN history h
  ON h.deal_id = p.deal_id AND h.codinv = CAST(p.codinv AS BIGINT)
LEFT JOIN firm f ON CAST(f.compcod AS BIGINT) = CAST(p.compcod AS BIGINT)
ORDER BY p.deal_id
"))

missing_bridge_ids <- DBI::dbGetQuery(con, "
WITH co AS (
  SELECT r.*, da.deal_id
  FROM inventor_status_reference r
  JOIN deal_assignment da USING (target_year, target_value)
  WHERE r.type = 'T_STAYER'
    AND r.stayer = 1
    AND r.target_year BETWEEN 1994 AND 2010
    AND da.strict_eligible
    AND r.year BETWEEN r.target_year - 5 AND r.target_year - 1
)
SELECT DISTINCT CAST(co.codinv AS BIGINT) AS codinv
FROM co
WHERE NOT EXISTS (
  SELECT 1 FROM patent_inventor pi
  WHERE CAST(pi.codinv AS BIGINT) = CAST(co.codinv AS BIGINT)
)
AND NOT EXISTS (
  SELECT 1
  FROM deal_target_company_strict dtc
  JOIN patent_company_link pcl
    ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
   AND pcl.year BETWEEN co.target_year - 5 AND co.target_year - 1
  JOIN patent_inventor pi
    ON pi.appln_id = pcl.appln_id
   AND CAST(pi.codinv AS BIGINT) = CAST(co.codinv AS BIGINT)
  WHERE dtc.deal_id = co.deal_id
)
")

raw_candidates <- c(
  file.path(getwd(), "01_Data", "patent_inventor.dta"),
  file.path(dirname(dirname(getwd())), "01_Data", "patent_inventor.dta")
)
raw_path <- raw_candidates[file.exists(raw_candidates)][1]
if (is.na(raw_path)) stop("Raw patent_inventor.dta not found for source check")

raw_bridge <- haven::read_dta(raw_path, col_select = c("appln_id", "codinv"))
source_check <- data.frame(
  raw_source_path = normalizePath(raw_path, mustWork = TRUE),
  raw_rows = nrow(raw_bridge),
  canonical_rows = DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM patent_inventor")$n,
  raw_distinct_pairs = nrow(unique(raw_bridge[c("appln_id", "codinv")])),
  canonical_distinct_pairs = DBI::dbGetQuery(con, "
    SELECT COUNT(DISTINCT (appln_id, codinv)) AS n FROM patent_inventor
  ")$n,
  missing_bucket_inventors = nrow(missing_bridge_ids),
  missing_bucket_found_in_raw = sum(
    missing_bridge_ids$codinv %in% as.numeric(raw_bridge$codinv)
  )
)
source_check$design_version <- LMV2_DESIGN_VERSION
source_check$design_hash <- LMV2_DESIGN_HASH
source_check <- source_check[, c(
  "design_version", "design_hash",
  setdiff(names(source_check), c("design_version", "design_hash"))
)]
source_check_path <- file.path(audit_dir, "missing_bridge_raw_source_check.csv")
utils::write.csv(source_check, source_check_path, row.names = FALSE, na = "")
message("Written: ", normalizePath(source_check_path, mustWork = TRUE))
rm(raw_bridge)

write_query("primary_latest_affiliation_resolution", "
SELECT
  qualification_route,
  latest_pre_candidate_group_count,
  latest_pre_resolved_by,
  COUNT(*) AS treated_inventors,
  COUNT(DISTINCT deal_id) AS deals
FROM lmv2_treated_primary
GROUP BY ALL
ORDER BY qualification_route, latest_pre_candidate_group_count,
         treated_inventors DESC
")

write_query("strict_deals_without_primary_inventors", "
WITH cohort AS (
  SELECT
    deal_id,
    COUNT(*) AS direct_company_inventors,
    SUM(target_resolved_latest::INTEGER) AS latest_target_inventors,
    SUM(target_to_acquirer_transition_strict::INTEGER) AS transition_inventors
  FROM target_cohort_own
  GROUP BY deal_id
), primary_cohort AS (
  SELECT deal_id, COUNT(*) AS primary_inventors
  FROM lmv2_treated_primary
  GROUP BY deal_id
)
SELECT
  da.deal_id, da.target_year, da.target_value, da.target, da.acquirer,
  da.n_target_companies, da.status_eligible,
  COALESCE(c.direct_company_inventors, 0) AS direct_company_inventors,
  COALESCE(c.latest_target_inventors, 0) AS latest_target_inventors,
  COALESCE(c.transition_inventors, 0) AS transition_inventors,
  COALESCE(p.primary_inventors, 0) AS primary_inventors
FROM deal_assignment da
LEFT JOIN cohort c USING (deal_id)
LEFT JOIN primary_cohort p USING (deal_id)
WHERE da.strict_eligible
  AND da.target_year BETWEEN 1994 AND 2010
  AND p.deal_id IS NULL
ORDER BY da.target_year, da.deal_id
")

write_query("target_company_bridge_checks", "
WITH checks AS (
  SELECT
    da.deal_id,
    dtc.target_compcod,
    COUNT(DISTINCT fg.id_group) AS groups_at_g_minus_1,
    MIN(fg.id_group) AS group_at_g_minus_1,
    da.target_group
  FROM deal_assignment da
  JOIN deal_target_company_strict dtc USING (deal_id)
  LEFT JOIN firm_group fg
    ON CAST(fg.compcod AS BIGINT) = dtc.target_compcod
   AND fg.year = CAST(da.target_year AS INTEGER) - 1
  WHERE da.strict_eligible
  GROUP BY da.deal_id, dtc.target_compcod, da.target_group
)
SELECT
  COUNT(*) AS deal_company_rows,
  SUM((groups_at_g_minus_1 = 0)::INTEGER) AS missing_group_rows,
  SUM((groups_at_g_minus_1 > 1)::INTEGER) AS ambiguous_group_rows,
  SUM((group_at_g_minus_1 <> target_group)::INTEGER) AS target_group_mismatches
FROM checks
")

write_query("acquirer_resolution_checks", "
SELECT
  acquirer_group_source,
  status_eligible,
  COUNT(*) AS deals,
  SUM((acquirer_group IS NULL)::INTEGER) AS missing_acquirer_group,
  SUM((CAST(acquirer_group AS VARCHAR) LIKE '999%')::INTEGER)
    AS placeholder_acquirer_group,
  SUM(todrop_acq::INTEGER) AS dropped_acquirer
FROM deal_assignment
WHERE strict_eligible
GROUP BY ALL
ORDER BY deals DESC
")

write_query("fallback_acquirer_history", "
WITH fallback AS (
  SELECT *
  FROM deal_assignment
  WHERE strict_eligible
    AND acquirer_group_source = 'target_post_group_fallback'
), history AS (
  SELECT
    f.deal_id,
    f.target_year,
    f.target_group,
    f.acquirer_group,
    fg.year,
    COUNT(DISTINCT fg.id_group) AS groups_in_year,
    MIN(fg.id_group) AS group_in_year
  FROM fallback f
  JOIN deal_target_company_strict dtc USING (deal_id)
  JOIN firm_group fg
    ON CAST(fg.compcod AS BIGINT) = dtc.target_compcod
   AND fg.year BETWEEN f.target_year - 1 AND f.target_year + 1
  GROUP BY f.deal_id, f.target_year, f.target_group, f.acquirer_group, fg.year
)
SELECT * FROM history ORDER BY deal_id, year
")

message("P2 deal/company assignment audit completed without modifying the database.")

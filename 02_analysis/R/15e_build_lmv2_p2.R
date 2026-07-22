# ============================================================================
# 15e_build_lmv2_p2.R -- P2 cohort, control, and power certification tables
# ============================================================================
# Design-only package. It constructs the frozen P2 interfaces and diagnostics;
# it does not match units or estimate treatment effects.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))

for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
AUDIT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P2")
PARQUET_DIR <- file.path(BASE, "output", "parquet", "derived")
dir.create(AUDIT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(PARQUET_DIR, recursive = TRUE, showWarnings = FALSE)

con <- DBI::dbConnect(duckdb::duckdb(), DUCKDB)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, "PRAGMA threads=4")

required <- c(
  "target_cohort_own", "cassi_deal_group_spine_expanded",
  "deal_target_company_strict", "deal_target_company_expanded",
  "deal_assignment", "inventor_affiliation_own", "inventor_status_reference",
  "inventor_production", "group_production", "patent_company_link",
  "patent_inventor", "firm_group"
)
missing <- required[!vapply(required, DBI::dbExistsTable, logical(1), conn = con)]
if (length(missing)) stop("Missing P2 inputs: ", paste(missing, collapse = ", "))

write_csv <- function(x, name) {
  x$design_version <- LMV2_DESIGN_VERSION
  x$design_hash <- LMV2_DESIGN_HASH
  x <- x[, c("design_version", "design_hash", setdiff(names(x), c("design_version", "design_hash")))]
  utils::write.csv(x, file.path(AUDIT_DIR, name), row.names = FALSE, na = "")
}

copy_table <- function(table_name) {
  path <- file.path(PARQUET_DIR, paste0(table_name, ".parquet"))
  sql_path <- gsub("\\\\", "/", path)
  DBI::dbExecute(con, sprintf(
    "COPY (SELECT * FROM %s ORDER BY ALL) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD, OVERWRITE TRUE)",
    DBI::dbQuoteIdentifier(con, table_name), sql_path
  ))
  normalizePath(path, mustWork = TRUE)
}

table_hash <- function(table_name) {
  rows <- DBI::dbGetQuery(con, sprintf("SELECT * FROM %s ORDER BY ALL", DBI::dbQuoteIdentifier(con, table_name)))
  digest::digest(rows, algo = "sha256", serialize = TRUE)
}

# ---------------------------------------------------------------------------
# Treated interfaces. target_cohort_own already retains the inventor's earliest
# deal-specific target-company exposure. P2 applies the prospectively locked
# latest-affiliation/strict-transition routes without changing that ordering.
# ---------------------------------------------------------------------------
DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_treated_broad AS
SELECT
  *,
  CAST(deal_year AS INTEGER) AS cohort,
  CASE
    WHEN deal_year BETWEEN 1994 AND 1999 THEN '1994-1999'
    WHEN deal_year BETWEEN 2000 AND 2004 THEN '2000-2004'
    WHEN deal_year BETWEEN 2005 AND 2010 THEN '2005-2010'
  END AS broad_era,
  (deal_year BETWEEN 1994 AND 2008) AS buffered_cohort
FROM target_cohort_own
WHERE deal_year BETWEEN 1994 AND 2010
")

DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_treated_primary AS
WITH base AS (
  SELECT
    b.*,
    CASE
      WHEN b.target_resolved_latest THEN 'latest_target_affiliation'
      WHEN b.target_to_acquirer_transition_strict THEN 'strict_target_to_acquirer_transition'
    END AS qualification_route
  FROM lmv2_treated_broad b
  WHERE b.target_resolved_latest OR b.target_to_acquirer_transition_strict
), first_post AS (
  SELECT
    b.codinv,
    b.deal_id,
    MIN(CAST(ia.year AS INTEGER)) AS first_post_patent_year
  FROM base b
  JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = b.codinv
   AND ia.year BETWEEN CAST(b.deal_year AS INTEGER)
                   AND CAST(b.deal_year AS INTEGER) + 5
  GROUP BY b.codinv, b.deal_id
), first_post_group_stayer AS (
  SELECT DISTINCT b.codinv, b.deal_id
  FROM base b
  JOIN first_post fp USING (codinv, deal_id)
  JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = b.codinv
   AND ia.year = fp.first_post_patent_year
   AND ia.resolved_group IN (b.target_group, b.acquirer_group)
), first_post_target_company_stayer AS (
  SELECT DISTINCT b.codinv, b.deal_id
  FROM base b
  JOIN first_post fp USING (codinv, deal_id)
  JOIN deal_target_company_strict dtc ON dtc.deal_id = b.deal_id
  JOIN patent_company_link pcl
    ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
   AND pcl.year = fp.first_post_patent_year
  JOIN patent_inventor pi
    ON pi.appln_id = pcl.appln_id
   AND CAST(pi.codinv AS BIGINT) = b.codinv
)
SELECT
  b.*,
  fp.first_post_patent_year,
  (g.codinv IS NOT NULL) AS stayer_group_first_post_t0_t5,
  (tc.codinv IS NOT NULL) AS stayer_target_company_first_post_t0_t5,
  (g.codinv IS NOT NULL OR tc.codinv IS NOT NULL)
    AS stayer_focal_entity_first_post_t0_t5,
  (b.status_eligible AND (g.codinv IS NOT NULL OR tc.codinv IS NOT NULL))
    AS status_eligible_stayer_first_post_t0_t5
FROM base b
LEFT JOIN first_post fp USING (codinv, deal_id)
LEFT JOIN first_post_group_stayer g USING (codinv, deal_id)
LEFT JOIN first_post_target_company_stayer tc USING (codinv, deal_id)
")

DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_treated_unique_affiliation_robustness AS
SELECT *
FROM lmv2_treated_primary
WHERE latest_pre_candidate_group_count = 1
ORDER BY cohort, deal_id, codinv
")

# ---------------------------------------------------------------------------
# Symmetric control interfaces. Firms must never be observed as targets and
# must have no acquirer event in the pseudo-event window g-5,...,g+5.
# Inventors must resolve uniquely to the candidate group at their latest
# pre-event affiliation and have no target exposure with deal year <= g+5.
# ---------------------------------------------------------------------------
DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_control_firm_eligibility AS
WITH stacks AS (
  SELECT UNNEST(range(1994, 2011)) AS cohort
), activity AS (
  SELECT
    s.cohort,
    CAST(pcl.id_group AS DOUBLE) AS control_group,
    COUNT(DISTINCT pcl.appln_id) AS pre_patent_stock,
    COUNT(DISTINCT CAST(pi.codinv AS BIGINT)) AS pre_inventor_count
  FROM stacks s
  JOIN patent_company_link pcl
    ON pcl.year BETWEEN s.cohort - 5 AND s.cohort - 1
  JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
  WHERE pcl.id_group IS NOT NULL
  GROUP BY s.cohort, pcl.id_group
), target_groups AS (
  SELECT DISTINCT CAST(target_group AS DOUBLE) AS id_group
  FROM deal_assignment
  WHERE target_group IS NOT NULL
  UNION
  SELECT DISTINCT CAST(fg.id_group AS DOUBLE) AS id_group
  FROM deal_assignment da
  JOIN deal_target_company_expanded dtc ON dtc.deal_id = da.deal_id
  JOIN firm_group fg
    ON CAST(fg.compcod AS BIGINT) = dtc.target_compcod
   AND fg.year = CAST(da.target_year AS INTEGER) - 1
  WHERE fg.id_group IS NOT NULL
), acquirer_events AS (
  SELECT DISTINCT
    CAST(acquirer_group AS DOUBLE) AS id_group,
    CAST(target_year AS INTEGER) AS event_year
  FROM deal_assignment
  WHERE acquirer_group IS NOT NULL
), last_patent AS (
  SELECT CAST(id_group AS DOUBLE) AS id_group, MAX(year) AS last_patent_year
  FROM patent_company_link
  WHERE id_group IS NOT NULL
  GROUP BY id_group
)
SELECT
  a.cohort,
  a.control_group,
  a.pre_patent_stock,
  a.pre_inventor_count,
  lp.last_patent_year,
  (lp.last_patent_year < a.cohort + 5) AS control_firm_exits_before_g_plus_5,
  FALSE AS ever_target,
  FALSE AS acquirer_event_g_minus_5_to_g_plus_5
FROM activity a
JOIN last_patent lp ON lp.id_group = a.control_group
WHERE NOT EXISTS (
  SELECT 1 FROM target_groups tg WHERE tg.id_group = a.control_group
)
AND NOT EXISTS (
  SELECT 1 FROM acquirer_events ae
  WHERE ae.id_group = a.control_group
    AND ae.event_year BETWEEN a.cohort - 5 AND a.cohort + 5
)
")

DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_control_inventor_eligibility AS
WITH stacks AS (
  SELECT UNNEST(range(1994, 2011)) AS cohort
), latest AS (
  SELECT
    s.cohort,
    CAST(ia.codinv AS BIGINT) AS codinv,
    ia.year AS latest_pre_affiliation_year,
    ia.resolved_group,
    ia.candidate_group_count,
    ia.candidate_group_list,
    ia.resolved_by,
    ROW_NUMBER() OVER (
      PARTITION BY s.cohort, ia.codinv ORDER BY ia.year DESC
    ) AS rn
  FROM stacks s
  JOIN inventor_affiliation_own ia
    ON ia.year BETWEEN s.cohort - 5 AND s.cohort - 1
), all_target_exposures AS (
  SELECT DISTINCT
    CAST(pi.codinv AS BIGINT) AS codinv,
    CAST(s.deal_year AS INTEGER) AS exposure_year
  FROM cassi_deal_group_spine_expanded s
  JOIN deal_target_company_expanded dtc ON dtc.deal_id = s.deal_id
  JOIN patent_company_link pcl
    ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
   AND pcl.year BETWEEN CAST(s.deal_year AS INTEGER) - 5
                    AND CAST(s.deal_year AS INTEGER) - 1
  JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
  WHERE pi.codinv IS NOT NULL
)
SELECT
  l.cohort,
  l.codinv,
  CAST(l.resolved_group AS DOUBLE) AS control_group,
  l.latest_pre_affiliation_year,
  l.cohort - l.latest_pre_affiliation_year AS qualifying_gap,
  l.candidate_group_count,
  l.candidate_group_list,
  l.resolved_by,
  cf.last_patent_year,
  cf.control_firm_exits_before_g_plus_5
FROM latest l
JOIN lmv2_control_firm_eligibility cf
  ON cf.cohort = l.cohort
 AND cf.control_group = l.resolved_group
WHERE l.rn = 1
  AND l.candidate_group_count = 1
  AND l.resolved_group IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM all_target_exposures te
    WHERE te.codinv = l.codinv
      AND te.exposure_year <= l.cohort + 5
  )
")

# ---------------------------------------------------------------------------
# Diagnostics and locked power gates.
# ---------------------------------------------------------------------------
treated_by_cohort <- DBI::dbGetQuery(con, "
SELECT
  cohort,
  COUNT(*) AS treated_inventors,
  COUNT(DISTINCT deal_id) AS treated_deals,
  SUM(status_eligible::INTEGER) AS status_eligible_inventors,
  SUM(status_eligible_stayer_first_post_t0_t5::INTEGER) AS status_eligible_stayers,
  COUNT(DISTINCT CASE WHEN status_eligible_stayer_first_post_t0_t5 THEN deal_id END)
    AS deals_with_status_eligible_stayers,
  SUM((qualification_route = 'strict_target_to_acquirer_transition')::INTEGER)
    AS transition_inventors,
  SUM(multi_exposure_inventor::INTEGER) AS repeated_exposure_inventors
FROM lmv2_treated_primary
GROUP BY cohort ORDER BY cohort
")
write_csv(treated_by_cohort, "treated_by_cohort.csv")

route_audit <- DBI::dbGetQuery(con, "
SELECT
  broad_era,
  COUNT(*) AS treated_inventors,
  SUM((qualification_route = 'strict_target_to_acquirer_transition')::INTEGER)
    AS transition_inventors,
  AVG((qualification_route = 'strict_target_to_acquirer_transition')::INTEGER)
    AS transition_share
FROM lmv2_treated_primary
GROUP BY GROUPING SETS ((broad_era), ())
ORDER BY broad_era NULLS LAST
")
route_audit$broad_era[is.na(route_audit$broad_era)] <- "overall"
write_csv(route_audit, "transition_route_audit.csv")

affiliation_audit <- DBI::dbGetQuery(con, "
SELECT
  COUNT(*) AS treated_inventors,
  SUM((qualification_route = 'latest_target_affiliation'
       AND NOT target_resolved_latest)::INTEGER) AS invalid_latest_routes,
  SUM((qualification_route = 'strict_target_to_acquirer_transition'
       AND NOT target_to_acquirer_transition_strict)::INTEGER) AS invalid_transition_routes,
  SUM((last_pre_affiliation_group IS NULL)::INTEGER) AS unresolved_latest_affiliations,
  SUM((qualification_route = 'latest_target_affiliation'
       AND last_pre_affiliation_group <> target_group)::INTEGER)
    AS latest_group_mismatches,
  SUM((qualification_route = 'strict_target_to_acquirer_transition'
       AND last_pre_affiliation_group <> acquirer_group)::INTEGER)
    AS transition_group_mismatches
FROM lmv2_treated_primary
")
write_csv(affiliation_audit, "treated_affiliation_certification.csv")

tie_breaker_audit <- DBI::dbGetQuery(con, "
SELECT
  qualification_route,
  latest_pre_candidate_group_count,
  latest_pre_resolved_by,
  COUNT(*) AS treated_inventors,
  COUNT(DISTINCT deal_id) AS treated_deals
FROM lmv2_treated_primary
GROUP BY ALL
ORDER BY qualification_route, latest_pre_candidate_group_count,
         treated_inventors DESC
")
write_csv(tie_breaker_audit, "treated_tie_breaker_audit.csv")

unique_robustness <- DBI::dbGetQuery(con, "
WITH scoped AS (
  SELECT '1994-2010' AS sample, *
  FROM lmv2_treated_unique_affiliation_robustness
  UNION ALL
  SELECT '1994-2008' AS sample, *
  FROM lmv2_treated_unique_affiliation_robustness
  WHERE cohort <= 2008
), deal_sizes AS (
  SELECT sample, deal_id, COUNT(*) AS n_stayers
  FROM scoped
  WHERE status_eligible_stayer_first_post_t0_t5
  GROUP BY sample, deal_id
), deal_summary AS (
  SELECT
    sample,
    SUM(n_stayers) * SUM(n_stayers) / SUM(n_stayers * n_stayers)
      AS raw_inventor_weighted_deal_ess
  FROM deal_sizes
  GROUP BY sample
)
SELECT
  s.sample,
  COUNT(*) AS treated_inventors,
  COUNT(DISTINCT s.deal_id) AS treated_deals,
  SUM(s.status_eligible_stayer_first_post_t0_t5::INTEGER)
    AS status_eligible_stayers,
  COUNT(DISTINCT CASE
    WHEN s.status_eligible_stayer_first_post_t0_t5 THEN s.deal_id END)
    AS deals_with_stayers,
  d.raw_inventor_weighted_deal_ess
FROM scoped s
JOIN deal_summary d USING (sample)
GROUP BY s.sample, d.raw_inventor_weighted_deal_ess
ORDER BY s.sample
")
write_csv(unique_robustness, "treated_unique_affiliation_robustness.csv")

promotion_audit <- DBI::dbGetQuery(con, "
SELECT
  deal_id, target_year, target_value, target_nmb, matched_dealnumber,
  match_source, n_target_groups, target_group, n_acquirer_groups,
  acquirer_group, acquirer_group_history_consistent,
  todrop_tar, todrop_acq, divest, strict_eligible
FROM deal_assignment
WHERE match_source = 'MERGE_ID_SUPPLEMENT'
ORDER BY deal_id
")
write_csv(promotion_audit, "supplementary_deal_promotion_audit.csv")

composition <- DBI::dbGetQuery(con, "
SELECT
  CASE WHEN cohort <= 2008 THEN '1994-2008' ELSE '2009-2010' END AS cohort_block,
  COUNT(*) AS treated_inventors,
  COUNT(DISTINCT deal_id) AS treated_deals,
  SUM(status_eligible_stayer_first_post_t0_t5::INTEGER) AS status_eligible_stayers,
  COUNT(DISTINCT CASE WHEN status_eligible_stayer_first_post_t0_t5 THEN deal_id END)
    AS deals_with_stayers,
  AVG(big_deal::INTEGER) AS big_deal_inventor_share,
  AVG(multi_exposure_inventor::INTEGER) AS repeated_exposure_share
FROM lmv2_treated_primary
GROUP BY cohort_block ORDER BY cohort_block
")
write_csv(composition, "buffered_vs_late_composition.csv")

power <- DBI::dbGetQuery(con, "
WITH scoped AS (
  SELECT '1994-2010' AS sample, * FROM lmv2_treated_primary
  UNION ALL
  SELECT '1994-2008' AS sample, * FROM lmv2_treated_primary WHERE cohort <= 2008
), deal_sizes AS (
  SELECT sample, deal_id, COUNT(*) AS n_stayers
  FROM scoped
  WHERE status_eligible_stayer_first_post_t0_t5
  GROUP BY sample, deal_id
), summary AS (
  SELECT
    sample,
    SUM(n_stayers) AS status_eligible_stayers,
    COUNT(*) AS deals_with_stayers,
    SUM(n_stayers) * SUM(n_stayers) / SUM(n_stayers * n_stayers)
      AS raw_inventor_weighted_deal_ess
  FROM deal_sizes GROUP BY sample
)
SELECT
  *,
  status_eligible_stayers >= 3000 AS pass_minimum_stayers,
  deals_with_stayers >= 150 AS pass_minimum_deals,
  raw_inventor_weighted_deal_ess >= 20 AS pass_minimum_ess,
  (status_eligible_stayers >= 3000 AND deals_with_stayers >= 150
   AND raw_inventor_weighted_deal_ess >= 20) AS pass_all_power_gates
FROM summary ORDER BY sample
")
write_csv(power, "buffered_stayer_power_gates.csv")

benchmark <- data.frame(
  metric = c("treated_inventors", "treated_deals", "status_eligible_stayers",
             "deals_with_status_eligible_stayers", "raw_deal_ess"),
  provisional_full_1994_2010 = c(28643, 339, 4157, 198, 31.98),
  provisional_buffered_1994_2008 = c(24074, 290, 3656, 169, 25.97),
  stringsAsFactors = FALSE
)
full <- power[power$sample == "1994-2010", ]
buf <- power[power$sample == "1994-2008", ]
counts <- DBI::dbGetQuery(con, "
SELECT
  COUNT(*) AS treated_inventors,
  COUNT(DISTINCT deal_id) AS treated_deals
FROM lmv2_treated_primary
UNION ALL
SELECT COUNT(*), COUNT(DISTINCT deal_id)
FROM lmv2_treated_primary WHERE cohort <= 2008
")
benchmark$post_repair_full_1994_2010 <- c(
  counts$treated_inventors[1], counts$treated_deals[1],
  full$status_eligible_stayers, full$deals_with_stayers,
  full$raw_inventor_weighted_deal_ess
)
benchmark$post_repair_buffered_1994_2008 <- c(
  counts$treated_inventors[2], counts$treated_deals[2],
  buf$status_eligible_stayers, buf$deals_with_stayers,
  buf$raw_inventor_weighted_deal_ess
)
benchmark$explanation <- c(
  "latest-affiliation/transition rule plus approved supplementary promotions",
  "latest-affiliation/transition rule plus approved supplementary promotions",
  "first observed post-event patent in t=0..5 must remain with focal entity",
  "same first-post status rule; event year zero does not enter post outcomes",
  "recomputed from corrected first-post stayer deal shares"
)
write_csv(benchmark, "provisional_benchmark_reconciliation.csv")

stayer_definition <- DBI::dbGetQuery(con, "
WITH scoped AS (
  SELECT '1994-2010' AS sample, * FROM lmv2_treated_primary
  UNION ALL
  SELECT '1994-2008' AS sample, * FROM lmv2_treated_primary WHERE cohort <= 2008
), positive_group_t1_t5 AS (
  SELECT DISTINCT s.sample, s.codinv, s.deal_id
  FROM scoped s
  JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = s.codinv
   AND ia.year BETWEEN s.cohort + 1 AND s.cohort + 5
   AND ia.resolved_group IN (s.target_group, s.acquirer_group)
  WHERE s.status_eligible
), positive_target_company_t1_t5 AS (
  SELECT DISTINCT s.sample, s.codinv, s.deal_id
  FROM scoped s
  JOIN deal_target_company_strict dtc ON dtc.deal_id = s.deal_id
  JOIN patent_company_link pcl
    ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
   AND pcl.year BETWEEN s.cohort + 1 AND s.cohort + 5
  JOIN patent_inventor pi
    ON pi.appln_id = pcl.appln_id
   AND CAST(pi.codinv AS BIGINT) = s.codinv
  WHERE s.status_eligible
), positive_focal_t1_t5 AS (
  SELECT * FROM positive_group_t1_t5
  UNION
  SELECT * FROM positive_target_company_t1_t5
)
SELECT
  s.sample,
  SUM((p.codinv IS NOT NULL)::INTEGER) AS positive_focal_t1_t5,
  SUM(s.status_eligible_stayer_first_post_t0_t5::INTEGER)
    AS first_post_focal_t0_t5,
  SUM((s.status_eligible AND s.stayer_group_first_post_t0_t5)::INTEGER)
    AS first_post_group_path,
  SUM((s.status_eligible
       AND s.stayer_target_company_first_post_t0_t5)::INTEGER)
    AS first_post_target_company_path,
  SUM((s.status_eligible_stayer_first_post_t0_t5
       AND s.first_post_patent_year = s.cohort)::INTEGER)
    AS first_post_focal_at_t0,
  SUM((p.codinv IS NOT NULL
       AND NOT s.status_eligible_stayer_first_post_t0_t5)::INTEGER)
    AS positive_rule_only,
  SUM((p.codinv IS NULL
       AND s.status_eligible_stayer_first_post_t0_t5)::INTEGER)
    AS first_post_rule_only
FROM scoped s
LEFT JOIN positive_focal_t1_t5 p
  ON p.sample = s.sample AND p.codinv = s.codinv AND p.deal_id = s.deal_id
GROUP BY s.sample ORDER BY s.sample
")
write_csv(stayer_definition, "stayer_definition_reconciliation.csv")

control_firms <- DBI::dbGetQuery(con, "
SELECT
  cohort,
  COUNT(*) AS eligible_control_firms,
  SUM(control_firm_exits_before_g_plus_5::INTEGER) AS exits_before_g_plus_5,
  AVG(control_firm_exits_before_g_plus_5::INTEGER) AS exit_share
FROM lmv2_control_firm_eligibility
GROUP BY cohort ORDER BY cohort
")
write_csv(control_firms, "control_firms_by_cohort.csv")

control_inventors <- DBI::dbGetQuery(con, "
SELECT
  cohort,
  COUNT(*) AS eligible_control_inventors,
  COUNT(DISTINCT control_group) AS eligible_control_firms,
  SUM(control_firm_exits_before_g_plus_5::INTEGER)
    AS inventors_at_exiting_control_firms,
  AVG(control_firm_exits_before_g_plus_5::INTEGER)
    AS inventor_weighted_exit_share
FROM lmv2_control_inventor_eligibility
GROUP BY cohort ORDER BY cohort
")
write_csv(control_inventors, "control_inventors_by_cohort.csv")

control_cert <- DBI::dbGetQuery(con, "
WITH all_target_exposures AS (
  SELECT DISTINCT CAST(pi.codinv AS BIGINT) AS codinv,
                  CAST(s.deal_year AS INTEGER) AS exposure_year
  FROM cassi_deal_group_spine_expanded s
  JOIN deal_target_company_expanded dtc ON dtc.deal_id = s.deal_id
  JOIN patent_company_link pcl
    ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
   AND pcl.year BETWEEN CAST(s.deal_year AS INTEGER) - 5
                    AND CAST(s.deal_year AS INTEGER) - 1
  JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
)
SELECT
  COUNT(*) AS control_inventor_cohort_rows,
  SUM((candidate_group_count <> 1)::INTEGER) AS nonunique_affiliations,
  SUM((control_group IS NULL)::INTEGER) AS unresolved_affiliations,
  SUM(EXISTS(
    SELECT 1 FROM all_target_exposures te
    WHERE te.codinv = c.codinv AND te.exposure_year <= c.cohort + 5
  )::INTEGER) AS contaminated_controls
FROM lmv2_control_inventor_eligibility c
")
write_csv(control_cert, "control_inventor_certification.csv")

# Cassi-Ornaghi crosswalk. The paper's 1,000,751 is the sum of its 760,047
# separation observations and 240,704 exit-model observations, not the row
# count of a single raw inventor-year panel.
co_reproduction <- DBI::dbGetQuery(con, "
WITH status_counts AS (
  SELECT
    *,
    COUNT(*) OVER (PARTITION BY codinv) AS n_status_rows,
    SUM((type = 'N_LEAVER')::INTEGER) OVER (PARTITION BY codinv) AS n_n_leaver,
    COUNT(DISTINCT id_group) OVER (PARTITION BY codinv) AS n_groups
  FROM inventor_status_reference
), filtered AS (
  SELECT * FROM status_counts
  WHERE n_status_rows > 1
    AND CASE WHEN n_groups = 0 THEN 0
             ELSE n_n_leaver::DOUBLE / n_groups END <= 1
), merged AS (
  SELECT f.*
  FROM filtered f
  JOIN inventor_production ip USING (codinv, year)
  JOIN group_production gp USING (id_group, year)
)
SELECT
  COUNT(DISTINCT codinv) AS reproduced_inventors,
  COUNT(*) AS reproduced_status_rows,
  SUM((type <> 'last year')::INTEGER) AS reproduced_separation_observations,
  SUM((type = 'T_STAYER')::INTEGER) AS reproduced_target_stayers,
  SUM((type = 'T_LEAVER')::INTEGER) AS reproduced_target_leavers,
  SUM((type IN ('N_STAYER', 'A_STAYER'))::INTEGER)
    AS reproduced_nontarget_stayers,
  SUM((type IN ('N_LEAVER', 'A_LEAVER'))::INTEGER)
    AS reproduced_nontarget_leavers
FROM merged
")
write_csv(co_reproduction, "cassi_ornaghi_exact_reproduction.csv")

thesis_summary <- DBI::dbGetQuery(con, "
SELECT
  COUNT(*) AS primary_treated_inventors,
  COUNT(DISTINCT deal_id) AS primary_treated_deals,
  SUM(status_eligible_stayer_first_post_t0_t5::INTEGER)
    AS full_status_eligible_stayers,
  SUM((cohort <= 2008 AND status_eligible_stayer_first_post_t0_t5)::INTEGER)
    AS buffered_status_eligible_stayers,
  SUM((n_target_pre_years >= 2)::INTEGER) AS recurrent_preperiod_inventors
FROM lmv2_treated_primary
")

sample_crosswalk <- data.frame(
  row = c(
    "inventors_in_paper_analytic_universe",
    "separation_observations",
    "exit_model_observations",
    "reported_combined_observations",
    "target_stayers",
    "target_leavers",
    "nontarget_stayers",
    "nontarget_leavers",
    "thesis_primary_treated_inventors_1994_2010",
    "thesis_primary_treated_deals_1994_2010",
    "thesis_status_eligible_stayers_1994_2010",
    "thesis_status_eligible_stayers_1994_2008",
    "thesis_preperiod_recurrent_inventors"
  ),
  cassi_ornaghi_published = c(
    311358, 760047, 240704, 1000751, 7104, 2675, 643267, 107001,
    NA, NA, NA, NA, NA
  ),
  reproduced_or_thesis = c(
    co_reproduction$reproduced_inventors,
    co_reproduction$reproduced_separation_observations,
    NA, NA,
    co_reproduction$reproduced_target_stayers,
    co_reproduction$reproduced_target_leavers,
    co_reproduction$reproduced_nontarget_stayers,
    co_reproduction$reproduced_nontarget_leavers,
    thesis_summary$primary_treated_inventors,
    thesis_summary$primary_treated_deals,
    thesis_summary$full_status_eligible_stayers,
    thesis_summary$buffered_status_eligible_stayers,
    thesis_summary$recurrent_preperiod_inventors
  ),
  reason_for_difference = c(
    "exact paper status and merge filters",
    "exact paper separation-sample filters",
    "paper-specific exit model restrictions; no thesis analogue",
    "sum of separation and exit-model samples, not one panel",
    "paper post-selected status; thesis uses deal-specific cohort and first-post focal entity",
    "paper post-selected status; thesis does not make leavers a contribution",
    "paper non-target status sample; thesis controls are cohort-specific and certified",
    "paper non-target status sample; thesis controls are cohort-specific and certified",
    "deal-specific target company + latest affiliation/transition + earliest exposure",
    "1994-2010 primary deal assignment including rule-based supplementary promotions",
    "first post patent in t=0..5 identifies status; post outcomes remain t=1..5",
    "same first-post status rule with buffered cohorts",
    "diagnostic only: at least two distinct target-company patent years in g-5..g-1"
  ),
  stringsAsFactors = FALSE
)
write_csv(sample_crosswalk, "cassi_ornaghi_thesis_sample_crosswalk.csv")

# Export stable interfaces and a manifest with logical (order-invariant) hashes.
interface_tables <- c(
  "lmv2_treated_primary", "lmv2_treated_broad",
  "lmv2_treated_unique_affiliation_robustness",
  "lmv2_control_firm_eligibility", "lmv2_control_inventor_eligibility"
)
paths <- vapply(interface_tables, copy_table, character(1))
manifest <- data.frame(
  table = interface_tables,
  rows = vapply(interface_tables, function(x) DBI::dbGetQuery(
    con, sprintf("SELECT COUNT(*) AS n FROM %s", DBI::dbQuoteIdentifier(con, x))
  )$n, numeric(1)),
  logical_sha256 = vapply(interface_tables, table_hash, character(1)),
  parquet_path = unname(paths),
  stringsAsFactors = FALSE
)
write_csv(manifest, "p2_interface_manifest.csv")

message("P2 build complete. Power gate result:")
print(power)

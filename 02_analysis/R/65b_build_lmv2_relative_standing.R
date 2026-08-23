# ============================================================================
# 65b_build_lmv2_relative_standing.R -- outcome-blind moderator construction
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "65a_lmv2_relative_standing_config.R"))

cfg <- LMV2_RELSTAND
out_dir <- cfg$output_dir
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
temp_dir <- file.path(out_dir, "duckdb_tmp_build")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

required <- c(
  cfg$inputs$database, cfg$inputs$inherited_moderators,
  cfg$inputs$inherited_moderator_manifest, cfg$freeze_path
)
if (!all(file.exists(required))) {
  stop("Missing relative-standing input: ",
       paste(required[!file.exists(required)], collapse = ", "))
}
inherited_manifest <- utils::read.csv(
  cfg$inputs$inherited_moderator_manifest, stringsAsFactors = FALSE
)
if (nrow(inherited_manifest) != 1L ||
    inherited_manifest$moderator_parquet_sha256 != digest::digest(
      file = cfg$inputs$inherited_moderators, algo = "sha256"
    )) {
  stop("Inherited outcome-blind moderator artifact is stale")
}

con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = normalizePath(cfg$inputs$database, winslash = "/", mustWork = TRUE),
  read_only = TRUE
)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf("PRAGMA threads=%d", cfg$execution$threads))
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", cfg$execution$memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", DBI::dbQuoteString(con, temp_dir)
))

base_path <- normalizePath(
  cfg$inputs$inherited_moderators, winslash = "/", mustWork = TRUE
)
t0 <- Sys.time()

DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE rs_base AS
SELECT
  deal_id, cohort, arm, codinv, roster_row_id, focal_group_1,
  patent_count_5y, log_patent_count_5y, patent_trajectory, career_age,
  focal_group_tenure, focal_group_exclusivity,
  stable_team_patent_share
FROM read_parquet(%s)
WHERE cohort BETWEEN 1993 AND 2010
", DBI::dbQuoteString(con, base_path)))

DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_deal_map AS
SELECT
  deal_id, MIN(cohort) cohort,
  MIN(CAST(acquirer_group AS BIGINT)) acquirer_group,
  COUNT(DISTINCT cohort) n_cohorts,
  COUNT(DISTINCT acquirer_group) n_acquirer_groups
FROM lmv2_treated_primary
WHERE deal_id IN (SELECT DISTINCT deal_id FROM rs_base)
GROUP BY deal_id
")

DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_roster AS
SELECT
  b.*, CAST(b.focal_group_1 AS BIGINT) focal_group,
  d.acquirer_group,
  CASE WHEN regexp_matches(CAST(d.acquirer_group AS VARCHAR), '^999')
       THEN TRUE ELSE FALSE END placeholder_acquirer
FROM rs_base b
JOIN rs_deal_map d USING (deal_id)
")

DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_focal_cells AS
SELECT DISTINCT deal_id, cohort, arm, focal_group FROM rs_roster
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_acquirer_cells AS
SELECT DISTINCT deal_id, cohort, acquirer_group
FROM rs_roster
WHERE acquirer_group IS NOT NULL
  AND NOT placeholder_acquirer
  AND NOT regexp_matches(CAST(acquirer_group AS VARCHAR), '^999')
")

# The only dated inputs used below end at cohort-1.
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_focal_patent_inventor AS
SELECT DISTINCT
  c.deal_id, c.cohort, c.arm, c.focal_group,
  CAST(pi.codinv AS BIGINT) codinv,
  CAST(pi.appln_id AS BIGINT) appln_id,
  CAST(pcl.year AS INTEGER) patent_year
FROM rs_focal_cells c
JOIN patent_company_link pcl
  ON CAST(pcl.id_group AS BIGINT)=c.focal_group
 AND pcl.year BETWEEN c.cohort-5 AND c.cohort-1
JOIN patent_inventor pi ON pi.appln_id=pcl.appln_id
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_acquirer_patent_inventor AS
SELECT DISTINCT
  c.deal_id, c.cohort, c.acquirer_group,
  CAST(pi.codinv AS BIGINT) codinv,
  CAST(pi.appln_id AS BIGINT) appln_id,
  CAST(pcl.year AS INTEGER) patent_year
FROM rs_acquirer_cells c
JOIN patent_company_link pcl
  ON CAST(pcl.id_group AS BIGINT)=c.acquirer_group
 AND pcl.year BETWEEN c.cohort-5 AND c.cohort-1
JOIN patent_inventor pi ON pi.appln_id=pcl.appln_id
")

DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_focal_productivity AS
SELECT
  deal_id, cohort, arm, focal_group, codinv,
  COUNT(DISTINCT appln_id) focal_patents_5y
FROM rs_focal_patent_inventor
GROUP BY 1,2,3,4,5
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_combined_productivity AS
WITH pooled AS (
  SELECT deal_id, cohort, arm, focal_group, codinv, appln_id
  FROM rs_focal_patent_inventor
  UNION ALL
  SELECT a.deal_id, a.cohort, x.arm, x.focal_group,
         a.codinv, a.appln_id
  FROM rs_acquirer_patent_inventor a
  JOIN rs_focal_cells x
    USING (deal_id, cohort)
)
SELECT
  deal_id, cohort, arm, focal_group, codinv,
  COUNT(DISTINCT appln_id) combined_patents_5y
FROM pooled
GROUP BY 1,2,3,4,5
")

DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_focal_standing AS
SELECT
  *,
  COUNT(*) OVER (
    PARTITION BY deal_id, cohort, arm, focal_group
  ) focal_inventors,
  100.0 * (RANK() OVER (
    PARTITION BY deal_id, cohort, arm, focal_group
    ORDER BY focal_patents_5y
  ) - 1) / COUNT(*) OVER (
    PARTITION BY deal_id, cohort, arm, focal_group
  ) focal_standing_pct
FROM rs_focal_productivity
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_combined_standing AS
SELECT
  *,
  COUNT(*) OVER (
    PARTITION BY deal_id, cohort, arm, focal_group
  ) combined_inventors,
  100.0 * (RANK() OVER (
    PARTITION BY deal_id, cohort, arm, focal_group
    ORDER BY combined_patents_5y
  ) - 1) / COUNT(*) OVER (
    PARTITION BY deal_id, cohort, arm, focal_group
  ) combined_standing_pct
FROM rs_combined_productivity
")

DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE rs_moderators AS
SELECT
  r.* EXCLUDE(focal_group),
  f.focal_patents_5y, f.focal_inventors, f.focal_standing_pct,
  c.combined_patents_5y, c.combined_inventors,
  c.combined_standing_pct,
  f.focal_standing_pct-c.combined_standing_pct
    relative_standing_loss_pp,
  (f.focal_standing_pct-c.combined_standing_pct)/%d.0
    relative_standing_loss_10pp,
  CASE WHEN f.focal_standing_pct-c.combined_standing_pct>0
       THEN 1 ELSE 0 END positive_standing_loss,
  CASE WHEN r.patent_count_5y>=%d THEN 1 ELSE 0 END productive_3plus,
  CASE
    WHEN f.focal_inventors>=%d AND f.focal_standing_pct>=80 THEN 1
    WHEN f.focal_inventors>=%d THEN 0 ELSE NULL
  END kapoor_top20,
  CASE
    WHEN r.acquirer_group IS NULL THEN 'missing_acquirer_group'
    WHEN r.placeholder_acquirer
      OR regexp_matches(CAST(r.acquirer_group AS VARCHAR), '^999')
      THEN 'placeholder_acquirer_group'
    WHEN f.codinv IS NULL THEN 'roster_inventor_missing_from_focal_pool'
    WHEN c.codinv IS NULL THEN 'roster_inventor_missing_from_combined_pool'
    ELSE 'eligible'
  END standing_eligibility
FROM rs_roster r
LEFT JOIN rs_focal_standing f
  ON f.deal_id=r.deal_id AND f.cohort=r.cohort AND f.arm=r.arm
 AND f.focal_group=r.focal_group_1 AND f.codinv=r.codinv
LEFT JOIN rs_combined_standing c
  ON c.deal_id=r.deal_id AND c.cohort=r.cohort AND c.arm=r.arm
 AND c.focal_group=r.focal_group_1 AND c.codinv=r.codinv
", cfg$construction$contrast_percentage_points,
   cfg$construction$productive_threshold,
   cfg$construction$top20_minimum_focal_inventors,
   cfg$construction$top20_minimum_focal_inventors))

moderator_path <- normalizePath(
  file.path(out_dir, "relative_standing_moderators.parquet"),
  winslash = "/", mustWork = FALSE
)
if (file.exists(moderator_path) && !file.remove(moderator_path)) {
  stop("Could not replace stale relative-standing moderator artifact")
}
DBI::dbExecute(con, sprintf(
  "COPY (SELECT * FROM rs_moderators ORDER BY cohort,deal_id,arm,codinv)
   TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
  DBI::dbQuoteString(con, moderator_path)
))

eligibility <- DBI::dbGetQuery(con, "
SELECT
  standing_eligibility, arm, COUNT(*) roster_rows,
  COUNT(DISTINCT codinv) distinct_inventors,
  COUNT(DISTINCT deal_id) deals
FROM rs_moderators GROUP BY 1,2 ORDER BY 1,2
")
utils::write.csv(
  eligibility, file.path(out_dir, "relative_standing_eligibility.csv"),
  row.names = FALSE
)

distribution <- DBI::dbGetQuery(con, "
SELECT
  arm, COUNT(*) n,
  AVG(relative_standing_loss_pp) mean,
  STDDEV_POP(relative_standing_loss_pp) sd,
  MIN(relative_standing_loss_pp) min,
  QUANTILE_CONT(relative_standing_loss_pp,0.10) p10,
  QUANTILE_CONT(relative_standing_loss_pp,0.25) p25,
  MEDIAN(relative_standing_loss_pp) p50,
  QUANTILE_CONT(relative_standing_loss_pp,0.75) p75,
  QUANTILE_CONT(relative_standing_loss_pp,0.90) p90,
  QUANTILE_CONT(relative_standing_loss_pp,0.95) p95,
  MAX(relative_standing_loss_pp) max,
  AVG(CASE WHEN relative_standing_loss_pp>0 THEN 1.0 ELSE 0.0 END)
    share_positive,
  AVG(CASE WHEN relative_standing_loss_pp=0 THEN 1.0 ELSE 0.0 END)
    share_zero,
  CORR(log_patent_count_5y,relative_standing_loss_pp)
    corr_absolute_productivity
FROM rs_moderators
WHERE standing_eligibility='eligible'
GROUP BY arm ORDER BY arm
")
utils::write.csv(
  distribution, file.path(out_dir, "relative_standing_distribution.csv"),
  row.names = FALSE
)

by_productivity <- DBI::dbGetQuery(con, "
SELECT
  arm,
  CASE WHEN patent_count_5y=1 THEN '1 patent'
       WHEN patent_count_5y=2 THEN '2 patents'
       ELSE '3+ patents' END productivity_group,
  COUNT(*) n,
  AVG(relative_standing_loss_pp) mean_loss_pp,
  MEDIAN(relative_standing_loss_pp) median_loss_pp,
  QUANTILE_CONT(relative_standing_loss_pp,0.10) p10,
  QUANTILE_CONT(relative_standing_loss_pp,0.90) p90,
  AVG(CASE WHEN relative_standing_loss_pp>0 THEN 1.0 ELSE 0.0 END)
    share_positive
FROM rs_moderators
WHERE standing_eligibility='eligible'
GROUP BY 1,2 ORDER BY 1,2
")
utils::write.csv(
  by_productivity,
  file.path(out_dir, "relative_standing_by_productivity.csv"),
  row.names = FALSE
)

small_focal <- DBI::dbGetQuery(con, "
WITH cells AS (
  SELECT deal_id, cohort, MIN(focal_inventors) focal_inventors
  FROM rs_moderators
  WHERE arm='treated'
  GROUP BY 1,2
)
SELECT
  COUNT(*) treated_deals,
  SUM(CASE WHEN focal_inventors<5 THEN 1 ELSE 0 END) deals_below_five,
  MIN(focal_inventors) min_inventors,
  MEDIAN(focal_inventors) median_inventors,
  MAX(focal_inventors) max_inventors
FROM cells
")
utils::write.csv(
  small_focal, file.path(out_dir, "relative_standing_focal_size.csv"),
  row.names = FALSE
)

audit <- DBI::dbGetQuery(con, "
SELECT
  (SELECT COUNT(*) FROM rs_base) base_rows,
  COUNT(*) moderator_rows,
  COUNT(DISTINCT roster_row_id) unique_moderator_rows,
  SUM(CASE WHEN standing_eligibility='eligible'
            AND (relative_standing_loss_pp < -100
              OR relative_standing_loss_pp > 100)
           THEN 1 ELSE 0 END) range_violations,
  SUM(CASE WHEN standing_eligibility='eligible'
            AND (focal_standing_pct IS NULL
              OR combined_standing_pct IS NULL)
           THEN 1 ELSE 0 END) eligible_missing_values,
  (SELECT COUNT(*) FROM rs_focal_patent_inventor
   WHERE patent_year>cohort-1) focal_future_rows,
  (SELECT COUNT(*) FROM rs_acquirer_patent_inventor
   WHERE patent_year>cohort-1) acquirer_future_rows,
  (SELECT COUNT(*) FROM rs_deal_map
   WHERE n_cohorts<>1 OR n_acquirer_groups>1) nonunique_deal_mappings,
  (SELECT COUNT(*)
   FROM rs_focal_cells f
   LEFT JOIN (
     SELECT DISTINCT deal_id, cohort, arm, focal_group
     FROM rs_combined_standing
   ) c USING (deal_id, cohort, arm, focal_group)
   WHERE c.focal_group IS NULL) combined_missing_focal_cells
FROM rs_moderators
")
checks <- data.frame(
  check = c(
    "one_moderator_row_per_inherited_roster_row",
    "standing_loss_in_valid_range",
    "eligible_rows_have_complete_standing",
    "focal_inputs_end_before_treatment",
    "acquirer_inputs_end_before_treatment",
    "deal_acquirer_mapping_is_unique",
    "combined_pool_is_focal_specific",
    "both_arms_have_eligible_rows"
  ),
  pass = c(
    audit$base_rows == audit$moderator_rows &&
      audit$moderator_rows == audit$unique_moderator_rows,
    audit$range_violations == 0,
    audit$eligible_missing_values == 0,
    audit$focal_future_rows == 0,
    audit$acquirer_future_rows == 0,
    audit$nonunique_deal_mappings == 0,
    audit$combined_missing_focal_cells == 0,
    all(c("treated", "control") %in%
          eligibility$arm[eligibility$standing_eligibility == "eligible"])
  ),
  stringsAsFactors = FALSE
)
lmv2_relstand_assert(checks)
utils::write.csv(
  checks, file.path(out_dir, "relative_standing_build_certification.csv"),
  row.names = FALSE
)

manifest <- data.frame(
  design_hash = lmv2_relstand_hash(),
  freeze_sha256 = digest::digest(file = cfg$freeze_path, algo = "sha256"),
  inherited_moderator_sha256 = digest::digest(
    file = cfg$inputs$inherited_moderators, algo = "sha256"
  ),
  relative_standing_sha256 = digest::digest(
    file = moderator_path, algo = "sha256"
  ),
  moderator_rows = audit$moderator_rows,
  maximum_input_event_time = -1L,
  outcome_estimates_written = 0L,
  runtime_minutes = as.numeric(difftime(Sys.time(), t0, units = "mins")),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "relative_standing_build_manifest.csv"),
  row.names = FALSE
)
message("Relative-standing moderator build certified: ",
        manifest$moderator_rows, " rows.")

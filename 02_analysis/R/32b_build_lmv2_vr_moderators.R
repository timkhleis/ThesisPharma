# ============================================================================
# 32b_build_lmv2_vr_moderators.R -- outcome-blind VR moderator construction
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
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))

cfg <- LMV2_VR_HET
out_dir <- cfg$output_dir
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
temp_dir <- file.path(out_dir, "duckdb_tmp_build")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

required_files <- c(
  cfg$inputs$database,
  cfg$inputs$inherited_moderators,
  cfg$inputs$inherited_moderator_manifest,
  cfg$freeze_path
)
if (!all(file.exists(required_files))) {
  stop("Missing VR moderator input: ",
       paste(required_files[!file.exists(required_files)], collapse = ", "))
}
inherited_manifest <- utils::read.csv(
  cfg$inputs$inherited_moderator_manifest, stringsAsFactors = FALSE
)
if (nrow(inherited_manifest) != 1L ||
    inherited_manifest$moderator_parquet_sha256 != digest::digest(
      file = cfg$inputs$inherited_moderators, algo = "sha256"
    )) {
  stop("Inherited outcome-blind moderator table is stale")
}

db_path <- normalizePath(
  cfg$inputs$database, winslash = "/", mustWork = TRUE
)
base_path <- normalizePath(
  cfg$inputs$inherited_moderators, winslash = "/", mustWork = TRUE
)
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf(
  "PRAGMA threads=%d", cfg$execution$threads
))
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", cfg$execution$memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", DBI::dbQuoteString(con, temp_dir)
))

t0 <- Sys.time()
for (tbl in c(
  "patent_inventor_enriched", "inventor_ipc_year",
  "group_ipc_year", "lmv2_treated_primary"
)) {
  if (!DBI::dbExistsTable(con, tbl)) stop("Missing table: ", tbl)
}

# Never inherit the old roster weight. Estimation obtains the certified P5c
# weight directly from the panel in 32c.
DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE vr_base AS
SELECT
  deal_id,cohort,arm,codinv,roster_row_id,focal_group_1,
  patent_count_5y,log_patent_count_5y,patent_trajectory,career_age,
  focal_group_tenure,focal_group_exclusivity
FROM read_parquet(%s)
", DBI::dbQuoteString(con, base_path)))

DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE vr_deal_map AS
SELECT
  deal_id,MIN(cohort) cohort,
  MIN(CAST(target_group AS BIGINT)) target_group,
  MIN(CAST(acquirer_group AS BIGINT)) acquirer_group,
  COUNT(DISTINCT cohort) n_cohorts,
  COUNT(DISTINCT target_group) n_target_groups,
  COUNT(DISTINCT acquirer_group) n_acquirer_groups
FROM lmv2_treated_primary
WHERE deal_id IN (SELECT DISTINCT deal_id FROM vr_base)
GROUP BY deal_id
")

# A persistent relationship requires repeated collaboration over time, not two
# applications in the same year.
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE vr_unit_patents AS
SELECT DISTINCT
  b.roster_row_id,b.cohort,b.deal_id,b.arm,b.codinv,
  CAST(p.appln_id AS BIGINT) appln_id,
  CAST(p.year AS INTEGER) patent_year
FROM vr_base b
JOIN patent_inventor_enriched p
  ON CAST(p.codinv AS BIGINT)=b.codinv
 AND p.year BETWEEN b.cohort-5 AND b.cohort-1
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE vr_pairs AS
SELECT
  u.roster_row_id,u.appln_id,u.patent_year,
  CAST(p.codinv AS BIGINT) co_codinv
FROM vr_unit_patents u
JOIN patent_inventor_enriched p
  ON CAST(p.appln_id AS BIGINT)=u.appln_id
 AND CAST(p.codinv AS BIGINT)<>u.codinv
")
DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE vr_persistent_ties AS
SELECT
  roster_row_id,co_codinv,
  COUNT(DISTINCT appln_id) joint_patents,
  COUNT(DISTINCT patent_year) joint_years
FROM vr_pairs
GROUP BY roster_row_id,co_codinv
HAVING COUNT(DISTINCT appln_id)>=%d
   AND COUNT(DISTINCT patent_year)>=%d
", cfg$construction$persistent_min_joint_patents,
   cfg$construction$persistent_min_joint_years))
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE vr_team_metrics AS
WITH patent_flags AS (
  SELECT
    u.roster_row_id,u.appln_id,u.patent_year,
    COUNT(DISTINCT t.co_codinv)>0 has_persistent_tie
  FROM vr_unit_patents u
  LEFT JOIN vr_pairs p
    ON p.roster_row_id=u.roster_row_id AND p.appln_id=u.appln_id
  LEFT JOIN vr_persistent_ties t
    ON t.roster_row_id=p.roster_row_id AND t.co_codinv=p.co_codinv
  GROUP BY u.roster_row_id,u.appln_id,u.patent_year
), patent_summary AS (
  SELECT
    roster_row_id,
    COUNT(*) predeal_patents_reconstructed,
    MAX(patent_year) last_team_input_year,
    AVG(CAST(has_persistent_tie AS DOUBLE)) persistent_patent_share
  FROM patent_flags GROUP BY roster_row_id
), tie_summary AS (
  SELECT
    roster_row_id,
    COUNT(*) persistent_collaborator_count,
    MAX(joint_patents) strongest_joint_patents,
    MAX(joint_years) longest_joint_years
  FROM vr_persistent_ties GROUP BY roster_row_id
)
SELECT
  p.*,
  COALESCE(t.persistent_collaborator_count,0)
    persistent_collaborator_count,
  COALESCE(t.strongest_joint_patents,0) strongest_joint_patents,
  COALESCE(t.longest_joint_years,0) longest_joint_years,
  COALESCE(t.strongest_joint_patents,0)/
    NULLIF(p.predeal_patents_reconstructed,0) strongest_tie_share
FROM patent_summary p
LEFT JOIN tie_summary t USING (roster_row_id)
")

# Compute inventor portfolios once per cohort-inventor. The same control can
# legitimately receive a different TechFit when reused for a different focal
# acquirer.
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE vr_cohort_inventor AS
SELECT DISTINCT cohort,codinv FROM vr_base
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE vr_inventor_ipc4 AS
SELECT
  u.cohort,u.codinv,SUBSTR(i.ipc_code,1,4) ipc4,
  SUM(CAST(i.patent_count AS DOUBLE)) weight_full,
  SUM(CASE WHEN i.year BETWEEN u.cohort-5 AND u.cohort-1
           THEN CAST(i.patent_count AS DOUBLE) ELSE 0 END) weight_5y,
  MIN(i.year) first_input_year,MAX(i.year) last_input_year
FROM vr_cohort_inventor u
JOIN inventor_ipc_year i
  ON CAST(i.codinv AS BIGINT)=u.codinv AND i.year<u.cohort
WHERE i.ipc_code IS NOT NULL AND LENGTH(i.ipc_code)>=4
GROUP BY u.cohort,u.codinv,SUBSTR(i.ipc_code,1,4)
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE vr_acquirer_ipc4 AS
SELECT
  d.deal_id,SUBSTR(i.ipc_code,1,4) ipc4,
  SUM(CAST(i.patent_count AS DOUBLE)) weight_full,
  SUM(CASE WHEN i.year BETWEEN d.cohort-5 AND d.cohort-1
           THEN CAST(i.patent_count AS DOUBLE) ELSE 0 END) weight_5y,
  MIN(i.year) first_input_year,MAX(i.year) last_input_year
FROM vr_deal_map d
JOIN group_ipc_year i
  ON CAST(i.id_group AS BIGINT)=d.acquirer_group AND i.year<d.cohort
WHERE i.ipc_code IS NOT NULL AND LENGTH(i.ipc_code)>=4
  AND d.acquirer_group IS NOT NULL
  AND NOT regexp_matches(CAST(d.acquirer_group AS VARCHAR),'^999')
GROUP BY d.deal_id,SUBSTR(i.ipc_code,1,4)
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE vr_techfit AS
WITH inv_norm AS (
  SELECT
    cohort,codinv,
    SQRT(SUM(weight_full*weight_full)) inv_norm_full,
    SQRT(SUM(weight_5y*weight_5y)) inv_norm_5y,
    MIN(first_input_year) inv_first_year,
    MAX(last_input_year) inv_last_year
  FROM vr_inventor_ipc4 GROUP BY cohort,codinv
), acq_norm AS (
  SELECT
    deal_id,
    SQRT(SUM(weight_full*weight_full)) acq_norm_full,
    SQRT(SUM(weight_5y*weight_5y)) acq_norm_5y,
    MIN(first_input_year) acq_first_year,
    MAX(last_input_year) acq_last_year
  FROM vr_acquirer_ipc4 GROUP BY deal_id
), dots AS (
  SELECT
    b.roster_row_id,
    SUM(i.weight_full*a.weight_full) dot_full,
    SUM(i.weight_5y*a.weight_5y) dot_5y
  FROM vr_base b
  JOIN vr_inventor_ipc4 i
    ON i.cohort=b.cohort AND i.codinv=b.codinv
  JOIN vr_acquirer_ipc4 a
    ON a.deal_id=b.deal_id AND a.ipc4=i.ipc4
  GROUP BY b.roster_row_id
)
SELECT
  b.roster_row_id,d.acquirer_group,
  n.inv_norm_full,n.inv_norm_5y,
  a.acq_norm_full,a.acq_norm_5y,
  n.inv_first_year,n.inv_last_year,a.acq_first_year,a.acq_last_year,
  COALESCE(x.dot_full,0) dot_full,
  COALESCE(x.dot_5y,0) dot_5y,
  CASE
    WHEN d.acquirer_group IS NULL THEN 'missing_acquirer_group'
    WHEN regexp_matches(CAST(d.acquirer_group AS VARCHAR),'^999')
      THEN 'placeholder_acquirer_group'
    WHEN n.inv_norm_full IS NULL OR n.inv_norm_full<=0
      THEN 'missing_inventor_ipc4_portfolio'
    WHEN a.acq_norm_full IS NULL OR a.acq_norm_full<=0
      THEN 'missing_acquirer_ipc4_portfolio'
    ELSE 'eligible'
  END techfit_full_reason,
  CASE
    WHEN d.acquirer_group IS NULL THEN 'missing_acquirer_group'
    WHEN regexp_matches(CAST(d.acquirer_group AS VARCHAR),'^999')
      THEN 'placeholder_acquirer_group'
    WHEN n.inv_norm_5y IS NULL OR n.inv_norm_5y<=0
      THEN 'missing_inventor_ipc4_portfolio'
    WHEN a.acq_norm_5y IS NULL OR a.acq_norm_5y<=0
      THEN 'missing_acquirer_ipc4_portfolio'
    ELSE 'eligible'
  END techfit_5y_reason,
  CASE WHEN n.inv_norm_full>0 AND a.acq_norm_full>0
    THEN COALESCE(x.dot_full,0)/(n.inv_norm_full*a.acq_norm_full)
    ELSE NULL END techfit_full,
  CASE WHEN n.inv_norm_5y>0 AND a.acq_norm_5y>0
    THEN COALESCE(x.dot_5y,0)/(n.inv_norm_5y*a.acq_norm_5y)
    ELSE NULL END techfit_5y
FROM vr_base b
JOIN vr_deal_map d USING (deal_id)
LEFT JOIN inv_norm n ON n.cohort=b.cohort AND n.codinv=b.codinv
LEFT JOIN acq_norm a USING (deal_id)
LEFT JOIN dots x USING (roster_row_id)
")

DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE vr_moderators AS
SELECT
  b.*,t.predeal_patents_reconstructed,t.last_team_input_year,
  t.persistent_collaborator_count,t.persistent_patent_share,
  t.strongest_joint_patents,t.longest_joint_years,t.strongest_tie_share,
  f.acquirer_group,f.techfit_full_reason,f.techfit_5y_reason,
  f.techfit_full,f.techfit_5y,
  f.inv_first_year,f.inv_last_year,f.acq_first_year,f.acq_last_year,
  CASE WHEN t.persistent_collaborator_count>0 THEN 1 ELSE 0 END team_any
FROM vr_base b
JOIN vr_team_metrics t USING (roster_row_id)
JOIN vr_techfit f USING (roster_row_id)
")

moderator_path <- normalizePath(
  file.path(out_dir, "vr_moderators.parquet"),
  winslash = "/", mustWork = FALSE
)
if (file.exists(moderator_path) && !file.remove(moderator_path)) {
  stop("Could not replace stale VR moderator artifact")
}
DBI::dbExecute(con, sprintf("
COPY (
  SELECT * FROM vr_moderators
  ORDER BY cohort,deal_id,arm,codinv,roster_row_id
) TO %s (FORMAT PARQUET,COMPRESSION ZSTD)
", DBI::dbQuoteString(con, moderator_path)))

team_counts <- DBI::dbGetQuery(con, "
SELECT
  arm,team_any,COUNT(*) roster_rows,
  COUNT(DISTINCT codinv) distinct_inventors,
  COUNT(DISTINCT deal_id) nominal_deals
FROM vr_moderators
GROUP BY arm,team_any ORDER BY arm,team_any
")
utils::write.csv(
  team_counts, file.path(out_dir, "team_persistence_counts.csv"),
  row.names = FALSE
)
techfit_funnel <- DBI::dbGetQuery(con, "
SELECT
  'full_history' variant,techfit_full_reason reason,arm,
  COUNT(*) roster_rows,COUNT(DISTINCT codinv) distinct_inventors,
  COUNT(DISTINCT deal_id) nominal_deals
FROM vr_moderators GROUP BY techfit_full_reason,arm
UNION ALL
SELECT
  'five_year',techfit_5y_reason,arm,
  COUNT(*),COUNT(DISTINCT codinv),COUNT(DISTINCT deal_id)
FROM vr_moderators GROUP BY techfit_5y_reason,arm
ORDER BY variant,reason,arm
")
utils::write.csv(
  techfit_funnel, file.path(out_dir, "techfit_coverage_funnel.csv"),
  row.names = FALSE
)
techfit_summary <- DBI::dbGetQuery(con, "
SELECT
  arm,
  COUNT(techfit_full) n_full,
  AVG(techfit_full) mean_full,
  MEDIAN(techfit_full) median_full,
  QUANTILE_CONT(techfit_full,0.25) p25_full,
  QUANTILE_CONT(techfit_full,0.75) p75_full,
  COUNT(techfit_5y) n_5y,
  AVG(techfit_5y) mean_5y,
  MEDIAN(techfit_5y) median_5y,
  CORR(techfit_full,techfit_5y) correlation_full_5y
FROM vr_moderators GROUP BY arm ORDER BY arm
")
utils::write.csv(
  techfit_summary, file.path(out_dir, "techfit_distribution.csv"),
  row.names = FALSE
)

audit <- DBI::dbGetQuery(con, "
SELECT
  (SELECT COUNT(*) FROM vr_base) roster_rows,
  (SELECT COUNT(*) FROM vr_base WHERE arm='treated') treated_rows,
  (SELECT COUNT(*) FROM vr_moderators) moderator_rows,
  (SELECT COUNT(DISTINCT roster_row_id) FROM vr_moderators) unique_rows,
  (SELECT COUNT(*) FROM vr_moderators
   WHERE predeal_patents_reconstructed<>patent_count_5y)
    patent_reconstruction_mismatches,
  (SELECT COUNT(*) FROM vr_moderators
   WHERE last_team_input_year>=cohort) team_future_violations,
  (SELECT COUNT(*) FROM vr_moderators
   WHERE inv_last_year>=cohort OR acq_last_year>=cohort)
    techfit_future_violations,
  (SELECT COUNT(*) FROM vr_moderators
   WHERE persistent_patent_share<0 OR persistent_patent_share>1
      OR strongest_tie_share<0 OR strongest_tie_share>1)
    team_share_violations,
  (SELECT COUNT(*) FROM vr_moderators
   WHERE techfit_full IS NOT NULL
     AND (techfit_full < -1e-12 OR techfit_full > 1+1e-12))
    techfit_full_bound_violations,
  (SELECT COUNT(*) FROM vr_moderators
   WHERE techfit_5y IS NOT NULL
     AND (techfit_5y < -1e-12 OR techfit_5y > 1+1e-12))
    techfit_5y_bound_violations,
  (SELECT COUNT(*) FROM vr_moderators
   WHERE techfit_full_reason<>'eligible' AND techfit_full IS NOT NULL)
    ineligible_full_values,
  (SELECT COUNT(*) FROM vr_moderators
   WHERE techfit_5y_reason<>'eligible' AND techfit_5y IS NOT NULL)
    ineligible_5y_values,
  (SELECT COUNT(*) FROM vr_deal_map
   WHERE n_cohorts<>1 OR n_target_groups<>1 OR n_acquirer_groups>1)
    nonunique_deal_mappings
")
treated_team <- team_counts[team_counts$arm == "treated", ]
checks <- data.frame(
  check = c(
    "one_moderator_row_per_certified_roster_row",
    "predeal_patent_counts_reproduce_p3",
    "team_inputs_are_strictly_pre_treatment",
    "techfit_inputs_are_strictly_pre_treatment",
    "team_metrics_are_bounded",
    "techfit_values_are_bounded",
    "ineligible_techfit_is_never_silently_zero",
    "deal_to_acquirer_mapping_is_unique",
    "temporal_team_split_exhausts_amended_treated_roster",
    "both_team_groups_have_treated_support"
  ),
  pass = c(
    audit$roster_rows == audit$moderator_rows &&
      audit$moderator_rows == audit$unique_rows,
    audit$patent_reconstruction_mismatches == 0,
    audit$team_future_violations == 0,
    audit$techfit_future_violations == 0,
    audit$team_share_violations == 0,
    audit$techfit_full_bound_violations == 0 &&
      audit$techfit_5y_bound_violations == 0,
    audit$ineligible_full_values == 0 && audit$ineligible_5y_values == 0,
    audit$nonunique_deal_mappings == 0,
    identical(sort(as.integer(treated_team$team_any)), 0:1) &&
      sum(treated_team$roster_rows) == audit$treated_rows,
    all(treated_team$roster_rows >= 500L)
  ),
  stringsAsFactors = FALSE
)
lmv2_vr_assert_checks(checks)
utils::write.csv(
  audit, file.path(out_dir, "moderator_build_audit.csv"), row.names = FALSE
)
utils::write.csv(
  checks, file.path(out_dir, "moderator_build_certification.csv"),
  row.names = FALSE
)

manifest <- data.frame(
  design_hash = lmv2_vr_hash(),
  freeze_sha256 = digest::digest(file = cfg$freeze_path, algo = "sha256"),
  source_sha256 = digest::digest(
    file = file.path(BASE, "R", "32b_build_lmv2_vr_moderators.R"),
    algo = "sha256"
  ),
  inherited_moderator_sha256 = digest::digest(
    file = cfg$inputs$inherited_moderators, algo = "sha256"
  ),
  moderator_sha256 = digest::digest(
    file = moderator_path, algo = "sha256"
  ),
  moderator_rows = audit$moderator_rows,
  outcome_columns_written = 0L,
  runtime_minutes = as.numeric(
    difftime(Sys.time(), t0, units = "mins")
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "moderator_build_manifest.csv"),
  row.names = FALSE
)
message(
  "Certified VR moderators: ", manifest$moderator_rows,
  " rows in ", round(manifest$runtime_minutes, 2), " minutes."
)

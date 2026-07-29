# ============================================================================
# Build and certify symmetric t=-7/-6 landmark units for PPSCM v2
# ============================================================================
# This stage does not query the outcome panel.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(
  BASE, "R", "39a_lmv2_ppscm_second_attempt_config.R"))
config <- lmv2_ppscm_v2_config()
lmv2_ppscm_assert_freeze(config)
dir.create(config$units_dir, recursive = TRUE, showWarnings = FALSE)

source_path <- file.path(
  BASE, "R", "39b_build_lmv2_ppscm_symmetric_units.R")
config_path <- file.path(
  BASE, "R", "39a_lmv2_ppscm_second_attempt_config.R")
source_sha256 <- lmv2_ppscm_sha256(source_path)
config_sha256 <- lmv2_ppscm_sha256(config_path)
freeze_sha256 <- lmv2_ppscm_sha256(config$freeze_path)

con <- DBI::dbConnect(
  duckdb::duckdb(), dbdir = config$db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(
  con, sprintf("PRAGMA threads=%d", config$execution$threads))
DBI::dbExecute(
  con, sprintf("PRAGMA memory_limit='%s'",
               config$execution$memory_limit))

required <- c(
  "lmv2_treated_primary", "deal_assignment", "firm_group",
  "cassi_deal_group_spine_expanded", "deal_target_company_expanded",
  "deal_target_company_strict", "patent_company_link",
  "patent_inventor", "inventor_affiliation_own")
missing <- required[
  !vapply(required, DBI::dbExistsTable, logical(1), conn = con)]
if (length(missing)) {
  stop("Missing symmetric-unit inputs: ", paste(missing, collapse = ", "))
}

message("PPSCM v2 Stage B: construct target-exposure exclusion")
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_all_target_exposures AS
SELECT DISTINCT CAST(pi.codinv AS BIGINT) codinv,
       CAST(s.deal_year AS INTEGER) exposure_year
FROM cassi_deal_group_spine_expanded s
JOIN deal_target_company_expanded dtc USING(deal_id)
JOIN patent_company_link pcl
  ON CAST(pcl.compcod AS BIGINT)=dtc.target_compcod
 AND pcl.year BETWEEN CAST(s.deal_year AS INTEGER)-5
                  AND CAST(s.deal_year AS INTEGER)-1
JOIN patent_inventor pi ON pi.appln_id=pcl.appln_id
WHERE pi.codinv IS NOT NULL
"))

message("PPSCM v2 Stage B: construct landmark treated units")
invisible(DBI::dbExecute(con, sprintf("
CREATE TEMP TABLE pp2_accepted_deals AS
SELECT DISTINCT CAST(deal_id AS BIGINT) deal_id,
       CAST(cohort AS INTEGER) cohort,
       CAST(target_group AS BIGINT) target_group
FROM lmv2_treated_primary
WHERE cohort BETWEEN %d AND %d
", min(config$cohorts), max(config$cohorts))))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_treated_focal_patent AS
SELECT DISTINCT d.deal_id,d.cohort,d.target_group,
       CAST(pi.codinv AS BIGINT) codinv
FROM pp2_accepted_deals d
JOIN deal_target_company_strict dtc USING(deal_id)
JOIN patent_company_link pcl
  ON CAST(pcl.compcod AS BIGINT)=dtc.target_compcod
 AND pcl.year BETWEEN d.cohort-7 AND d.cohort-6
JOIN patent_inventor pi ON pi.appln_id=pcl.appln_id
WHERE pi.codinv IS NOT NULL
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_treated_latest AS
SELECT f.*,CAST(ia.year AS INTEGER) landmark_affiliation_year,
       CAST(ia.resolved_group AS BIGINT) resolved_group,
       CAST(ia.candidate_group_count AS INTEGER) candidate_group_count,
       ROW_NUMBER() OVER (
         PARTITION BY f.deal_id,f.codinv ORDER BY ia.year DESC) affiliation_rank
FROM pp2_treated_focal_patent f
JOIN inventor_affiliation_own ia
  ON CAST(ia.codinv AS BIGINT)=f.codinv
 AND ia.year BETWEEN f.cohort-7 AND f.cohort-6
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_treated_eligible AS
SELECT * FROM pp2_treated_latest
WHERE affiliation_rank=1
  AND candidate_group_count=1
  AND resolved_group=target_group
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_treated_units AS
WITH ranked AS (
  SELECT *,ROW_NUMBER() OVER (
    PARTITION BY codinv ORDER BY cohort,deal_id) exposure_rank
  FROM pp2_treated_eligible
)
SELECT cohort,'treated' arm,codinv,deal_id,
       deal_id cluster_id,target_group focal_group,
       landmark_affiliation_year,
       COUNT(*) OVER (PARTITION BY cohort,deal_id) cohort_size,
       'landmark:treated:'||CAST(cohort AS VARCHAR)||':'||
       CAST(deal_id AS VARCHAR)||':'||CAST(codinv AS VARCHAR) unit_id
FROM ranked WHERE exposure_rank=1
"))

message("PPSCM v2 Stage B: construct landmark control units")
invisible(DBI::dbExecute(con, sprintf("
CREATE TEMP TABLE pp2_control_latest AS
WITH cohorts AS (
  SELECT UNNEST(range(%d,%d))::INTEGER cohort
)
SELECT s.cohort,CAST(ia.codinv AS BIGINT) codinv,
       CAST(ia.year AS INTEGER) landmark_affiliation_year,
       CAST(ia.resolved_group AS BIGINT) resolved_group,
       CAST(ia.candidate_group_count AS INTEGER) candidate_group_count,
       ROW_NUMBER() OVER (
         PARTITION BY s.cohort,CAST(ia.codinv AS BIGINT)
         ORDER BY ia.year DESC) affiliation_rank
FROM cohorts s
JOIN inventor_affiliation_own ia
  ON ia.year BETWEEN s.cohort-7 AND s.cohort-6
", min(config$cohorts), max(config$cohorts) + 1L)))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_target_groups AS
SELECT DISTINCT CAST(target_group AS BIGINT) focal_group
FROM deal_assignment
WHERE target_group IS NOT NULL
UNION
SELECT DISTINCT CAST(fg.id_group AS BIGINT) focal_group
FROM deal_assignment da
JOIN deal_target_company_expanded dtc USING(deal_id)
JOIN firm_group fg
  ON CAST(fg.compcod AS BIGINT)=dtc.target_compcod
 AND fg.year=CAST(da.target_year AS INTEGER)-1
WHERE fg.id_group IS NOT NULL
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_acquirer_events AS
SELECT DISTINCT CAST(acquirer_group AS BIGINT) focal_group,
       CAST(target_year AS INTEGER) event_year
FROM deal_assignment
WHERE acquirer_group IS NOT NULL
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_control_preclean AS
SELECT l.cohort,l.codinv,l.landmark_affiliation_year,
       l.resolved_group focal_group
FROM pp2_control_latest l
WHERE l.affiliation_rank=1
  AND l.candidate_group_count=1
  AND l.resolved_group IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM pp2_target_groups tg
    WHERE tg.focal_group=l.resolved_group)
  AND NOT EXISTS (
    SELECT 1 FROM pp2_acquirer_events ae
    WHERE ae.focal_group=l.resolved_group
      AND ae.event_year BETWEEN l.cohort-5 AND l.cohort+5)
  AND NOT EXISTS (
    SELECT 1 FROM pp2_all_target_exposures te
    WHERE te.codinv=l.codinv
      AND te.exposure_year<=l.cohort+5)
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_control_sizes AS
SELECT cohort,focal_group,COUNT(DISTINCT codinv)::INTEGER cohort_size
FROM pp2_control_preclean
GROUP BY cohort,focal_group
"))
invisible(DBI::dbExecute(con, sprintf("
CREATE TEMP TABLE pp2_control_units AS
SELECT c.cohort,'control' arm,c.codinv,NULL::BIGINT deal_id,
       -c.focal_group cluster_id,c.focal_group,
       c.landmark_affiliation_year,s.cohort_size,
       'landmark:control:'||CAST(c.cohort AS VARCHAR)||':'||
       CAST(c.focal_group AS VARCHAR)||':'||CAST(c.codinv AS VARCHAR) unit_id
FROM pp2_control_preclean c
JOIN pp2_control_sizes s USING(cohort,focal_group)
WHERE s.cohort_size>=%d
", config$minimum_donor_cohort_inventors)))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_symmetric_units AS
SELECT * FROM pp2_treated_units
UNION ALL
SELECT * FROM pp2_control_units
"))

sample_flow <- DBI::dbGetQuery(con, sprintf("
SELECT 'treated_accepted_deals' stage,
       COUNT(DISTINCT deal_id)::DOUBLE count_value FROM pp2_accepted_deals
UNION ALL
SELECT 'treated_early_focal_patent_inventors',
       COUNT(DISTINCT CAST(deal_id AS VARCHAR)||':'||CAST(codinv AS VARCHAR))
FROM pp2_treated_focal_patent
UNION ALL
SELECT 'treated_unique_target_affiliation',
       COUNT(*) FROM pp2_treated_eligible
UNION ALL
SELECT 'treated_earliest_exposure_units',
       COUNT(*) FROM pp2_treated_units
UNION ALL
SELECT 'control_unique_early_affiliation_rows',
       COUNT(*) FROM pp2_control_latest
       WHERE affiliation_rank=1 AND candidate_group_count=1
UNION ALL
SELECT 'control_clean_inventor_cohort_rows',
       COUNT(*) FROM pp2_control_preclean
UNION ALL
SELECT 'control_rows_after_minimum_cohort_size',
       COUNT(*) FROM pp2_control_units
UNION ALL
SELECT 'control_firm_cohorts_before_size_rule',
       COUNT(*) FROM pp2_control_sizes
UNION ALL
SELECT 'control_firm_cohorts_after_size_rule',
       COUNT(*) FROM pp2_control_sizes WHERE cohort_size>=%d
", config$minimum_donor_cohort_inventors))

unit_counts <- DBI::dbGetQuery(con, "
SELECT cohort,arm,COUNT(*) inventor_rows,
       COUNT(DISTINCT codinv) distinct_inventors,
       COUNT(DISTINCT cluster_id) clusters,
       MIN(cohort_size) minimum_cohort_size,
       MEDIAN(cohort_size) median_cohort_size,
       MAX(cohort_size) maximum_cohort_size
FROM pp2_symmetric_units
GROUP BY cohort,arm ORDER BY cohort,arm
")
donor_sizes <- DBI::dbGetQuery(con, sprintf("
SELECT cohort,focal_group,cohort_size,
       cohort_size>=%d retained_minimum_size
FROM pp2_control_sizes ORDER BY cohort,focal_group
", config$minimum_donor_cohort_inventors))

bad_keys <- DBI::dbGetQuery(con, "
SELECT COUNT(*) n FROM pp2_symmetric_units
WHERE cohort IS NULL OR arm IS NULL OR codinv IS NULL OR
      cluster_id IS NULL OR focal_group IS NULL OR
      landmark_affiliation_year IS NULL OR unit_id IS NULL
")$n[[1]]
duplicate_ids <- DBI::dbGetQuery(con, "
SELECT COUNT(*)-COUNT(DISTINCT unit_id) n FROM pp2_symmetric_units
")$n[[1]]
treated_repeat <- DBI::dbGetQuery(con, "
SELECT COUNT(*)-COUNT(DISTINCT codinv) n
FROM pp2_treated_units
")$n[[1]]
control_small <- DBI::dbGetQuery(con, sprintf("
SELECT COUNT(*) n FROM pp2_control_units
WHERE cohort_size<%d
", config$minimum_donor_cohort_inventors))$n[[1]]
control_target_exposure <- DBI::dbGetQuery(con, "
SELECT COUNT(*) n
FROM pp2_control_units c
JOIN pp2_all_target_exposures te USING(codinv)
WHERE te.exposure_year<=c.cohort+5
")$n[[1]]
control_u2_violation <- DBI::dbGetQuery(con, "
SELECT COUNT(*) n
FROM pp2_control_units c
WHERE EXISTS (
  SELECT 1 FROM pp2_target_groups tg
  WHERE tg.focal_group=c.focal_group)
OR EXISTS (
  SELECT 1 FROM pp2_acquirer_events ae
  WHERE ae.focal_group=c.focal_group
    AND ae.event_year BETWEEN c.cohort-5 AND c.cohort+5)
")$n[[1]]

certification <- data.frame(
  check = c(
    "freeze_hash_matches", "unit_keys_complete", "unit_ids_unique",
    "treated_inventors_first_exposure_only",
    "control_minimum_cohort_size",
    "control_target_exposure_excluded",
    "control_u2_clean",
    "cohort_range_is_1995_2010",
    "both_arms_nonempty"),
  pass = c(
    tolower(freeze_sha256)==config$expected_freeze_sha256,
    bad_keys==0, duplicate_ids==0, treated_repeat==0,
    control_small==0, control_target_exposure==0,
    control_u2_violation==0,
    all(as.integer(range(DBI::dbGetQuery(
      con, "SELECT cohort FROM pp2_symmetric_units")$cohort)) ==
      c(min(config$cohorts),max(config$cohorts))),
    DBI::dbGetQuery(
      con, "SELECT COUNT(DISTINCT arm) n FROM pp2_symmetric_units")$n[[1]]==2),
  detail = c(
    freeze_sha256, bad_keys, duplicate_ids, treated_repeat,
    control_small, control_target_exposure, control_u2_violation,
    paste(range(config$cohorts),collapse=":"), "treated;control"),
  stringsAsFactors = FALSE)

lmv2_ppscm_atomic_csv(
  sample_flow, file.path(config$units_dir, "sample_flow.csv"))
lmv2_ppscm_atomic_csv(
  unit_counts, file.path(config$units_dir, "symmetric_unit_counts.csv"))
lmv2_ppscm_atomic_csv(
  donor_sizes, file.path(config$units_dir, "donor_cohort_sizes.csv"))
lmv2_ppscm_atomic_csv(
  certification, file.path(config$units_dir, "unit_certification.csv"))
if (!all(certification$pass)) {
  stop("Symmetric-unit certification failed: ",
       paste(certification$check[!certification$pass], collapse = ", "))
}

lmv2_ppscm_atomic_copy(con, "
SELECT cohort,arm,codinv,deal_id,cluster_id,focal_group,
       landmark_affiliation_year,cohort_size,unit_id
FROM pp2_symmetric_units
ORDER BY cohort,arm,cluster_id,codinv
", config$units_path)
units_sha256 <- lmv2_ppscm_sha256(config$units_path)
manifest <- data.frame(
  version = config$version,
  source_sha256 = source_sha256,
  config_sha256 = config_sha256,
  freeze_sha256 = freeze_sha256,
  units_sha256 = units_sha256,
  minimum_event_time_used = -7L,
  maximum_event_time_used = -6L,
  treated_inventors = DBI::dbGetQuery(
    con, "SELECT COUNT(*) n FROM pp2_treated_units")$n[[1]],
  treated_deals = DBI::dbGetQuery(
    con, "SELECT COUNT(DISTINCT deal_id) n FROM pp2_treated_units")$n[[1]],
  control_inventor_cohort_rows = DBI::dbGetQuery(
    con, "SELECT COUNT(*) n FROM pp2_control_units")$n[[1]],
  control_firm_cohorts = DBI::dbGetQuery(
    con, "SELECT COUNT(DISTINCT CAST(cohort AS VARCHAR)||':'||
         CAST(focal_group AS VARCHAR)) n FROM pp2_control_units")$n[[1]],
  certification_pass = all(certification$pass),
  stringsAsFactors = FALSE)
lmv2_ppscm_atomic_csv(manifest, config$units_manifest_path)
message(
  "PPSCM v2 Stage B PASS | treated=", manifest$treated_inventors,
  " | deals=", manifest$treated_deals,
  " | control firm-cohorts=", manifest$control_firm_cohorts)

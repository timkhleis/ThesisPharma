# ============================================================================
# 31b_build_lmv2_inventor_moderators.R -- pre-treatment moderator builder
# ============================================================================
# Builds one row per certified P5c roster row.  This stage does not read the
# event panel or any treatment/post-treatment outcome.

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
source(file.path(BASE, "R", "31a_lmv2_inventor_heterogeneity_config.R"))

cfg <- LMV2_INVENTOR_HET
out_dir <- cfg$output_dir
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
temp_dir <- file.path(out_dir, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

db_path <- normalizePath(cfg$inputs$database, winslash = "/", mustWork = TRUE)
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
  "p6.lmv2_p5a_roster", "lmv2_p3_inventor_units",
  "patent_inventor_enriched"
)) {
  if (!DBI::dbExistsTable(con, DBI::Id(
    schema = if (grepl(".", tbl, fixed = TRUE)) strsplit(
      tbl, ".", fixed = TRUE
    )[[1]][1] else "main",
    table = tail(strsplit(tbl, ".", fixed = TRUE)[[1]], 1)
  ))) stop("Required table is missing: ", tbl)
}

# The control-unit table is cohort x inventor x focal group and intentionally
# has no deal_id.  Treated units retain deal_id.  Separate joins avoid a broad
# OR condition over the four-million-row P3 table.
# P3 stores focal tenure as an inclusive count through the cohort year. Shift
# it back by one so both tenure and career age are measured at t=-1.
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE het_mod_base AS
SELECT
  r.deal_id, r.cohort, r.arm, r.codinv, r.roster_row_id, r.weight,
  r.focal_group_1,
  CAST(u.patent_count_5y AS BIGINT) AS patent_count_5y,
  u.log_patent_count_5y, u.patent_trajectory, u.career_age,
  u.focal_group_tenure-1 AS focal_group_tenure,
  u.focal_group_exclusivity
FROM p6.lmv2_p5a_roster r
JOIN lmv2_p3_inventor_units u
  ON r.arm='treated' AND u.role='treated'
 AND u.cohort=r.cohort AND u.deal_id=r.deal_id
 AND u.codinv=r.codinv AND u.focal_group=r.focal_group_1
UNION ALL
SELECT
  r.deal_id, r.cohort, r.arm, r.codinv, r.roster_row_id, r.weight,
  r.focal_group_1,
  CAST(u.patent_count_5y AS BIGINT) AS patent_count_5y,
  u.log_patent_count_5y, u.patent_trajectory, u.career_age,
  u.focal_group_tenure-1 AS focal_group_tenure,
  u.focal_group_exclusivity
FROM p6.lmv2_p5a_roster r
JOIN lmv2_p3_inventor_units u
  ON r.arm='control' AND u.role='control'
 AND u.cohort=r.cohort AND u.codinv=r.codinv
 AND u.focal_group=r.focal_group_1
")

DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE het_unit_patents AS
SELECT DISTINCT
  b.roster_row_id, b.cohort, b.deal_id, b.arm, b.codinv,
  CAST(p.appln_id AS BIGINT) AS appln_id,
  CAST(p.year AS INTEGER) AS patent_year,
  CAST(p.inventor_count AS BIGINT) AS inventor_count
FROM het_mod_base b
JOIN patent_inventor_enriched p
  ON CAST(p.codinv AS BIGINT)=b.codinv
 AND p.year BETWEEN b.cohort-5 AND b.cohort-1
")

DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE het_coinventor_pairs AS
SELECT
  u.roster_row_id, u.appln_id,
  CAST(p.codinv AS BIGINT) AS co_codinv
FROM het_unit_patents u
JOIN patent_inventor_enriched p
  ON CAST(p.appln_id AS BIGINT)=u.appln_id
 AND CAST(p.codinv AS BIGINT)<>u.codinv
")

DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE het_stable_ties AS
SELECT roster_row_id, co_codinv,
       COUNT(DISTINCT appln_id) AS joint_patents
FROM het_coinventor_pairs
GROUP BY roster_row_id, co_codinv
HAVING COUNT(DISTINCT appln_id)>=%d
", cfg$construction$stable_tie_min_joint_patents))

DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE het_team_metrics AS
WITH patent_flags AS (
  SELECT
    u.roster_row_id, u.appln_id, u.patent_year, u.inventor_count,
    COUNT(DISTINCT p.co_codinv)>0 AS has_coinventor,
    COUNT(DISTINCT s.co_codinv)>0 AS has_stable_tie
  FROM het_unit_patents u
  LEFT JOIN het_coinventor_pairs p
    ON p.roster_row_id=u.roster_row_id AND p.appln_id=u.appln_id
  LEFT JOIN het_stable_ties s
    ON s.roster_row_id=p.roster_row_id AND s.co_codinv=p.co_codinv
  GROUP BY u.roster_row_id,u.appln_id,u.patent_year,u.inventor_count
), patent_summary AS (
  SELECT
    roster_row_id,
    COUNT(*) AS predeal_patents_reconstructed,
    MAX(patent_year) AS last_team_input_year,
    AVG(inventor_count) AS mean_patent_team_size,
    AVG(CAST(has_coinventor AS DOUBLE)) AS coauthored_patent_share,
    AVG(CAST(has_stable_tie AS DOUBLE)) AS stable_team_patent_share
  FROM patent_flags
  GROUP BY roster_row_id
), tie_summary AS (
  SELECT
    roster_row_id,
    COUNT(*) AS stable_coinventor_count,
    MAX(joint_patents) AS max_joint_patents_with_one_coinventor
  FROM het_stable_ties
  GROUP BY roster_row_id
)
SELECT
  p.*,
  COALESCE(t.stable_coinventor_count,0) AS stable_coinventor_count,
  COALESCE(t.max_joint_patents_with_one_coinventor,0)
    AS max_joint_patents_with_one_coinventor
FROM patent_summary p
LEFT JOIN tie_summary t USING (roster_row_id)
")

DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE het_moderators AS
SELECT
  b.*,
  t.predeal_patents_reconstructed,
  t.last_team_input_year,
  t.mean_patent_team_size,
  t.coauthored_patent_share,
  t.stable_team_patent_share,
  t.stable_coinventor_count,
  t.max_joint_patents_with_one_coinventor,
  CASE WHEN b.career_age<=1 THEN '0-1 years'
       WHEN b.career_age<=3 THEN '2-3 years'
       ELSE '4+ years' END AS career_age_group,
  CASE WHEN b.patent_count_5y<=1 THEN '1 patent'
       WHEN b.patent_count_5y=2 THEN '2 patents'
       ELSE '3+ patents' END AS predeal_productivity_group,
  CASE WHEN b.focal_group_exclusivity>=1-1e-12 THEN 'exclusive'
       ELSE 'multi-firm' END AS focal_exclusivity_group,
  CASE WHEN t.stable_team_patent_share<=1e-12 THEN 'no stable team'
       WHEN t.stable_team_patent_share>=1-1e-12
         THEN 'all patents stable team'
       ELSE 'partial stable team' END AS team_embeddedness_group,
  CASE WHEN b.focal_group_tenure<=1 THEN '0-1 years'
       WHEN b.focal_group_tenure<=3 THEN '2-3 years'
       ELSE '4+ years' END AS focal_tenure_group
FROM het_mod_base b
JOIN het_team_metrics t USING (roster_row_id)
")

moderator_path <- normalizePath(
  file.path(out_dir, "inventor_moderators.parquet"),
  winslash = "/", mustWork = FALSE
)
DBI::dbExecute(con, sprintf(
  "COPY (SELECT * FROM het_moderators ORDER BY cohort,deal_id,arm,codinv)
   TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
  DBI::dbQuoteString(con, moderator_path)
))

group_counts <- DBI::dbGetQuery(con, "
WITH long AS (
  SELECT cohort,deal_id,arm,codinv,weight,
         'career_age' moderator,career_age_group group_name
  FROM het_moderators
  UNION ALL
  SELECT cohort,deal_id,arm,codinv,weight,
         'predeal_productivity',predeal_productivity_group
  FROM het_moderators
  UNION ALL
  SELECT cohort,deal_id,arm,codinv,weight,
         'focal_exclusivity',focal_exclusivity_group
  FROM het_moderators
  UNION ALL
  SELECT cohort,deal_id,arm,codinv,weight,
         'team_embeddedness',team_embeddedness_group
  FROM het_moderators
  UNION ALL
  SELECT cohort,deal_id,arm,codinv,weight,
         'focal_tenure',focal_tenure_group
  FROM het_moderators
)
SELECT moderator,group_name,arm,
       COUNT(*) AS roster_rows,
       COUNT(DISTINCT codinv) AS distinct_inventors,
       COUNT(DISTINCT deal_id) AS nominal_deals,
       SUM(weight) AS weight_mass
FROM long
GROUP BY moderator,group_name,arm
ORDER BY moderator,group_name,arm
")
utils::write.csv(
  group_counts, file.path(out_dir, "moderator_group_counts.csv"),
  row.names = FALSE
)

audit <- DBI::dbGetQuery(con, "
SELECT
  (SELECT COUNT(*) FROM p6.lmv2_p5a_roster) AS roster_rows,
  (SELECT COUNT(*) FROM het_moderators) AS moderator_rows,
  (SELECT COUNT(DISTINCT roster_row_id) FROM het_moderators)
    AS unique_moderator_rows,
  (SELECT COUNT(*) FROM het_moderators
   WHERE patent_count_5y<>predeal_patents_reconstructed)
    AS reconstructed_patent_mismatches,
  (SELECT COUNT(*) FROM het_moderators
   WHERE last_team_input_year>cohort-1) AS future_year_violations,
  (SELECT COUNT(*) FROM het_moderators
   WHERE stable_team_patent_share<0 OR stable_team_patent_share>1)
    AS team_share_violations,
  (SELECT COUNT(*) FROM het_moderators
   WHERE focal_group_tenure<0 OR focal_group_tenure>career_age)
    AS tenure_clock_violations,
  (SELECT COUNT(*) FROM het_moderators
   WHERE career_age_group IS NULL
      OR predeal_productivity_group IS NULL
      OR focal_exclusivity_group IS NULL
      OR team_embeddedness_group IS NULL
      OR focal_tenure_group IS NULL) AS missing_groups
")
utils::write.csv(
  audit, file.path(out_dir, "moderator_build_audit.csv"),
  row.names = FALSE
)

checks <- data.frame(
  check = c(
    "one_moderator_row_per_roster_row",
    "reconstructed_predeal_patent_counts_match_p3",
    "team_inputs_end_before_treatment",
    "team_shares_in_unit_interval",
    "focal_tenure_uses_t_minus_1_clock",
    "all_predeclared_groups_assigned",
    "both_arms_present_in_every_group"
  ),
  pass = c(
    audit$roster_rows == audit$moderator_rows &&
      audit$moderator_rows == audit$unique_moderator_rows,
    audit$reconstructed_patent_mismatches == 0,
    audit$future_year_violations == 0,
    audit$team_share_violations == 0,
    audit$tenure_clock_violations == 0,
    audit$missing_groups == 0,
    all(stats::aggregate(
      arm ~ moderator + group_name,
      data = group_counts,
      FUN = function(x) length(unique(x))
    )$arm == 2L)
  ),
  stringsAsFactors = FALSE
)
lmv2_het_assert_checks(checks)
utils::write.csv(
  checks, file.path(out_dir, "moderator_build_certification.csv"),
  row.names = FALSE
)

freeze_path <- file.path(
  BASE, "notes", "local_match_v2_inventor_heterogeneity_freeze.md"
)
manifest <- data.frame(
  heterogeneity_design_hash = lmv2_inventor_het_hash(),
  freeze_sha256 = digest::digest(file = freeze_path, algo = "sha256"),
  source_sha256 = digest::digest(
    file = file.path(BASE, "R", "31b_build_lmv2_inventor_moderators.R"),
    algo = "sha256"
  ),
  moderator_parquet_sha256 = digest::digest(
    file = moderator_path, algo = "sha256"
  ),
  moderator_rows = audit$moderator_rows,
  stable_tie_min_joint_patents =
    cfg$construction$stable_tie_min_joint_patents,
  maximum_team_input_event_time =
    DBI::dbGetQuery(con, "
      SELECT MAX(last_team_input_year-cohort) x FROM het_moderators
    ")$x,
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
  "Certified pre-treatment moderator table: ", audit$moderator_rows,
  " rows in ", round(manifest$runtime_minutes, 2), " minutes."
)

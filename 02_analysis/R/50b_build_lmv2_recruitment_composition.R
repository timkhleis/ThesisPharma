# Build symmetric and as-is recruitment histories at the production roster grain.

.libPaths(c(normalizePath(".r_libs", mustWork = TRUE), .libPaths()))
suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(digest)
})
source(file.path("02_analysis", "R", "50a_lmv2_recruitment_composition_config.R"))

sql_quote <- function(x) paste0("'", gsub("'", "''", normalizePath(x, winslash = "/", mustWork = FALSE)), "'")
assert_hash <- function(path, expected) {
  observed <- toupper(digest::digest(file = path, algo = "sha256", serialize = FALSE))
  if (!identical(observed, expected)) stop("Input hash mismatch: ", path)
  observed
}

dir.create(LMV2_RECRUIT_PATHS$output, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(LMV2_RECRUIT_PATHS$output, "data"), showWarnings = FALSE)
dir.create(file.path(LMV2_RECRUIT_PATHS$output, "tables"), showWarnings = FALSE)
dir.create(file.path(LMV2_RECRUIT_PATHS$output, "manifests"), showWarnings = FALSE)

verified <- c(
  p5a_roster = assert_hash(LMV2_RECRUIT_PATHS$p5a_roster, LMV2_RECRUIT_HASHES[["p5a_roster"]]),
  loyo_m3_roster = assert_hash(LMV2_RECRUIT_PATHS$loyo_m3_roster, LMV2_RECRUIT_HASHES[["loyo_m3_roster"]]),
  count_active_roster = assert_hash(LMV2_RECRUIT_PATHS$count_active_roster, LMV2_RECRUIT_HASHES[["count_active_roster"]]),
  database = assert_hash(LMV2_RECRUIT_PATHS$database, LMV2_RECRUIT_HASHES[["database"]])
)

con <- dbConnect(duckdb::duckdb(), LMV2_RECRUIT_PATHS$database, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "SET threads=4")
dbExecute(con, "SET memory_limit='9GB'")

p5a <- sql_quote(LMV2_RECRUIT_PATHS$p5a_roster)
loyo <- sql_quote(LMV2_RECRUIT_PATHS$loyo_m3_roster)
count_active <- sql_quote(LMV2_RECRUIT_PATHS$count_active_roster)

dbExecute(con, sprintf("
  CREATE TEMP TABLE recruit_roster AS
  SELECT 'p5a' AS specification,
         concat(cohort, ':', deal_id, ':', arm, ':', codinv) AS roster_row_id,
         cohort, deal_id, arm, codinv, weight,
         focal_group_1, focal_group_2, use_target_company_path
  FROM read_parquet(%s)
  UNION ALL
  SELECT 'loyo_m3', roster_row_id, cohort, deal_id, arm, codinv, weight,
         focal_group_1, focal_group_2, use_target_company_path
  FROM read_parquet(%s)
  UNION ALL
  SELECT 'count_active', roster_row_id, cohort, deal_id, arm, codinv, weight,
         focal_group_1, focal_group_2, use_target_company_path
  FROM read_parquet(%s)
", p5a, loyo, count_active))

grain <- dbGetQuery(con, "
  SELECT specification, count(*) AS n_rows,
         count(DISTINCT (cohort, deal_id, arm, codinv)) AS n_keys,
         count(*) - count(DISTINCT (cohort, deal_id, arm, codinv)) AS duplicates
  FROM recruit_roster GROUP BY specification ORDER BY specification")
if (any(grain$duplicates != 0)) stop("Recruitment roster key is not unique")

dbExecute(con, "
  CREATE TEMP TABLE recruit_keys AS
  SELECT DISTINCT cohort, deal_id, arm, codinv, focal_group_1,
                  use_target_company_path
  FROM recruit_roster")

dbExecute(con, "
  CREATE TEMP TABLE symmetric_history AS
  WITH h AS (
    SELECT k.cohort, k.deal_id, k.arm, k.codinv, k.focal_group_1,
           min(a.year) AS first_focal_year,
           max(a.year) AS last_focal_year,
           count(DISTINCT a.year) AS active_focal_years
    FROM recruit_keys k
    LEFT JOIN inventor_affiliation_own a
      ON CAST(a.codinv AS BIGINT)=k.codinv
     AND CAST(a.resolved_group AS BIGINT)=k.focal_group_1
     AND a.year <= k.cohort - 1
    GROUP BY ALL
  ), first_patent AS (
    SELECT CAST(codinv AS BIGINT) AS codinv, min(year) AS first_patent_year
    FROM inventor_year WHERE patent_count > 0 GROUP BY 1
  )
  SELECT h.*, fp.first_patent_year,
         first_focal_year - cohort AS first_event_time,
         last_focal_year - cohort AS last_event_time,
         CASE WHEN first_focal_year IS NULL THEN NULL
              ELSE last_focal_year - first_focal_year + 1 END AS calendar_span,
         cohort - 1988 AS available_lookback_years
  FROM h LEFT JOIN first_patent fp USING (codinv)")

dbExecute(con, "
  CREATE TEMP TABLE treated_company_history AS
  SELECT k.cohort, k.deal_id, k.arm, k.codinv,
         min(pcl.year) AS first_company_year,
         max(pcl.year) AS last_company_year,
         count(DISTINCT pcl.year) AS active_company_years
  FROM recruit_keys k
  JOIN deal_target_company_strict dt ON dt.deal_id=k.deal_id
  JOIN patent_inventor pi ON CAST(pi.codinv AS BIGINT)=k.codinv
  JOIN patent_company_link pcl
    ON pcl.appln_id=pi.appln_id AND pcl.compcod=dt.target_compcod
  WHERE k.arm='treated' AND pcl.year <= k.cohort - 1
  GROUP BY ALL")

dbExecute(con, "
  CREATE TEMP TABLE recruitment_history AS
  SELECT r.specification, r.roster_row_id, r.cohort, r.deal_id, r.arm,
         r.codinv, r.weight, r.focal_group_1, r.focal_group_2,
         r.use_target_company_path, s.first_patent_year,
         s.first_focal_year AS symmetric_first_year,
         s.last_focal_year AS symmetric_last_year,
         s.active_focal_years AS symmetric_active_years,
         s.calendar_span AS symmetric_calendar_span,
         s.first_event_time AS symmetric_entry_event,
         s.last_event_time AS symmetric_end_event,
         s.available_lookback_years,
         CASE WHEN r.arm='treated' THEN tc.first_company_year ELSE s.first_focal_year END AS asis_first_year,
         CASE WHEN r.arm='treated' THEN tc.last_company_year ELSE s.last_focal_year END AS asis_last_year,
         CASE WHEN r.arm='treated' THEN tc.active_company_years ELSE s.active_focal_years END AS asis_active_years
  FROM recruit_roster r
  JOIN symmetric_history s USING (cohort, deal_id, arm, codinv, focal_group_1)
  LEFT JOIN treated_company_history tc USING (cohort, deal_id, arm, codinv)")

bin_case <- function(var) sprintf("CASE WHEN %1$s IS NULL THEN 'unresolved'
  WHEN %1$s <= -6 THEN 'pre_g5' WHEN %1$s=-5 THEN 'm5'
  WHEN %1$s=-4 THEN 'm4' WHEN %1$s=-3 THEN 'm3'
  WHEN %1$s=-2 THEN 'm2' WHEN %1$s=-1 THEN 'm1'
  ELSE 'unresolved' END", var)

dbExecute(con, sprintf("
  CREATE TEMP TABLE recruitment_binned AS
  SELECT *, %s AS symmetric_entry_bin, %s AS symmetric_end_bin,
    CASE WHEN symmetric_calendar_span IS NULL THEN 'unresolved'
         WHEN symmetric_calendar_span=1 THEN '1'
         WHEN symmetric_calendar_span=2 THEN '2'
         WHEN symmetric_calendar_span BETWEEN 3 AND 5 THEN '3_5'
         ELSE '6_plus' END AS symmetric_length_bin,
    asis_first_year-cohort AS asis_entry_event,
    asis_last_year-cohort AS asis_end_event,
    %s AS asis_entry_bin, %s AS asis_end_bin
  FROM recruitment_history",
  bin_case("symmetric_entry_event"), bin_case("symmetric_end_event"),
  bin_case("asis_first_year-cohort"), bin_case("asis_last_year-cohort")))

history_path <- file.path(LMV2_RECRUIT_PATHS$output, "data", "recruitment_history.parquet")
dbExecute(con, sprintf("COPY recruitment_binned TO %s (FORMAT PARQUET, COMPRESSION ZSTD)", sql_quote(history_path)))

write.csv(grain, file.path(LMV2_RECRUIT_PATHS$output, "tables", "roster_grain.csv"), row.names = FALSE)
coverage <- dbGetQuery(con, "
  SELECT specification, arm, count(*) AS n,
    avg(CAST(symmetric_first_year IS NOT NULL AS INTEGER))::DOUBLE AS symmetric_resolved_share,
    avg(CAST(asis_first_year IS NOT NULL AS INTEGER))::DOUBLE AS asis_resolved_share,
    min(available_lookback_years) AS min_lookback,
    max(available_lookback_years) AS max_lookback
  FROM recruitment_binned GROUP BY specification, arm ORDER BY specification, arm")
write.csv(coverage, file.path(LMV2_RECRUIT_PATHS$output, "tables", "history_coverage.csv"), row.names = FALSE)

shares <- dbGetQuery(con, "
  WITH arm_mass AS (
    SELECT specification, cohort, arm, sum(weight) AS mass
    FROM recruitment_binned GROUP BY ALL
  ), cell AS (
    SELECT specification, cohort, arm, symmetric_entry_bin, sum(weight) AS cell_mass
    FROM recruitment_binned GROUP BY ALL
  )
  SELECT c.*, c.cell_mass/a.mass AS share
  FROM cell c JOIN arm_mass a USING (specification, cohort, arm)
  ORDER BY specification, cohort, arm, symmetric_entry_bin")
write.csv(shares, file.path(LMV2_RECRUIT_PATHS$output, "tables", "entry_shares_by_cohort.csv"), row.names = FALSE)

manifest <- data.frame(version = LMV2_RECRUIT_VERSION, input = names(verified),
                       sha256 = unname(verified), built_at = as.character(Sys.time()))
write.csv(manifest, file.path(LMV2_RECRUIT_PATHS$output, "manifests", "build_manifest.csv"), row.names = FALSE)
cat("Built recruitment histories:", normalizePath(history_path), "\n")

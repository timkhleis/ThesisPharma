# Read-only preflight audit for the P5.1 main-ATT support rescue.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, required = TRUE, default = NA_character_) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) {
    if (required) stop("Missing --", name, "=...")
    return(default)
  }
  sub(paste0("^--", name, "="), "", hit[[1]])
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(BASE, "R", "16c_lmv2_matching_utils.R"))
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))
source(file.path(BASE, "R", "17l_lmv2_p4_hybrid_core.R"))
source(file.path(BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"))
source(file.path(BASE, "R", "19a_lmv2_p5_rescue_config.R"))

db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
original_p5_dir <- normalizePath(
  read_arg("original-p5-dir"), winslash = "/", mustWork = TRUE)
output_dir <- read_arg("output-dir")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

decomposition_sql <- "
WITH activity AS (
  SELECT CAST(pcl.id_group AS BIGINT) id_group,
         COUNT(DISTINCT pcl.appln_id) patent_stock_5y,
         COUNT(DISTINCT CAST(pi.codinv AS BIGINT)) inventor_count_5y
  FROM patent_company_link pcl
  JOIN patent_inventor pi ON pi.appln_id=pcl.appln_id
  WHERE pcl.year BETWEEN 1995 AND 1999
    AND pcl.id_group IS NOT NULL AND pi.codinv IS NOT NULL
  GROUP BY 1
), target_events AS (
  SELECT DISTINCT CAST(target_group AS BIGINT) id_group,
         CAST(target_year AS INTEGER) event_year
  FROM deal_assignment WHERE target_group IS NOT NULL
  UNION
  SELECT DISTINCT CAST(fg.id_group AS BIGINT),
         CAST(da.target_year AS INTEGER)
  FROM deal_assignment da
  JOIN deal_target_company_expanded dtc ON dtc.deal_id=da.deal_id
  JOIN firm_group fg
    ON CAST(fg.compcod AS BIGINT)=dtc.target_compcod
   AND fg.year=CAST(da.target_year AS INTEGER)-1
  WHERE fg.id_group IS NOT NULL
), target_flags AS (
  SELECT id_group, TRUE ever_target,
         BOOL_OR(event_year<=2005) target_by_g5
  FROM target_events GROUP BY id_group
), acquirer_flags AS (
  SELECT CAST(acquirer_group AS BIGINT) id_group, TRUE acquirer_near
  FROM deal_assignment
  WHERE acquirer_group IS NOT NULL
    AND CAST(target_year AS INTEGER) BETWEEN 1995 AND 2005
  GROUP BY 1
), classified AS (
  SELECT a.*,
         COALESCE(t.ever_target,FALSE) ever_target,
         COALESCE(t.target_by_g5,FALSE) target_by_g5,
         COALESCE(q.acquirer_near,FALSE) acquirer_near
  FROM activity a
  LEFT JOIN target_flags t USING(id_group)
  LEFT JOIN acquirer_flags q USING(id_group)
), labeled AS (
  SELECT *,
    CASE
      WHEN NOT ever_target AND NOT acquirer_near THEN 'u1'
      WHEN ever_target AND NOT target_by_g5 AND NOT acquirer_near
        THEN 'u2_increment'
      WHEN acquirer_near THEN 'acquirer_excluded'
      ELSE 'target_by_g5_excluded'
    END pool_class
  FROM classified
)
SELECT pool_class, COUNT(*) n_firms,
       SUM(patent_stock_5y) patents,
       SUM(inventor_count_5y) inventor_firm_links,
       MEDIAN(patent_stock_5y) median_patents,
       QUANTILE_CONT(patent_stock_5y,0.9) p90_patents,
       MAX(patent_stock_5y) max_patents,
       MEDIAN(inventor_count_5y) median_inventors,
       QUANTILE_CONT(inventor_count_5y,0.9) p90_inventors,
       MAX(inventor_count_5y) max_inventors
FROM labeled GROUP BY 1 ORDER BY 1"
decomposition <- DBI::dbGetQuery(con, decomposition_sql)
utils::write.csv(
  decomposition,
  file.path(output_dir, "cohort_2000_donor_exclusion_decomposition.csv"),
  row.names = FALSE
)

cover_glob <- gsub(
  "\\\\", "/",
  file.path(
    original_p5_dir, "main", "cohort_*", "disk_tech_cache",
    "cohort_*", "profile_edge_covers", "*.parquet")
)
support_sql <- sprintf("
WITH full_treated AS (
  SELECT CAST(cohort AS INTEGER) cohort,
         CAST(deal_id AS INTEGER) deal_id,
         CAST(codinv AS BIGINT) codinv,
         log_patent_count_5y, career_age,
         focal_group_exclusivity, focal_group_tenure
  FROM lmv2_p3_treated_inventor_units
  WHERE cohort BETWEEN 1994 AND 2010
), supported AS (
  SELECT DISTINCT CAST(cohort AS INTEGER) cohort,
         CAST(deal_id AS INTEGER) deal_id,
         CAST(treated_codinv AS BIGINT) codinv
  FROM read_parquet('%s', union_by_name=true)
)
SELECT f.*, s.codinv IS NOT NULL AS supported
FROM full_treated f
LEFT JOIN supported s USING(cohort,deal_id,codinv)
ORDER BY cohort,deal_id,codinv", cover_glob)
treated_support <- DBI::dbGetQuery(con, support_sql)
score <- lmv2_p5_rescue_score_gates(treated_support)

utils::write.csv(
  score$checks, file.path(output_dir, "baseline_gate_checks.csv"),
  row.names = FALSE)
utils::write.csv(
  score$by_cohort, file.path(output_dir, "baseline_coverage_by_cohort.csv"),
  row.names = FALSE)
utils::write.csv(
  score$by_quartile,
  file.path(output_dir, "baseline_coverage_by_productivity_quartile.csv"),
  row.names = FALSE)
utils::write.csv(
  score$selection,
  file.path(output_dir, "baseline_retained_vs_unsupported.csv"),
  row.names = FALSE)

manifest <- data.frame(
  version = LMV2_P5_RESCUE_VERSION,
  amendment_hash = LMV2_P5_RESCUE_AMENDMENT_SHA256,
  database = db_path,
  database_size = file.info(db_path)$size,
  original_p5_dir = original_p5_dir,
  baseline_pass = score$pass,
  timestamp = as.character(Sys.time()),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(output_dir, "preflight_manifest.csv"),
  row.names = FALSE)
message("P5.1 preflight audit complete: ", normalizePath(output_dir))

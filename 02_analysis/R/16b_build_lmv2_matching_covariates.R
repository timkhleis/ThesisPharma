# ============================================================================
# 16b_build_lmv2_matching_covariates.R -- P3 outcome-blind matching inputs
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(BASE, "R", "16c_lmv2_matching_utils.R"))

for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

dir.create(LMV2_P3_PATHS$audit, recursive = TRUE, showWarnings = FALSE)
dir.create(LMV2_P3_PATHS$parquet, recursive = TRUE, showWarnings = FALSE)

con <- DBI::dbConnect(duckdb::duckdb(), file.path(BASE, "output", "thesis_foundation.duckdb"))
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")
DBI::dbExecute(con, "PRAGMA threads=1")
DBI::dbExecute(con, "PRAGMA preserve_insertion_order=false")

required <- c(
  "lmv2_treated_primary", "lmv2_control_firm_eligibility",
  "lmv2_control_inventor_eligibility", "inventor_year", "patent_inventor",
  "patent_application", "patent_company_link", "inventor_ipc_year", "group_ipc_year", "ipc",
  "deal_target_company_strict", "deal_target_company_expanded"
)
missing <- required[!vapply(required, DBI::dbExistsTable, logical(1), conn = con)]
if (length(missing)) stop("Missing P3 input tables: ", paste(missing, collapse = ", "))

message("P3: constructing canonical IPC resolution map")
ipc_codes <- DBI::dbGetQuery(con, "SELECT DISTINCT ipc_code FROM ipc WHERE ipc_code IS NOT NULL")
ipc_map <- do.call(rbind, lapply(LMV2_P3$technology$resolutions, function(res) {
  data.frame(
    ipc_code = ipc_codes$ipc_code,
    resolution = res,
    ipc_feature = lmv2_ipc_feature(ipc_codes$ipc_code, res),
    stringsAsFactors = FALSE
  )
}))
ipc_map <- unique(ipc_map[!is.na(ipc_map$ipc_feature), ])
DBI::dbWriteTable(con, "lmv2_p3_ipc_code_map", ipc_map, overwrite = TRUE)

message("P3: constructing canonical group-year patent counts")
DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_p3_group_year_patents AS
SELECT CAST(id_group AS BIGINT) AS id_group, year,
       COUNT(DISTINCT appln_id) AS patent_count
FROM patent_company_link
WHERE id_group IS NOT NULL AND year IS NOT NULL
GROUP BY CAST(id_group AS BIGINT),year
")
message("P3: constructing typed P1 inventor-year matching view")
DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_p3_inventor_year_typed AS
SELECT CAST(codinv AS BIGINT) AS codinv,year,patent_count,
       career_first_year,career_last_year
FROM inventor_year
")

message("P3: constructing firm matching covariates")
firm_tables <- character()
for (g in LMV2_LOCK$timing$cohorts) {
  shard <- sprintf("lmv2_p3_firm_units_%d", g)
  firm_tables <- c(firm_tables, shard)
  message("  firm covariates cohort ", g)
  DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TABLE %s AS
WITH treated_roster AS (
  SELECT DISTINCT cohort, 'treated' AS role, deal_id,
         CAST(target_group AS BIGINT) AS id_group
  FROM lmv2_treated_primary WHERE cohort=%d
), treated_activity AS (
  SELECT t.cohort,t.role,t.deal_id,t.id_group,
         COUNT(DISTINCT pcl.appln_id) AS patent_stock_5y,
         COUNT(DISTINCT CAST(pi.codinv AS BIGINT)) AS inventor_count_5y
  FROM treated_roster t
  JOIN patent_company_link pcl ON CAST(pcl.id_group AS BIGINT)=t.id_group
   AND pcl.year BETWEEN t.cohort-5 AND t.cohort-1
  JOIN patent_inventor pi ON pi.appln_id=pcl.appln_id
  GROUP BY t.cohort,t.role,t.deal_id,t.id_group
), units AS (
  SELECT * FROM treated_activity
  UNION ALL
  SELECT cohort, 'control' AS role, NULL::BIGINT AS deal_id,
         CAST(control_group AS BIGINT) AS id_group,
         pre_patent_stock AS patent_stock_5y,
         pre_inventor_count AS inventor_count_5y
  FROM lmv2_control_firm_eligibility WHERE cohort=%d
), annual AS (
  SELECT u.cohort,u.role,u.deal_id,u.id_group,g.year,g.patent_count
  FROM units u
  JOIN lmv2_p3_group_year_patents g ON g.id_group=u.id_group
   AND g.year BETWEEN u.cohort-5 AND u.cohort-1
), collapsed AS (
  SELECT cohort, role, deal_id, id_group,
         SUM(CASE WHEN year BETWEEN cohort-5 AND cohort-3 THEN patent_count ELSE 0 END) AS patents_early,
         SUM(CASE WHEN year BETWEEN cohort-2 AND cohort-1 THEN patent_count ELSE 0 END) AS patents_recent
  FROM annual
  GROUP BY cohort, role, deal_id, id_group
)
SELECT u.cohort, u.role, u.deal_id, u.id_group,
       u.patent_stock_5y,
       u.inventor_count_5y,
       LN(1+u.patent_stock_5y) AS log_patent_stock_5y,
       LN(1+u.inventor_count_5y) AS log_inventor_count_5y,
       COALESCE(c.patents_early,0) AS patents_early,
       COALESCE(c.patents_recent,0) AS patents_recent,
       LN(1+COALESCE(c.patents_recent,0)/2.0)-LN(1+COALESCE(c.patents_early,0)/3.0)
         AS patent_trajectory
FROM units u
LEFT JOIN collapsed c
  ON c.cohort=u.cohort
 AND c.role=u.role
 AND c.deal_id IS NOT DISTINCT FROM u.deal_id
 AND c.id_group=u.id_group
", DBI::dbQuoteIdentifier(con, shard), g, g))
}
union_sql <- paste(sprintf("SELECT * FROM %s", vapply(
  firm_tables, function(x) as.character(DBI::dbQuoteIdentifier(con, x)), character(1)
)), collapse = " UNION ALL ")
DBI::dbExecute(con, paste("CREATE OR REPLACE TABLE lmv2_p3_firm_units AS", union_sql))
for (shard in firm_tables) DBI::dbRemoveTable(con, shard)

message("P3: constructing inventor matching covariates")
DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_p3_inventor_cohort_stats AS
WITH stacks AS (SELECT UNNEST(range(1993,2011))::INTEGER AS cohort)
SELECT s.cohort,iy.codinv,
       COUNT(*) AS active_pre_years,
       SUM(iy.patent_count) AS patent_count_5y,
       SUM(CASE WHEN iy.year BETWEEN s.cohort-5 AND s.cohort-3
                THEN iy.patent_count ELSE 0 END) AS patents_early,
       SUM(CASE WHEN iy.year BETWEEN s.cohort-2 AND s.cohort-1
                THEN iy.patent_count ELSE 0 END) AS patents_recent,
       MIN(iy.career_first_year) AS career_first_year,
       MAX(iy.year) AS last_pre_patent_year
FROM stacks s
JOIN lmv2_p3_inventor_year_typed iy
  ON iy.year BETWEEN s.cohort-5 AND s.cohort-1
GROUP BY s.cohort,iy.codinv
")
DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_p3_inventor_general_units AS
WITH units AS (
  SELECT cohort,'treated' AS role,deal_id,CAST(codinv AS BIGINT) codinv,
         CAST(target_group AS BIGINT) focal_group,
         NULL::BOOLEAN AS control_firm_exits_before_g_plus_5
  FROM lmv2_treated_primary
  UNION ALL
  SELECT CAST(cohort AS INTEGER),'control',NULL::BIGINT,CAST(codinv AS BIGINT),
         CAST(control_group AS BIGINT),control_firm_exits_before_g_plus_5
  FROM lmv2_control_inventor_eligibility
)
SELECT u.*,s.active_pre_years,s.patent_count_5y,s.patents_early,s.patents_recent,
       s.career_first_year,s.last_pre_patent_year,
       LN(1+s.patent_count_5y) AS log_patent_count_5y,
       LN(1+s.patents_recent/2.0)-LN(1+s.patents_early/3.0) AS patent_trajectory,
       (u.cohort-1-s.career_first_year) AS career_age,
       CASE
         WHEN s.last_pre_patent_year=u.cohort-1 THEN 0
         WHEN s.last_pre_patent_year=u.cohort-2 THEN 1
         WHEN s.last_pre_patent_year=u.cohort-3 THEN 2
         WHEN s.last_pre_patent_year BETWEEN u.cohort-5 AND u.cohort-4 THEN 3
         ELSE NULL
       END AS recency_bin
FROM units u
LEFT JOIN lmv2_p3_inventor_cohort_stats s USING(cohort,codinv)
")

message("P3: constructing treated focal-group tenure and exclusivity")
promoted_deals <- paste(LMV2_P3$p2_assignment$high_confidence_promoted_deals,
                        collapse = ",")
DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TABLE lmv2_p3_treated_inventor_units AS
WITH treated AS (
  SELECT * FROM lmv2_p3_inventor_general_units WHERE role='treated'
), target_companies AS (
  SELECT deal_id,target_compcod FROM deal_target_company_strict
  UNION
  SELECT deal_id,target_compcod FROM deal_target_company_expanded
  WHERE deal_id IN (%s)
), evidence_raw AS (
  SELECT DISTINCT t.cohort,t.deal_id,t.codinv,t.focal_group,
         CAST(pi.appln_id AS BIGINT) AS appln_id,pa.patent_year,
         EXISTS (
           SELECT 1 FROM patent_company_link pg
           WHERE pg.appln_id=pi.appln_id
             AND CAST(pg.id_group AS BIGINT)=t.focal_group
         ) AS has_group_link,
         EXISTS (
           SELECT 1 FROM patent_company_link pc
           JOIN target_companies tc ON tc.deal_id=t.deal_id
                                   AND tc.target_compcod=CAST(pc.compcod AS BIGINT)
           WHERE pc.appln_id=pi.appln_id
         ) AS has_target_company_link
  FROM treated t
  JOIN patent_inventor pi ON CAST(pi.codinv AS BIGINT)=t.codinv
  JOIN patent_application pa ON pa.appln_id=pi.appln_id AND pa.patent_year<=t.cohort-1
), focal_evidence AS (
  SELECT * FROM evidence_raw WHERE has_group_link OR has_target_company_link
), focal AS (
  SELECT cohort,deal_id,codinv,focal_group,
         MIN(patent_year) AS focal_first_year,
         COUNT(DISTINCT CASE WHEN patent_year BETWEEN cohort-5 AND cohort-1
                             THEN appln_id END) AS focal_patent_count_5y,
         BOOL_OR(has_group_link) AS has_group_focal_evidence,
         BOOL_OR(has_target_company_link) AS has_target_company_focal_evidence,
         COUNT(DISTINCT CASE WHEN patent_year BETWEEN cohort-5 AND cohort-1
                                  AND has_target_company_link AND NOT has_group_link
                             THEN appln_id END) AS company_only_focal_patent_count_5y
  FROM focal_evidence GROUP BY cohort,deal_id,codinv,focal_group
)
SELECT t.*,
       t.cohort-f.focal_first_year AS focal_group_tenure,
       f.focal_patent_count_5y::DOUBLE/NULLIF(t.patent_count_5y,0)
         AS focal_group_exclusivity,
       COALESCE(f.has_group_focal_evidence,FALSE) AS has_group_focal_evidence,
       COALESCE(f.has_target_company_focal_evidence,FALSE)
         AS has_target_company_focal_evidence,
       COALESCE(f.company_only_focal_patent_count_5y,0)
         AS company_only_focal_patent_count_5y
FROM treated t
LEFT JOIN focal f USING(cohort,deal_id,codinv,focal_group)
", promoted_deals))

message("P3: constructing normalized firm technology vectors at three resolutions")
DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_p3_firm_ipc_vectors AS
WITH roster AS (
  SELECT DISTINCT cohort, id_group FROM lmv2_p3_firm_units
), weighted AS (
  SELECT r.cohort, r.id_group, m.resolution, m.ipc_feature,
         SUM(g.patent_count)::DOUBLE AS weight
  FROM roster r
  JOIN group_ipc_year g ON CAST(g.id_group AS BIGINT)=r.id_group
   AND g.year BETWEEN r.cohort-5 AND r.cohort-1
  JOIN lmv2_p3_ipc_code_map m USING (ipc_code)
  GROUP BY r.cohort, r.id_group, m.resolution, m.ipc_feature
)
SELECT *, weight/SUM(weight) OVER (PARTITION BY cohort,id_group,resolution) AS frequency
FROM weighted
")

message("P3: constructing normalized treated-inventor technology vectors")
DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_p3_treated_inventor_ipc_vectors AS
WITH roster AS (
  SELECT cohort, deal_id, codinv FROM lmv2_p3_treated_inventor_units
), weighted AS (
  SELECT r.cohort, r.deal_id, r.codinv, m.resolution, m.ipc_feature,
         SUM(i.patent_count)::DOUBLE AS weight
  FROM roster r
  JOIN inventor_ipc_year i ON CAST(i.codinv AS BIGINT)=r.codinv
   AND i.year BETWEEN r.cohort-5 AND r.cohort-1
  JOIN lmv2_p3_ipc_code_map m USING (ipc_code)
  GROUP BY r.cohort,r.deal_id,r.codinv,m.resolution,m.ipc_feature
)
SELECT *, weight/SUM(weight) OVER (PARTITION BY cohort,deal_id,codinv,resolution) AS frequency
FROM weighted
")

message("P3: constructing all Stage-1 technology similarity matrices")
similarity_shards <- character()
for (g in LMV2_LOCK$timing$cohorts) {
  shard <- sprintf("lmv2_p3_stage1_similarity_%d", g)
  similarity_shards <- c(similarity_shards, shard)
  message("  Stage-1 similarities cohort ", g)
  DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TABLE %s AS
WITH pairs AS (
  SELECT t.cohort,t.deal_id,t.id_group AS target_group,c.id_group AS control_group,r.resolution
  FROM lmv2_p3_firm_units t
  JOIN lmv2_p3_firm_units c ON c.cohort=t.cohort AND c.role='control'
  CROSS JOIN (SELECT DISTINCT resolution FROM lmv2_p3_ipc_code_map) r
  WHERE t.role='treated' AND t.cohort=%d
), norms AS (
  SELECT cohort,id_group,resolution,SQRT(SUM(frequency*frequency)) AS norm
  FROM lmv2_p3_firm_ipc_vectors WHERE cohort=%d GROUP BY cohort,id_group,resolution
), dots AS (
  SELECT t.cohort,t.deal_id,t.id_group AS target_group,
         c.id_group AS control_group,tv.resolution,
         SUM(tv.frequency*cv.frequency) AS dot
  FROM lmv2_p3_firm_units t
  JOIN lmv2_p3_firm_ipc_vectors tv
    ON tv.cohort=t.cohort AND tv.id_group=t.id_group
  JOIN lmv2_p3_firm_ipc_vectors cv
    ON cv.cohort=tv.cohort AND cv.resolution=tv.resolution
   AND cv.ipc_feature=tv.ipc_feature
  JOIN lmv2_p3_firm_units c
    ON c.cohort=cv.cohort AND c.id_group=cv.id_group AND c.role='control'
  WHERE t.role='treated' AND t.cohort=%d
  GROUP BY t.cohort,t.deal_id,t.id_group,c.id_group,tv.resolution
)
SELECT p.*, CASE WHEN tn.norm>0 AND cn.norm>0
                 THEN LEAST(1.0,GREATEST(0.0,COALESCE(d.dot,0)/(tn.norm*cn.norm)))
                 ELSE NULL END AS cosine
FROM pairs p
LEFT JOIN dots d USING (cohort,deal_id,target_group,control_group,resolution)
LEFT JOIN norms tn ON tn.cohort=p.cohort AND tn.id_group=p.target_group AND tn.resolution=p.resolution
LEFT JOIN norms cn ON cn.cohort=p.cohort AND cn.id_group=p.control_group AND cn.resolution=p.resolution
", DBI::dbQuoteIdentifier(con, shard), g, g, g))
}
union_sql <- paste(sprintf("SELECT * FROM %s", vapply(
  similarity_shards, function(x) as.character(DBI::dbQuoteIdentifier(con, x)), character(1)
)), collapse = " UNION ALL ")
DBI::dbExecute(con, paste("CREATE OR REPLACE TABLE lmv2_p3_stage1_similarity AS", union_sql))
for (shard in similarity_shards) DBI::dbRemoveTable(con, shard)

message("P3: constructing within-cohort scalers and Stage-1 edges")
DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_p3_stage1_scalers AS
WITH scalar_long AS (
  SELECT cohort,'log_patent_stock_5y' AS component,STDDEV_SAMP(log_patent_stock_5y) AS component_sd
  FROM lmv2_p3_firm_units GROUP BY cohort
  UNION ALL
  SELECT cohort,'log_inventor_count_5y',STDDEV_SAMP(log_inventor_count_5y)
  FROM lmv2_p3_firm_units GROUP BY cohort
  UNION ALL
  SELECT cohort,'patent_trajectory',STDDEV_SAMP(patent_trajectory)
  FROM lmv2_p3_firm_units GROUP BY cohort
), tech AS (
  SELECT cohort,resolution,'tech_distance' AS component,
         STDDEV_SAMP(1-cosine) AS component_sd
  FROM lmv2_p3_stage1_similarity WHERE cosine IS NOT NULL GROUP BY cohort,resolution
)
SELECT cohort,NULL::VARCHAR AS resolution,component,component_sd,
       (component_sd IS NULL OR component_sd<1e-10) AS degenerate
FROM scalar_long
UNION ALL
SELECT cohort,resolution,component,component_sd,
       (component_sd IS NULL OR component_sd<1e-10) AS degenerate
FROM tech
")

DBI::dbExecute(con, "
CREATE OR REPLACE TABLE lmv2_p3_stage1_edges AS
WITH base AS (
  SELECT s.*,1-s.cosine AS tech_distance,
         c.log_patent_stock_5y-t.log_patent_stock_5y AS gap_log_patent_stock_5y,
         c.log_inventor_count_5y-t.log_inventor_count_5y AS gap_log_inventor_count_5y,
         c.patent_trajectory-t.patent_trajectory AS gap_patent_trajectory
FROM lmv2_p3_stage1_similarity s
  JOIN lmv2_p3_firm_units t ON t.cohort=s.cohort AND t.deal_id=s.deal_id AND t.role='treated'
  JOIN lmv2_p3_firm_units c ON c.cohort=s.cohort AND c.id_group=s.control_group AND c.role='control'
  WHERE s.resolution='ipc4'
), scales AS (
  SELECT cohort,
    MAX(CASE WHEN resolution IS NULL AND component='log_patent_stock_5y' THEN component_sd END) sd_stock,
    MAX(CASE WHEN resolution IS NULL AND component='log_inventor_count_5y' THEN component_sd END) sd_inventors,
    MAX(CASE WHEN resolution IS NULL AND component='patent_trajectory' THEN component_sd END) sd_trajectory
  FROM lmv2_p3_stage1_scalers GROUP BY cohort
), tech AS (
  SELECT cohort,resolution,component_sd sd_tech FROM lmv2_p3_stage1_scalers
  WHERE component='tech_distance'
)
SELECT b.*,
  SQRT(
    CASE WHEN sc.sd_stock IS NULL OR sc.sd_stock<1e-10 THEN 0 ELSE POW(b.gap_log_patent_stock_5y/sc.sd_stock,2) END+
    CASE WHEN sc.sd_inventors IS NULL OR sc.sd_inventors<1e-10 THEN 0 ELSE POW(b.gap_log_inventor_count_5y/sc.sd_inventors,2) END+
    CASE WHEN te.sd_tech IS NULL OR te.sd_tech<1e-10 THEN 0 ELSE POW(b.tech_distance/te.sd_tech,2) END
  ) AS distance_base,
  SQRT(
    CASE WHEN sc.sd_stock IS NULL OR sc.sd_stock<1e-10 THEN 0 ELSE POW(b.gap_log_patent_stock_5y/sc.sd_stock,2) END+
    CASE WHEN sc.sd_inventors IS NULL OR sc.sd_inventors<1e-10 THEN 0 ELSE POW(b.gap_log_inventor_count_5y/sc.sd_inventors,2) END+
    CASE WHEN sc.sd_trajectory IS NULL OR sc.sd_trajectory<1e-10 THEN 0 ELSE POW(b.gap_patent_trajectory/sc.sd_trajectory,2) END+
    CASE WHEN te.sd_tech IS NULL OR te.sd_tech<1e-10 THEN 0 ELSE POW(b.tech_distance/te.sd_tech,2) END
  ) AS distance_with_trajectory
FROM base b JOIN scales sc USING(cohort) JOIN tech te USING(cohort,resolution)
")

tables <- c(
  "lmv2_p3_group_year_patents", "lmv2_p3_inventor_year_typed",
  "lmv2_p3_ipc_code_map", "lmv2_p3_firm_units",
  "lmv2_p3_inventor_cohort_stats", "lmv2_p3_inventor_general_units",
  "lmv2_p3_treated_inventor_units",
  "lmv2_p3_firm_ipc_vectors", "lmv2_p3_treated_inventor_ipc_vectors",
  "lmv2_p3_stage1_similarity", "lmv2_p3_stage1_scalers", "lmv2_p3_stage1_edges"
)
for (table in tables) copy_db_table_to_parquet(con, table, "derived")

table_hash <- function(table) {
  cols <- DBI::dbListFields(con, table)
  expr <- paste(sprintf("COALESCE(CAST(%s AS VARCHAR),'<NA>')", DBI::dbQuoteIdentifier(con, cols)), collapse = ",")
  raw <- DBI::dbGetQuery(con, sprintf("
    SELECT COUNT(*) AS n_rows,
           CAST(SUM(CAST(HASH(%s) AS HUGEINT)) AS VARCHAR) AS hash_sum,
           CAST(BIT_XOR(HASH(%s)) AS VARCHAR) AS hash_xor
    FROM %s", expr, expr, DBI::dbQuoteIdentifier(con, table)))
  raw$logical_sha256 <- digest::digest(
    paste(raw$n_rows, raw$hash_sum, raw$hash_xor, sep = "|"),
    algo = "sha256", serialize = FALSE
  )
  raw
}

manifest <- do.call(rbind, lapply(tables, function(table) {
  h <- table_hash(table)
  data.frame(table = table, rows = h$n_rows, logical_sha256 = h$logical_sha256,
             stringsAsFactors = FALSE)
}))
manifest$p3_version <- LMV2_P3_VERSION
manifest$p3_config_hash <- LMV2_P3_CONFIG_HASH
manifest$p0_design_hash <- LMV2_DESIGN_HASH
manifest$p2_manifest_hash <- LMV2_P3_EFFECTIVE_CONFIG$p2_manifest_hash
manifest$amendment_hash <- LMV2_P3_EFFECTIVE_CONFIG$amendment_hash
utils::write.csv(manifest, file.path(LMV2_P3_PATHS$audit, "p3_interface_manifest.csv"),
                 row.names = FALSE, na = "")

message("P3 covariate build complete")

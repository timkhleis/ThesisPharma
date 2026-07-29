setwd("c:/Users/timkh/Documents/Thesis")
source("02_analysis/R/00_utils.R")
load_packages()

DUCKDB <- "c:/Users/timkh/Documents/Thesis/02_analysis/output/thesis_foundation.duckdb"
drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)

cat("=== cassi_deal_spine ===\n")
cat("Cols:", paste(DBI::dbListFields(con, "cassi_deal_spine"), collapse=", "), "\n")
n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM cassi_deal_spine")$n
cat("Total rows:", n, "\n")

cat("\nAcquirer group source breakdown:\n")
print(DBI::dbGetQuery(con,
  "SELECT acquirer_group_source, COUNT(*) AS n, COUNT(DISTINCT dealnumber) AS deals
   FROM cassi_deal_spine GROUP BY acquirer_group_source ORDER BY n DESC"))

cat("\nResolution summary:\n")
print(DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT dealnumber) AS unique_deals,
    SUM(CASE WHEN acquirer_group IS NOT NULL THEN 1 ELSE 0 END) AS acquirer_group_resolved,
    SUM(CASE WHEN target_group IS NOT NULL THEN 1 ELSE 0 END) AS target_group_resolved
  FROM cassi_deal_spine"))

cat("\n=== Sample rows ===\n")
print(DBI::dbGetQuery(con,
  "SELECT dealnumber, deal_year, deal_value, target_compcod, acquirer_compcod,
          target_group, acquirer_group, acquirer_group_source
   FROM cassi_deal_spine LIMIT 8"))

cat("\n=== Cross-check: merger_list target_nmb vs cassi_deal_spine dealnumber ===\n")
print(DBI::dbGetQuery(con, "
  SELECT
    COUNT(DISTINCT ml.target_nmb) AS ml_with_nmb,
    COUNT(DISTINCT CASE WHEN ds.dealnumber IS NOT NULL THEN ml.target_nmb END) AS ml_matched_in_spine
  FROM merger_list ml
  LEFT JOIN cassi_deal_spine ds
    ON CAST(ml.target_nmb AS VARCHAR) = ds.dealnumber"))

cat("\n=== merger_list deals NOT found in spine ===\n")
print(DBI::dbGetQuery(con, "
  SELECT ml.target_nmb, ml.target_year, ml.target_value, ml.acqui_firm
  FROM merger_list ml
  LEFT JOIN cassi_deal_spine ds ON CAST(ml.target_nmb AS VARCHAR) = ds.dealnumber
  WHERE ds.dealnumber IS NULL AND ml.target_nmb IS NOT NULL
  ORDER BY ml.target_year
  LIMIT 10"))

DBI::dbDisconnect(con, shutdown = TRUE)

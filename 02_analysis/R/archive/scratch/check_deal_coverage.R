setwd("c:/Users/timkh/Documents/Thesis")
source("02_analysis/R/00_utils.R")
load_packages()
drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, "02_analysis/output/thesis_foundation.duckdb", read_only = TRUE)

cat("=== Thesis deal coverage under new spine approach ===\n\n")

# All 513 thesis deals (basis = merger_list)
# New spine: join merger_list to cassi_deal_spine on (year, value)
# then to deal_map for acquirer resolution

res <- DBI::dbGetQuery(con, "
WITH ml_spine AS (
  SELECT
    ml.target_year,
    ml.target_value,
    ml.big,
    ds.dealnumber,
    ds.acquirer_group,
    ds.acquirer_group_source,
    ds.target_group,
    -- clean sample window
    CASE WHEN ml.target_year BETWEEN 1993 AND 2010 THEN 1 ELSE 0 END AS clean_window,
    -- placeholder acquirer
    CASE WHEN CAST(ds.acquirer_group AS VARCHAR) LIKE '999%' THEN 1 ELSE 0 END
      AS placeholder_acq,
    CASE WHEN ds.dealnumber IS NOT NULL THEN 1 ELSE 0 END AS in_spine
  FROM merger_list ml
  LEFT JOIN (
    SELECT DISTINCT dealnumber, deal_year, deal_value,
                    acquirer_group, acquirer_group_source, target_group
    FROM cassi_deal_spine
  ) ds ON ml.target_year = ds.deal_year AND ml.target_value = ds.deal_value
)
SELECT
  COUNT(*)                                          AS total_thesis_deals,
  SUM(in_spine)                                     AS in_spine,
  SUM(1 - in_spine)                                 AS not_in_spine,
  SUM(clean_window)                                 AS clean_window_total,
  SUM(in_spine * clean_window)                      AS spine_and_clean_window,
  SUM(in_spine * clean_window *
      (1 - placeholder_acq) *
      CASE WHEN acquirer_group IS NOT NULL THEN 1 ELSE 0 END)
                                                    AS spine_clean_acquirer_resolved,
  SUM(in_spine * clean_window * placeholder_acq)    AS spine_clean_placeholder
FROM ml_spine")

print(res)

cat("\n=== Breakdown by spine match and clean window ===\n")
print(DBI::dbGetQuery(con, "
WITH ml_spine AS (
  SELECT
    ml.target_year,
    ml.target_value,
    CASE WHEN ds.dealnumber IS NOT NULL THEN 1 ELSE 0 END AS in_spine,
    CASE WHEN ml.target_year BETWEEN 1993 AND 2010 THEN 1 ELSE 0 END AS clean_window,
    CASE WHEN CAST(ds.acquirer_group AS VARCHAR) LIKE '999%' THEN 1
         WHEN ds.acquirer_group IS NULL AND ds.dealnumber IS NOT NULL THEN 2
         ELSE 0 END AS acq_problem
  FROM merger_list ml
  LEFT JOIN (
    SELECT DISTINCT dealnumber, deal_year, deal_value, acquirer_group
    FROM cassi_deal_spine
  ) ds ON ml.target_year = ds.deal_year AND ml.target_value = ds.deal_value
)
SELECT
  in_spine,
  clean_window,
  COUNT(*) AS n_deals
FROM ml_spine
GROUP BY in_spine, clean_window
ORDER BY clean_window DESC, in_spine DESC"))

DBI::dbDisconnect(con, shutdown = TRUE)

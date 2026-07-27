setwd("c:/Users/timkh/Documents/Thesis")
source("02_analysis/R/00_utils.R")
load_packages()
drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, "02_analysis/output/thesis_foundation.duckdb", read_only = TRUE)

# --- 1. cross-check merger_list (513 deals) vs cassi_deal_spine via year+value ---
cat("=== merger_list (513 deals) vs cassi_deal_spine ===\n")
print(DBI::dbGetQuery(con, "
  SELECT
    COUNT(DISTINCT ml.target_year || '_' || CAST(ml.target_value AS VARCHAR))
      AS ml_deals,
    COUNT(DISTINCT CASE WHEN ds.dealnumber IS NOT NULL
      THEN ml.target_year || '_' || CAST(ml.target_value AS VARCHAR) END)
      AS matched_in_spine
  FROM merger_list ml
  LEFT JOIN cassi_deal_spine ds
    ON ml.target_year  = ds.deal_year
   AND ml.target_value = ds.deal_value"))

# --- 2. deal_map cols ---
cat("\ndeal_map cols:", paste(DBI::dbListFields(con, "deal_map"), collapse = ", "), "\n")
print(DBI::dbGetQuery(con, "SELECT * FROM deal_map LIMIT 3"))

# --- 3. inventor_status_reference cols ---
cat("\ninventor_status_reference cols:",
    paste(DBI::dbListFields(con, "inventor_status_reference"), collapse = ", "), "\n")
print(DBI::dbGetQuery(con, "SELECT * FROM inventor_status_reference LIMIT 3"))

# --- 4. how many spine deals overlap with ISR via year+value ---
cat("\n=== cassi_deal_spine vs inventor_status_reference ===\n")
print(DBI::dbGetQuery(con, "
  SELECT
    COUNT(DISTINCT ds.dealnumber) AS spine_deals,
    COUNT(DISTINCT CASE WHEN isr.target_year IS NOT NULL THEN ds.dealnumber END)
      AS spine_deals_in_isr
  FROM cassi_deal_spine ds
  LEFT JOIN inventor_status_reference isr
    ON ds.deal_year  = isr.target_year
   AND ds.deal_value = isr.target_value"))

DBI::dbDisconnect(con, shutdown = TRUE)

library(haven)

lm <- read_dta("c:/Users/timkh/Documents/Thesis/01_Data/L_merge.dta")
gh <- read_dta("c:/Users/timkh/Documents/Thesis/01_Data/L_group_history_target.dta")
gh_t <- subset(gh, merger_status == "target")

lm_dn  <- as.character(lm$dealnumber)
gh_nmb <- as.character(gh_t$merger_nmb)

# --- 1. Missing compcod_target in L_merge ---
lm_miss <- subset(lm, is.na(compcod_target))
cat("L_merge rows missing compcod_target:", nrow(lm_miss), "\n")
recoverable <- sum(as.character(lm_miss$dealnumber) %in% gh_nmb)
cat("Of those, dealnumber found in group history:", recoverable,
    "(can back-fill compcod from gh)\n")

# --- 2. What the group history gives us directly ---
cat("\n=== Group history target events ===\n")
cat("Total target rows:", nrow(gh_t), "\n")
cat("Unique merger_nmb:", length(unique(gh_nmb)), "\n")
cat("Unique compcod in target rows:", length(unique(gh_t$compcod)), "\n")

# Each merger_nmb may have multiple compcods (multiple companies in same deal)
deals_per_nmb <- as.data.frame(table(gh_nmb))
cat("\nDeals with 1 compcod:", sum(deals_per_nmb$Freq == 1), "\n")
cat("Deals with 2+ compcods:", sum(deals_per_nmb$Freq >= 2), "\n")
cat("Max compcods per deal:", max(deals_per_nmb$Freq), "\n")

# --- 3. Check cassi_deal_spine already built ---
cat("\n=== cassi_deal_spine (read via R) ===\n")
drv  <- duckdb::duckdb()
con  <- DBI::dbConnect(drv, "c:/Users/timkh/Documents/Thesis/02_analysis/output/thesis_foundation.duckdb")

spine <- DBI::dbGetQuery(con, "SELECT * FROM cassi_deal_spine LIMIT 0")
cat("Spine cols:", paste(names(spine), collapse=", "), "\n")
n_spine <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM cassi_deal_spine")$n
cat("Spine rows:", n_spine, "\n")

# how many unique dealnumbers in spine
n_deals <- DBI::dbGetQuery(con,
  "SELECT COUNT(DISTINCT dealnumber) AS n FROM cassi_deal_spine")$n
cat("Unique dealnumbers in spine:", n_deals, "\n")

# acquirer_group resolution breakdown
aq_src <- DBI::dbGetQuery(con,
  "SELECT acquirer_group_source, COUNT(*) AS n FROM cassi_deal_spine
   GROUP BY acquirer_group_source ORDER BY n DESC")
cat("\nAcquirer group source breakdown:\n")
print(aq_src)

# how many spine rows have acquirer_group resolved
resolved <- DBI::dbGetQuery(con,
  "SELECT
     COUNT(*) AS total,
     SUM(CASE WHEN acquirer_group IS NOT NULL THEN 1 ELSE 0 END) AS acquirer_resolved,
     SUM(CASE WHEN target_group IS NOT NULL THEN 1 ELSE 0 END) AS target_resolved
   FROM cassi_deal_spine")
cat("\nSpine resolution:\n")
print(resolved)

DBI::dbDisconnect(con, shutdown = TRUE)

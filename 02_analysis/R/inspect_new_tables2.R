library(haven)

lm <- read_dta("c:/Users/timkh/Documents/Thesis/01_Data/L_merge.dta")
gh <- read_dta("c:/Users/timkh/Documents/Thesis/01_Data/L_group_history_target.dta")
gh_t <- subset(gh, merger_status == "target")

cat("=== L_merge ===\n")
cat("Rows:", nrow(lm), "  Cols:", ncol(lm), "\n")
cat("Cols:", paste(names(lm), collapse=", "), "\n")
cat("year_merge:", min(lm$year_merge, na.rm=TRUE), "-", max(lm$year_merge, na.rm=TRUE), "\n")
cat("compcod_target non-NA:", sum(!is.na(lm$compcod_target)), "\n")
cat("compcod_acquirer non-NA:", sum(!is.na(lm$compcod_acquirer)), "\n")
cat("todrop_tar==1:", sum(lm$todrop_tar == 1, na.rm=TRUE), "\n")
cat("todrop_acq==1:", sum(lm$todrop_acq == 1, na.rm=TRUE), "\n")

cat("\n=== L_group_history_target (target rows) ===\n")
cat("Total rows:", nrow(gh), "  Target rows:", nrow(gh_t), "\n")
cat("Unique merger_nmb in target rows:", length(unique(gh_t$merger_nmb)), "\n")

cat("\n=== dealnumber <-> merger_nmb overlap ===\n")
lm_dn <- as.character(lm$dealnumber)
gh_nmb <- as.character(gh_t$merger_nmb)
cat("gh merger_nmb in L_merge dealnumber:", sum(gh_nmb %in% lm_dn), "of", length(gh_nmb), "\n")
cat("L_merge dealnumber in gh merger_nmb:", sum(lm_dn %in% gh_nmb), "of", length(lm_dn), "\n")

cat("\n=== Sample merger rows from L_merge (compcod_target not NA) ===\n")
lm_sub <- subset(lm, !is.na(compcod_target))
cat("Rows with compcod_target:", nrow(lm_sub), "\n")
print(head(lm_sub[, c("dealnumber","year_merge","value","compcod_target","compcod_acquirer","acquirer","target")], 8))

cat("\n=== cassi_deal_spine cols (from parquet) ===\n")
spine_path <- "c:/Users/timkh/Documents/Thesis/02_analysis/output/parquet/helper/cassi_deal_spine.parquet"
if (file.exists(spine_path)) cat("cassi_deal_spine.parquet EXISTS\n") else cat("NOT FOUND\n")

cat("\n=== cassi_deal_group_spine cols ===\n")
dgs_path <- "c:/Users/timkh/Documents/Thesis/02_analysis/output/parquet/helper/cassi_deal_group_spine.parquet"
if (file.exists(dgs_path)) cat("cassi_deal_group_spine.parquet EXISTS\n") else cat("NOT FOUND\n")

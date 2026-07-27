# Local Match v2 — P5b stayer selection diagnostics
#
# Describes post-treatment retention selection without changing certified
# stayer weights. Compares pre-deal output for initially retained inventors,
# leavers, and no-post-patent inventors, and reconciles the support funnel.
# Missing inventor-year rows are zero output in the fixed t=-5,...,-1 window.

options(stringsAsFactors = FALSE)
root <- "C:/Users/timkh/Documents/Thesis/.worktrees/lmv2-p6-outcomes"
out_dir <- file.path(root, "02_analysis/output/audit/local_match_v2/P5B_STAYER_SELECTION_DIAGNOSTICS")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
stayer_root <- Sys.getenv("LMV2_STAYER_ROOT", "C:/Users/timkh/.codex/worktrees/081f/Thesis")
partition <- file.path(stayer_root, "02_analysis/output/audit/local_match_v2/P5B_STAYER_S0_S2/treated_retention_partition.parquet")
funnel_csv <- file.path(stayer_root, "02_analysis/output/audit/local_match_v2/P5B_STAYER_S0_S2/treated_retention_funnel.csv")
db_candidates <- c(file.path(root, "02_analysis/output/thesis_foundation.duckdb"), file.path(stayer_root, "02_analysis/output/thesis_foundation.duckdb"), "C:/Users/timkh/Documents/Thesis/.worktrees/lmv2-foundation/02_analysis/output/thesis_foundation.duckdb")
db <- db_candidates[file.exists(db_candidates)][1]
duckdb_bin <- Sys.getenv("DUCKDB_BIN", "duckdb")
stopifnot(file.exists(partition), !is.na(db), file.exists(db))
sql_escape <- function(x) gsub("'", "''", normalizePath(x, winslash = "/", mustWork = FALSE), fixed = TRUE)
run_duckdb <- function(sql) {
  z <- system2(duckdb_bin, c(shQuote(db), "-c", shQuote(sql)), stdout = TRUE, stderr = TRUE)
  status <- attr(z, "status")
  if (!is.null(status) && status != 0) stop(paste(z, collapse = "\n"))
  invisible(z)
}

metrics_csv <- file.path(out_dir, "selection_inventor_predeal_metrics.csv")
metrics_sql <- sprintf("COPY (WITH p AS (SELECT DISTINCT cohort, deal_id, codinv, retention_status FROM read_parquet('%s') WHERE is_primary AND retention_status IN ('initially_retained','leaver','no_post_patent')), y AS (SELECT p.*, iy.year, COALESCE(iy.patent_count, 0)::DOUBLE AS patent_count FROM p LEFT JOIN inventor_year iy ON iy.codinv = p.codinv AND iy.year BETWEEN p.cohort - 5 AND p.cohort - 1) SELECT cohort, deal_id, codinv, retention_status, SUM(patent_count) AS pre_patent_total, SUM(patent_count)/5.0 AS pre_patent_mean, SUM(CASE WHEN patent_count > 0 THEN 1 ELSE 0 END)/5.0 AS pre_active_rate, COUNT(DISTINCT year) AS observed_pre_years FROM y GROUP BY 1,2,3,4) TO '%s' (HEADER, DELIMITER ',');", sql_escape(partition), sql_escape(metrics_csv))
run_duckdb(metrics_sql)
metrics <- read.csv(metrics_csv, check.names = FALSE)

num_summary <- function(x) c(n = length(x), mean = mean(x), sd = sd(x), median = median(x), p25 = as.numeric(quantile(x, .25)), p75 = as.numeric(quantile(x, .75)))
statuses <- c("initially_retained", "leaver", "no_post_patent")
summary_rows <- do.call(rbind, lapply(statuses, function(s) {
  d <- metrics[metrics$retention_status == s, , drop = FALSE]
  a <- num_summary(d$pre_patent_mean); b <- num_summary(d$pre_active_rate)
  data.frame(retention_status=s, inventors=length(unique(d$codinv)), deals=length(unique(d$deal_id)), pre_patent_mean_n=a[1], pre_patent_mean_mean=a[2], pre_patent_mean_sd=a[3], pre_patent_mean_median=a[4], pre_patent_mean_p25=a[5], pre_patent_mean_p75=a[6], pre_active_rate_n=b[1], pre_active_rate_mean=b[2], pre_active_rate_sd=b[3], pre_active_rate_median=b[4], pre_active_rate_p25=b[5], pre_active_rate_p75=b[6])
}))
write.csv(summary_rows, file.path(out_dir, "selection_group_summary.csv"), row.names = FALSE)

pooled_sd <- function(a,b) sqrt(((length(a)-1)*var(a)+(length(b)-1)*var(b))/(length(a)+length(b)-2))
pair_rows <- do.call(rbind, lapply(c("leaver","no_post_patent"), function(s) {
  a <- metrics$pre_patent_mean[metrics$retention_status=="initially_retained"]; b <- metrics$pre_patent_mean[metrics$retention_status==s]
  c2 <- metrics$pre_active_rate[metrics$retention_status=="initially_retained"]; d2 <- metrics$pre_active_rate[metrics$retention_status==s]
  data.frame(comparison=paste("initially_retained_minus",s), patent_mean_difference=mean(a)-mean(b), patent_standardized_difference=(mean(a)-mean(b))/pooled_sd(a,b), active_rate_difference=mean(c2)-mean(d2), active_rate_standardized_difference=(mean(c2)-mean(d2))/pooled_sd(c2,d2))
}))
write.csv(pair_rows, file.path(out_dir, "selection_pairwise_differences.csv"), row.names = FALSE)

if (file.exists(funnel_csv)) { funnel <- read.csv(funnel_csv, check.names=FALSE); write.csv(funnel, file.path(out_dir,"selection_funnel.csv"), row.names=FALSE) } else funnel <- data.frame()
s3 <- file.path(stayer_root,"02_analysis/output/audit/local_match_v2/P5B_STAYER_S3/s3_summary.csv")
if (file.exists(s3)) file.copy(s3,file.path(out_dir,"selection_support_summary.csv"),overwrite=TRUE)

checks <- data.frame(check=c("partition_exists","metrics_nonempty","statuses_complete","no_duplicate_inventor_deal","funnel_available","support_summary_available"), pass=c(file.exists(partition),nrow(metrics)>0,all(unique(metrics$retention_status)%in%statuses),!anyDuplicated(metrics[c("deal_id","codinv")]),file.exists(funnel_csv),file.exists(s3)), detail=c(partition,nrow(metrics),paste(sort(unique(metrics$retention_status)),collapse=";"),sum(duplicated(metrics[c("deal_id","codinv")])),funnel_csv,s3))
write.csv(checks,file.path(out_dir,"selection_certification.csv"),row.names=FALSE)
if (!all(checks$pass)) stop("Selection diagnostic certification failed")

writeLines(c("# P5b stayer selection diagnostics","","## Interpretation","","Retention is defined using post-acquisition patent affiliation and is therefore a post-treatment selection variable. The initially-retained comparison is descriptive of who remains observable in the focal patent ecosystem; it is not an unbiased estimate for the full treated inventor cohort.","","Pre-deal productivity uses the fixed annual window t=-5,...,-1. Missing inventor-year rows are zero-filled. The outputs report both the extensive margin (share of pre-years with at least one patent) and intensive margin (patents per inventor-year).","","The funnel and support files are reconciled to certified P5b S0-S3 artifacts. Support loss is a design-coverage statistic, not evidence that excluded inventors have a particular outcome.","","## Files","","- `selection_group_summary.csv`: status-specific pre-deal distributions.","- `selection_pairwise_differences.csv`: retained-minus-leaver/no-post differences and standardized differences.","- `selection_funnel.csv`: certified treated retention funnel.","- `selection_support_summary.csv`: certified P5b support summary.","- `selection_certification.csv`: source, duplicate, and completeness checks."),file.path(out_dir,"selection_diagnostics_report.md"))
cat("Selection diagnostics complete. Output:",out_dir,"\n")

# Local Match v2 — raw CS versus balanced quantity comparability audit
#
# Reconciles sample/timing/outcome definitions and expresses the conventional
# CS(2021) patent-count estimate relative to raw pre-treatment output and its
# implied post-treatment counterfactual. This is an audit, not a new design.

options(stringsAsFactors = FALSE)
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
db_path <- file.path(root, "02_analysis/output/thesis_foundation.duckdb")
raw_dir <- file.path(root, "02_analysis/output/results/cs2021")
balanced_dir <- file.path(root, "02_analysis/output/audit/local_match_v2/P6_QUANTITY_COMMUNICATION_PACKAGE")
out_dir <- file.path(root, "02_analysis/output/audit/local_match_v2/P6_RAW_BALANCED_COMPARABILITY")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
source(file.path(root, "02_analysis/R/00_utils.R"))
use_project_library()
shared_candidates <- c(
  file.path(root, ".r_libs"),
  file.path(root, "..", "..", ".r_libs")
)
shared_lib <- shared_candidates[dir.exists(shared_candidates)][1]
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
stopifnot(requireNamespace("DBI", quietly=TRUE), requireNamespace("duckdb", quietly=TRUE))

con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only=TRUE)
on.exit(DBI::dbDisconnect(con, shutdown=TRUE), add=TRUE)
raw_sample <- DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT codinv) AS inventors, COUNT(DISTINCT deal_id) AS deals, COUNT(DISTINCT deal_year) AS cohorts, MIN(deal_year) AS first_cohort, MAX(deal_year) AS last_cohort, MIN(event_time) AS min_event, MAX(event_time) AS max_event FROM cs2021_estimation_panel")
raw_means <- DBI::dbGetQuery(con, "SELECT event_time, AVG(patent_count) AS mean_patent_count, COUNT(*) AS observations FROM cs2021_estimation_panel WHERE event_time BETWEEN -5 AND 5 GROUP BY event_time ORDER BY event_time")
raw_pre <- DBI::dbGetQuery(con, "SELECT AVG(patent_count) FILTER (event_time BETWEEN -5 AND -1) AS mean_pre_patent_count, AVG(patent_count) FILTER (event_time BETWEEN 1 AND 5) AS mean_post_patent_count FROM cs2021_estimation_panel")

raw_dynamic <- read.csv(file.path(raw_dir, "dynamic_att_patent_count.csv"), check.names=FALSE)
post <- raw_dynamic[raw_dynamic$event_time %in% 1:5, , drop=FALSE]
raw_annual_att <- mean(post$att)
raw_cumulative_att <- sum(post$att)
raw_counterfactual <- raw_pre$mean_post_patent_count - raw_annual_att
raw_metrics <- data.frame(
  metric=c("raw_annual_att", "raw_five_year_cumulative_att", "raw_pre_treatment_mean", "raw_observed_post_mean", "raw_implied_post_counterfactual", "raw_effect_percent_of_pre_treatment", "raw_effect_percent_of_counterfactual"),
  value=c(raw_annual_att, raw_cumulative_att, raw_pre$mean_pre_patent_count, raw_pre$mean_post_patent_count, raw_counterfactual, raw_annual_att/raw_pre$mean_pre_patent_count, raw_annual_att/raw_counterfactual),
  definition=c("Mean ATT over t=+1,...,+5", "Sum of dynamic ATT over t=+1,...,+5", "Mean patent count over t=-5,...,-1", "Observed treated mean over t=+1,...,+5", "Observed treated post mean minus annual ATT", "Annual ATT divided by annual pre-treatment output", "Annual ATT divided by implied annual counterfactual output")
)
write.csv(raw_sample, file.path(out_dir,"raw_cs_sample_audit.csv"), row.names=FALSE)
write.csv(raw_means, file.path(out_dir,"raw_cs_event_means.csv"), row.names=FALSE)
write.csv(raw_metrics, file.path(out_dir,"raw_cs_percentage_effects.csv"), row.names=FALSE)

balanced_results <- read.csv(file.path(balanced_dir,"quantity_results_appendix.csv"), check.names=FALSE)
balanced_post <- read.csv(file.path(balanced_dir,"quantity_post_weighted_means.csv"), check.names=FALSE)
headline <- balanced_results[balanced_results$design=="P5c headline" & balanced_results$sample=="full_1994_2010" & balanced_results$effect_scale=="per inventor-year",,drop=FALSE]
balanced_summary <- data.frame(
  metric=c("balanced_nominal_deals", "balanced_annual_att", "balanced_percent_of_pre_treatment", "balanced_percent_of_counterfactual", "balanced_control_post_mean", "balanced_treated_post_mean"),
  value=c(headline$nominal_deals, headline$estimate, headline$relative_to_pre_treatment_output, headline$relative_to_matched_post_counterfactual, balanced_post$patent_mean[balanced_post$arm=="control"], balanced_post$patent_mean[balanced_post$arm=="treated"]),
  definition=c("Headline full 1994-2010 nominal deals", "P5c headline annual ATT", "Certified headline relative-to-pre measure", "Certified headline relative-to-counterfactual measure", "Weighted post-treatment control mean", "Weighted post-treatment treated mean")
)
write.csv(balanced_summary, file.path(out_dir,"balanced_headline_comparison.csv"), row.names=FALSE)

checks <- data.frame(
  check=c("raw_panel_exists","raw_dynamic_exists","balanced_appendix_exists","raw_dynamic_has_all_post_years","raw_panel_has_fixed_five_pre_years"),
  pass=c(file.exists(db_path),file.exists(file.path(raw_dir,"dynamic_att_patent_count.csv")),file.exists(file.path(balanced_dir,"quantity_results_appendix.csv")),all(post$event_time==1:5),all(raw_means$observations[raw_means$event_time %in% -5:-1]==raw_sample$inventors)),
  detail=c(db_path,raw_dir,balanced_dir,paste(post$event_time,collapse=","),paste(raw_means$observations[raw_means$event_time %in% -5:-1],collapse=","))
)
write.csv(checks,file.path(out_dir,"comparability_certification.csv"),row.names=FALSE)
if (!all(checks$pass)) stop("Comparability audit failed")

writeLines(c("# Raw CS versus balanced quantity comparability audit","","The conventional CS estimate is computed on the archived unconditional panel; the balanced values are read from the certified P5c communication package.","","The raw counterfactual is constructed as the observed treated post-treatment mean minus the average post-treatment ATT. Percentages are signed effects: negative values indicate a decline.","","The raw and balanced estimates should not be compared as if they were the same estimand. The raw panel covers a broader cohort and deal window and does not reweight controls to the treated pre-treatment population."),file.path(out_dir,"comparability_audit_report.md"))
cat("Comparability audit complete:",out_dir,"\n")

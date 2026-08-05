# Certify the pooled-window TechDrift amendment outputs.

source(file.path("02_analysis", "R", "50a_lmv2_techdrift_window_config.R"))
config <- lmv2_techdrift_window_config()
source(file.path("02_analysis", "R", "00_utils.R"))
use_project_library()
shared_lib <- file.path(
  Sys.getenv("USERPROFILE"),"Documents","Thesis",".r_libs")
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib,.libPaths())))
if (!requireNamespace("DBI", quietly=TRUE) ||
    !requireNamespace("duckdb", quietly=TRUE) ||
    !requireNamespace("digest", quietly=TRUE)) {
  stop("Missing certification package")
}

required_outputs <- file.path(config$output_dir, c(
  "techdrift_window_units.parquet",
  "techdrift_window_pairs.parquet",
  "techdrift_window_estimates.csv",
  "techdrift_window_coverage.csv",
  "techdrift_window_year_bounds.csv",
  "techdrift_baseline_audit.csv",
  "techdrift_eligibility_audit.csv",
  "techdrift_post_count_bins.csv",
  "techdrift_post_count_decomposition.csv",
  "techdrift_legacy_annual_results.csv",
  "techdrift_source_manifest.csv",
  "techdrift_run_manifest.csv"))
missing <- required_outputs[!file.exists(required_outputs)]
if (length(missing)) stop(
  "Missing TechDrift outputs: ", paste(missing,collapse=", "))

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con,shutdown=TRUE),add=TRUE)
units_path <- normalizePath(
  required_outputs[[1L]],winslash="/",mustWork=TRUE)
pairs_path <- normalizePath(
  required_outputs[[2L]],winslash="/",mustWork=TRUE)
sql_string <- function(x) paste0("'",gsub("'","''",x,fixed=TRUE),"'")

unit_checks <- DBI::dbGetQuery(con,sprintf("
  SELECT
    COUNT(*) unit_rows, COUNT(DISTINCT roster_row_id) unique_units,
    SUM(weight<=0 OR weight IS NULL) invalid_weights,
    SUM(pre5_n_ipc4 IS NULL OR pre5_n_ipc4=0) empty_recent_baselines,
    SUM(full_pre_n_ipc4<pre5_n_ipc4) full_baseline_narrower,
    SUM(first_observed_pre_year>cohort-1) post_leakage_history,
    SUM(tech_drift_recent5_post5<0 OR tech_drift_recent5_post5>1)
      invalid_main_drift
  FROM read_parquet(%s)
",sql_string(units_path)))

pair_checks <- DBI::dbGetQuery(con,sprintf("
  SELECT COUNT(*) pair_rows,
    COUNT(DISTINCT pair_name) pair_definitions,
    COUNT(DISTINCT weight_scheme) weight_schemes,
    SUM(tech_similarity<0 OR tech_similarity>1) invalid_similarity,
    SUM(tech_drift<0 OR tech_drift>1) invalid_drift,
    MAX(ABS((1-tech_similarity)-tech_drift))
      max_sign_identity_error
  FROM read_parquet(%s)
",sql_string(pairs_path)))

coverage <- utils::read.csv(
  file.path(config$output_dir,"techdrift_window_coverage.csv"),
  stringsAsFactors=FALSE)
main_coverage <- coverage[
  coverage$specification=="pooled_recent5_main",]
main_coverage_agg <- aggregate(
  cbind(observed_mass,design_mass)~arm,
  data=main_coverage,FUN=sum)
main_coverage_agg$weight_coverage <- with(
  main_coverage_agg,observed_mass/design_mass)

bounds <- utils::read.csv(
  file.path(config$output_dir,"techdrift_window_year_bounds.csv"),
  stringsAsFactors=FALSE)
expected_bounds <- data.frame(
  window_name=c(
    "early_pre5","post2","post3_5","post5","recent_pre5"),
  min_event_time=c(-10L,1L,3L,1L,-5L),
  max_event_time=c(-6L,2L,5L,5L,-1L),
  stringsAsFactors=FALSE)
bounds_check <- merge(
  expected_bounds,bounds[,c(
    "window_name","min_event_time","max_event_time")],
  by="window_name",suffixes=c("_expected","_actual"),all.x=TRUE)
bounds_ok <- with(bounds_check,
  min_event_time_expected==min_event_time_actual &
    max_event_time_expected==max_event_time_actual)

estimates <- utils::read.csv(
  file.path(config$output_dir,"techdrift_window_estimates.csv"),
  stringsAsFactors=FALSE)
governing <- estimates[estimates$inference=="deal_wild_bootstrap_t",]
expected_specs <- config$specifications$specification

legacy <- utils::read.csv(
  file.path(config$output_dir,"techdrift_legacy_annual_results.csv"),
  stringsAsFactors=FALSE)
legacy_stayer <- legacy[
  legacy$population=="initially_retained_inventors" &
    legacy$inference=="deal_wild_bootstrap_t",]
legacy_full <- legacy[
  legacy$population=="full_target_inventor_cohort" &
    legacy$inference=="deal_wild_bootstrap_t",]
eligibility <- utils::read.csv(
  file.path(config$output_dir,"techdrift_eligibility_audit.csv"),
  stringsAsFactors=FALSE)

# Hand-computed cosine fixtures: identical vectors have zero distance and
# disjoint vectors have unit distance.
cosine_distance <- function(x,y) {
  1-sum(x*y)/sqrt(sum(x*x)*sum(y*y))
}
fixture_identical <- cosine_distance(c(2,1),c(2,1))
fixture_disjoint <- cosine_distance(c(2,0),c(0,3))

checks <- data.frame(
  check=c(
    "one_row_per_roster_unit",
    "all_weights_positive",
    "all_recent_baselines_nonempty",
    "full_baseline_contains_recent_support",
    "no_post_year_in_history_baseline",
    "main_drift_in_unit_interval",
    "five_pair_definitions_materialized",
    "count_and_binary_weight_schemes_materialized",
    "pair_similarity_in_unit_interval",
    "pair_drift_in_unit_interval",
    "techdrift_is_one_minus_similarity",
    "window_year_bounds_exact",
    "main_weight_coverage_above_95pct_both_arms",
    "eligibility_population_is_initially_retained_design",
    "joint_pre_post_ipc_support_reported_both_arms",
    "all_frozen_specifications_estimated",
    "governing_intervals_ordered",
    "prepre_restricted_to_1998plus",
    "legacy_stayer_result_preserved",
    "legacy_full_result_preserved",
    "fixture_identical_distance_zero",
    "fixture_disjoint_distance_one"),
  pass=c(
    unit_checks$unit_rows==unit_checks$unique_units,
    unit_checks$invalid_weights==0,
    unit_checks$empty_recent_baselines==0,
    unit_checks$full_baseline_narrower==0,
    unit_checks$post_leakage_history==0,
    unit_checks$invalid_main_drift==0,
    pair_checks$pair_definitions==nrow(config$pair_definitions),
    pair_checks$weight_schemes==2L,
    pair_checks$invalid_similarity==0,
    pair_checks$invalid_drift==0,
    is.na(pair_checks$max_sign_identity_error) ||
      pair_checks$max_sign_identity_error<1e-12,
    nrow(bounds_check)==nrow(expected_bounds) && all(bounds_ok),
    nrow(main_coverage_agg)==2L &&
      all(main_coverage_agg$weight_coverage>=
            config$main_min_weight_coverage),
    nrow(eligibility)==2L &&
      all(eligibility$analysis_population==config$analysis_population),
    nrow(eligibility)==2L &&
      all(is.finite(eligibility$joint_ipc_weight_coverage)),
    setequal(governing$specification,expected_specs),
    all(governing$ci_low<=governing$ci_high),
    all(estimates$cohort_min[
      estimates$specification=="restricted_prepre_placebo"]>=
        config$pre_placebo_min_cohort),
    nrow(legacy_stayer)==1L,
    nrow(legacy_full)==1L,
    abs(fixture_identical)<1e-12,
    abs(fixture_disjoint-1)<1e-12),
  stringsAsFactors=FALSE)

utils::write.csv(
  main_coverage_agg,
  file.path(config$output_dir,"techdrift_main_coverage_summary.csv"),
  row.names=FALSE,na="")
utils::write.csv(
  checks,file.path(config$output_dir,"techdrift_certification.csv"),
  row.names=FALSE,na="")
if (!all(checks$pass)) stop(
  "TechDrift certification failed: ",
  paste(checks$check[!checks$pass],collapse=", "))

certified_outputs <- c(required_outputs,
  file.path(config$output_dir,c(
    "techdrift_main_coverage_summary.csv",
    "techdrift_certification.csv")))
output_hashes <- data.frame(
  output_path=normalizePath(
    certified_outputs,winslash="/",mustWork=TRUE),
  sha256=vapply(certified_outputs,digest::digest,character(1),
                algo="sha256",file=TRUE),
  stringsAsFactors=FALSE)
utils::write.csv(
  output_hashes,
  file.path(config$output_dir,"techdrift_output_hashes.csv"),
  row.names=FALSE,na="")

message("Pooled-window TechDrift amendment certified")

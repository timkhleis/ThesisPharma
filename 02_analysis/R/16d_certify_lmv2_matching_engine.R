# ============================================================================
# 16d_certify_lmv2_matching_engine.R -- independent P3 acceptance checks
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(BASE, "R", "16c_lmv2_matching_utils.R"))
for (pkg in c("DBI", "duckdb")) if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)

dir.create(LMV2_P3_PATHS$audit, recursive = TRUE, showWarnings = FALSE)
con <- DBI::dbConnect(duckdb::duckdb(), file.path(BASE, "output", "thesis_foundation.duckdb"))
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")
DBI::dbExecute(con, "PRAGMA threads=2")

scalar <- function(sql) DBI::dbGetQuery(con, sql)[[1]][1]
checks <- list()
add_check <- function(check, observed, expected, pass) {
  checks[[length(checks) + 1L]] <<- data.frame(
    check = check, observed = as.character(observed), expected = as.character(expected),
    pass = isTRUE(pass), stringsAsFactors = FALSE
  )
}

tables <- c(
  "lmv2_p3_group_year_patents", "lmv2_p3_inventor_year_typed",
  "lmv2_p3_ipc_code_map", "lmv2_p3_firm_units", "lmv2_p3_inventor_cohort_stats",
  "lmv2_p3_inventor_general_units", "lmv2_p3_treated_inventor_units",
  "lmv2_p3_firm_ipc_vectors", "lmv2_p3_treated_inventor_ipc_vectors",
  "lmv2_p3_stage1_similarity", "lmv2_p3_stage1_scalers", "lmv2_p3_stage1_edges"
)
present <- vapply(tables, DBI::dbExistsTable, logical(1), conn = con)
add_check("all_p3_interfaces_exist", paste(present, collapse = ","), "all TRUE", all(present))
if (!all(present)) stop("P3 interfaces missing")

manifest <- utils::read.csv(file.path(LMV2_P3_PATHS$audit, "p3_interface_manifest.csv"),
                            stringsAsFactors = FALSE)
add_check("manifest_has_all_interfaces", nrow(manifest), length(tables),
          setequal(manifest$table, tables))
add_check("manifest_p0_hash", unique(manifest$p0_design_hash), LMV2_DESIGN_HASH,
          identical(unique(manifest$p0_design_hash), LMV2_DESIGN_HASH))
add_check("manifest_p2_hash", unique(manifest$p2_manifest_hash),
          LMV2_P3_EFFECTIVE_CONFIG$p2_manifest_hash,
          identical(unique(manifest$p2_manifest_hash), LMV2_P3_EFFECTIVE_CONFIG$p2_manifest_hash))
add_check("manifest_amendment_hash", unique(manifest$amendment_hash),
          LMV2_P3_EFFECTIVE_CONFIG$amendment_hash,
          identical(unique(manifest$amendment_hash), LMV2_P3_EFFECTIVE_CONFIG$amendment_hash))
add_check("manifest_config_hash", unique(manifest$p3_config_hash), LMV2_P3_CONFIG_HASH,
          identical(unique(manifest$p3_config_hash), LMV2_P3_CONFIG_HASH))

resolutions <- DBI::dbGetQuery(con, "SELECT DISTINCT resolution FROM lmv2_p3_ipc_code_map ORDER BY 1")$resolution
add_check("three_ipc_resolutions", paste(resolutions, collapse = ","),
          paste(LMV2_P3$technology$resolutions, collapse = ","),
          setequal(resolutions, LMV2_P3$technology$resolutions))

fixture <- "A61K031/00"
parsed <- vapply(LMV2_P3$technology$resolutions, function(r) lmv2_ipc_feature(fixture, r), character(1))
add_check("ipc_parser_fixture", paste(parsed, collapse = ","), "A61K,A61K31,A61K31/00",
          identical(unname(parsed), c("A61K", "A61K31", "A61K31/00")))

add_check("firm_unit_unique_key",
          scalar("SELECT COUNT(*)-COUNT(DISTINCT (cohort,role,COALESCE(deal_id,-1),id_group)) FROM lmv2_p3_firm_units"),
          0, scalar("SELECT COUNT(*)-COUNT(DISTINCT (cohort,role,COALESCE(deal_id,-1),id_group)) FROM lmv2_p3_firm_units") == 0)
add_check("general_inventor_unique_key",
          scalar("SELECT COUNT(*)-COUNT(DISTINCT (cohort,role,COALESCE(deal_id,-1),codinv)) FROM lmv2_p3_inventor_general_units"),
          0, scalar("SELECT COUNT(*)-COUNT(DISTINCT (cohort,role,COALESCE(deal_id,-1),codinv)) FROM lmv2_p3_inventor_general_units") == 0)

expected_general <- scalar("SELECT (SELECT COUNT(*) FROM lmv2_treated_primary)+(SELECT COUNT(*) FROM lmv2_control_inventor_eligibility)")
observed_general <- scalar("SELECT COUNT(*) FROM lmv2_p3_inventor_general_units")
add_check("general_inventor_roster_complete", observed_general, expected_general,
          observed_general == expected_general)
treated_n <- scalar("SELECT COUNT(*) FROM lmv2_p3_treated_inventor_units")
expected_treated <- scalar("SELECT COUNT(*) FROM lmv2_treated_primary")
add_check("treated_inventor_roster_complete", treated_n, expected_treated, treated_n == expected_treated)

firm_mismatch <- scalar("
SELECT COUNT(*) FROM lmv2_p3_firm_units f
JOIN lmv2_control_firm_eligibility c
  ON c.cohort=f.cohort AND CAST(c.control_group AS BIGINT)=f.id_group
WHERE f.role='control' AND
 (f.patent_stock_5y<>c.pre_patent_stock OR f.inventor_count_5y<>c.pre_inventor_count)")
add_check("control_firm_counts_equal_certified_p2", firm_mismatch, 0, firm_mismatch == 0)

control_window_direct_mismatch <- scalar("
WITH direct AS (
  SELECT f.cohort,f.id_group,
         COALESCE(SUM(CASE WHEN g.year BETWEEN f.cohort-5 AND f.cohort-3
                           THEN g.patent_count ELSE 0 END),0) AS patents_early,
         COALESCE(SUM(CASE WHEN g.year BETWEEN f.cohort-2 AND f.cohort-1
                           THEN g.patent_count ELSE 0 END),0) AS patents_recent
  FROM lmv2_p3_firm_units f
  LEFT JOIN lmv2_p3_group_year_patents g
    ON g.id_group=f.id_group
   AND g.year BETWEEN f.cohort-5 AND f.cohort-1
  WHERE f.role='control'
  GROUP BY f.cohort,f.id_group
)
SELECT COUNT(*)
FROM lmv2_p3_firm_units f
JOIN direct d USING(cohort,id_group)
WHERE f.role='control'
  AND (f.patents_early<>d.patents_early
       OR f.patents_recent<>d.patents_recent)")
add_check("control_firm_windows_equal_direct_group_year_reconstruction",
          control_window_direct_mismatch, 0, control_window_direct_mismatch == 0)

control_window_stock_mismatch <- scalar("
SELECT COUNT(*) FROM lmv2_p3_firm_units
WHERE role='control'
  AND patents_early+patents_recent<>patent_stock_5y")
add_check("control_firm_windows_sum_to_certified_pre_patent_stock",
          control_window_stock_mismatch, 0, control_window_stock_mismatch == 0)

trajectory_bad <- scalar("
SELECT
 (SELECT COUNT(*) FROM lmv2_p3_firm_units
  WHERE ABS(patent_trajectory-(LN(1+patents_recent/2.0)-LN(1+patents_early/3.0)))>1e-12)
 +
 (SELECT COUNT(*) FROM lmv2_p3_inventor_general_units
  WHERE ABS(patent_trajectory-(LN(1+patents_recent/2.0)-LN(1+patents_early/3.0)))>1e-12)")
add_check("trajectory_exact_annualized_formula", trajectory_bad, 0, trajectory_bad == 0)

post_leak <- scalar("SELECT COUNT(*) FROM lmv2_p3_inventor_general_units WHERE last_pre_patent_year>cohort-1")
add_check("no_post_event_patent_information", post_leak, 0, post_leak == 0)
recency_bad <- scalar("SELECT COUNT(*) FROM lmv2_p3_inventor_general_units WHERE recency_bin NOT BETWEEN 0 AND 3 OR recency_bin IS NULL")
add_check("recency_bins_complete_and_bounded", recency_bad, 0, recency_bad == 0)
focal_bad <- scalar("
SELECT COUNT(*) FROM lmv2_p3_treated_inventor_units
WHERE focal_group_tenure IS NULL OR focal_group_tenure<1
   OR focal_group_exclusivity IS NULL OR focal_group_exclusivity<0 OR focal_group_exclusivity>1")
add_check("treated_focal_covariates_complete_and_bounded", focal_bad, 0, focal_bad == 0)
focal_route_bad <- scalar("
SELECT COUNT(*) FROM lmv2_p3_treated_inventor_units
WHERE NOT has_group_focal_evidence AND NOT has_target_company_focal_evidence")
add_check("treated_focal_covariates_use_p2_dual_evidence_route",
          focal_route_bad, 0, focal_route_bad == 0)
focal_routes <- DBI::dbGetQuery(con, "
SELECT cohort,
       SUM(has_group_focal_evidence::INTEGER) AS inventors_with_group_evidence,
       SUM(has_target_company_focal_evidence::INTEGER) AS inventors_with_target_company_evidence,
       SUM((NOT has_group_focal_evidence AND has_target_company_focal_evidence)::INTEGER)
         AS inventors_relying_on_company_route,
       SUM(company_only_focal_patent_count_5y) AS company_only_preperiod_patents
FROM lmv2_p3_treated_inventor_units GROUP BY cohort ORDER BY cohort")
utils::write.csv(focal_routes,
                 file.path(LMV2_P3_PATHS$audit, "p3_treated_focal_evidence_routes.csv"),
                 row.names = FALSE, na = "")

firm_vector_dev <- scalar("
SELECT COALESCE(MAX(ABS(total-1)),0) FROM (
 SELECT cohort,id_group,resolution,SUM(frequency) total
 FROM lmv2_p3_firm_ipc_vectors GROUP BY cohort,id_group,resolution)")
inv_vector_dev <- scalar("
SELECT COALESCE(MAX(ABS(total-1)),0) FROM (
 SELECT cohort,deal_id,codinv,resolution,SUM(frequency) total
 FROM lmv2_p3_treated_inventor_ipc_vectors GROUP BY cohort,deal_id,codinv,resolution)")
add_check("firm_vectors_normalized", firm_vector_dev, "<=1e-10", firm_vector_dev <= 1e-10)
add_check("treated_inventor_vectors_normalized", inv_vector_dev, "<=1e-10", inv_vector_dev <= 1e-10)

expected_pairs <- scalar("
SELECT 3*SUM(t.n*c.n) FROM
 (SELECT cohort,COUNT(DISTINCT deal_id) n FROM lmv2_treated_primary GROUP BY cohort)t
 JOIN (SELECT cohort,COUNT(*) n FROM lmv2_control_firm_eligibility GROUP BY cohort)c USING(cohort)")
observed_pairs <- scalar("SELECT COUNT(*) FROM lmv2_p3_stage1_similarity")
add_check("all_stage1_pairs_all_resolutions", observed_pairs, expected_pairs,
          observed_pairs == expected_pairs)
pair_resolution_bad <- scalar("
SELECT COUNT(*) FROM (
 SELECT cohort,deal_id,target_group,control_group,COUNT(*) n
 FROM lmv2_p3_stage1_similarity GROUP BY 1,2,3,4 HAVING n<>3)")
add_check("each_stage1_pair_has_three_resolutions", pair_resolution_bad, 0,
          pair_resolution_bad == 0)
cosine_bad <- scalar("SELECT COUNT(*) FROM lmv2_p3_stage1_similarity WHERE cosine<0 OR cosine>1")
add_check("stage1_cosines_bounded", cosine_bad, 0, cosine_bad == 0)
edge_count <- scalar("SELECT COUNT(*) FROM lmv2_p3_stage1_edges")
expected_edge_count <- scalar("
SELECT COUNT(*) FROM lmv2_p3_stage1_similarity WHERE resolution='ipc4'")
add_check("stage1_edges_cover_locked_ipc4_matrix_only", edge_count, expected_edge_count,
          edge_count == expected_edge_count)
edge_resolution_bad <- scalar("
SELECT COUNT(*) FROM lmv2_p3_stage1_edges WHERE resolution<>'ipc4'")
add_check("stage1_edges_are_locked_to_ipc4", edge_resolution_bad, 0,
          edge_resolution_bad == 0)

scale_bad <- scalar("
WITH direct AS (
 SELECT cohort,resolution,STDDEV_SAMP(1-cosine) sd
 FROM lmv2_p3_stage1_similarity WHERE cosine IS NOT NULL GROUP BY cohort,resolution
)
SELECT COUNT(*) FROM direct d JOIN lmv2_p3_stage1_scalers s USING(cohort,resolution)
WHERE s.component='tech_distance' AND ABS(d.sd-s.component_sd)>1e-12")
add_check("cosine_sd_uses_all_within_cohort_pairs", scale_bad, 0, scale_bad == 0)

diagnostics <- DBI::dbGetQuery(con, "
SELECT cohort,resolution,COUNT(*) candidate_pairs,
       AVG((cosine>0)::INTEGER) positive_cosine_share,
       AVG((cosine=0)::INTEGER) zero_cosine_share,
       COUNT(DISTINCT ROUND(cosine,8)) distinct_similarity_values,
       SUM((cosine IS NULL)::INTEGER) missing_vector_pairs
FROM lmv2_p3_stage1_similarity GROUP BY cohort,resolution ORDER BY cohort,resolution")
utils::write.csv(diagnostics, file.path(LMV2_P3_PATHS$audit, "p3_stage1_ipc_diagnostics.csv"),
                 row.names = FALSE, na = "")
vector_support <- DBI::dbGetQuery(con, "
WITH ipc4_vectors AS (
  SELECT DISTINCT cohort,id_group FROM lmv2_p3_firm_ipc_vectors
  WHERE resolution='ipc4'
), deal_pool AS (
  SELECT s.cohort,s.deal_id,s.target_group,
         COUNT(DISTINCT s.control_group) AS candidate_control_firms,
         COUNT(DISTINCT CASE WHEN cv.id_group IS NOT NULL THEN s.control_group END)
           AS control_firms_with_ipc4_vector,
         COUNT(*) FILTER (WHERE s.cosine IS NOT NULL) AS admissible_ipc4_pairs,
         COUNT(*) FILTER (WHERE s.cosine IS NULL) AS missing_vector_pairs,
         MAX((tv.id_group IS NOT NULL)::INTEGER) AS target_has_ipc4_vector
  FROM lmv2_p3_stage1_similarity s
  LEFT JOIN ipc4_vectors tv ON tv.cohort=s.cohort AND tv.id_group=s.target_group
  LEFT JOIN ipc4_vectors cv ON cv.cohort=s.cohort AND cv.id_group=s.control_group
  WHERE s.resolution='ipc4'
  GROUP BY s.cohort,s.deal_id,s.target_group
)
SELECT * FROM deal_pool ORDER BY cohort,deal_id")
utils::write.csv(vector_support,
                 file.path(LMV2_P3_PATHS$audit, "p3_stage1_vector_support_by_deal.csv"),
                 row.names = FALSE, na = "")
expected_stage1_deals <- scalar("SELECT COUNT(DISTINCT deal_id) FROM lmv2_treated_primary")
add_check("stage1_vector_support_census_covers_every_deal",
          nrow(vector_support), expected_stage1_deals,
          nrow(vector_support)==expected_stage1_deals)
scalers <- DBI::dbGetQuery(con, "SELECT * FROM lmv2_p3_stage1_scalers ORDER BY cohort,resolution,component")
utils::write.csv(scalers, file.path(LMV2_P3_PATHS$audit, "p3_within_cohort_scalers.csv"),
                 row.names = FALSE, na = "")

# Pure engine fixtures: distance, total-distance caliper, deterministic ties,
# two-firm repair, explicit unsupported outcome, and reuse counts.
trajectory_fixture <- log1p(4/2)-log1p(3/3)
add_check("trajectory_hand_fixture", trajectory_fixture, log(3)-log(2),
          isTRUE(all.equal(trajectory_fixture, log(3)-log(2), tolerance = 1e-15)))
sd0 <- lmv2_safe_sd(c(1,1,1))
add_check("near_zero_sd_contributes_zero", paste(sd0$degenerate, lmv2_scale_gap(5, sd0$sd)),
          "TRUE 0", isTRUE(sd0$degenerate) && identical(lmv2_scale_gap(5, sd0$sd), 0))
boundary <- lmv2_apply_total_caliper(c(1,1+1e-9), 1)
add_check("total_distance_caliper_boundary", paste(boundary, collapse = ","), "TRUE,FALSE",
          identical(boundary, c(TRUE,FALSE)))

s1 <- data.frame(cohort=2000L,deal_id=1L,control_group=6:1,
                 distance=c(1,1,0.5,0.4,0.3,0.2),resolution="ipc4")
s1 <- rbind(s1, transform(s1, resolution="ipc_main_group", distance=0))
s1m <- lmv2_select_stage1(s1, Inf, 5L)
add_check("stage1_deterministic_top_five", paste(s1m$control_group,collapse=","), "1,2,3,4,5",
          identical(s1m$control_group, 1:5))
add_check("stage1_selector_ignores_diagnostic_resolutions",
          paste(unique(s1m$resolution),collapse=","), "ipc4",
          identical(unique(s1m$resolution), "ipc4"))
stage1_no_ipc4 <- data.frame(
  cohort=2000L,deal_id=2L,control_group=1:5,distance=0,resolution="ipc_main_group"
)
stage1_missing <- lmv2_select_stage1(stage1_no_ipc4, Inf, 5L)
stage1_missing_attr <- attr(stage1_missing, "unsupported")
add_check("stage1_missing_ipc4_is_counted_unsupported",
          nrow(stage1_missing_attr), 1,
          nrow(stage1_missing)==0 && nrow(stage1_missing_attr)==1)

s2 <- data.frame(
  cohort=2000L,deal_id=1L,treated_codinv=10L,
  control_codinv=101:104,control_group=c(1,1,1,2),distance=c(.1,.2,.3,.4)
)
s2m <- lmv2_select_stage2(s2, Inf)
add_check("stage2_minimum_distance_two_firm_repair",
          paste(s2m$control_codinv,collapse=","), "101,102,104",
          identical(s2m$control_codinv, c(101L,102L,104L)))
add_check("stage2_equal_weights", sum(s2m$weight), 1, abs(sum(s2m$weight)-1)<1e-15)
unsupported <- lmv2_select_stage2(s2[s2$control_group==1,], Inf)
add_check("stage2_no_second_firm_is_unsupported", nrow(unsupported), 0, nrow(unsupported)==0)
unsupported_attr <- attr(unsupported, "unsupported")
add_check("stage2_unsupported_reason_is_returned",
          unsupported_attr$reason[1], "no_second_eligible_control_firm",
          nrow(unsupported_attr)==1 &&
            identical(unsupported_attr$reason[1], "no_second_eligible_control_firm"))
reuse <- lmv2_control_reuse_counts(rbind(s2m,s2m))
add_check("reuse_counter_interface", max(reuse$reuse_count), 2, max(reuse$reuse_count)==2)

# Stage-2 scalar SDs use unit observations before pair-level IPC/recency filters.
stage2_vars <- LMV2_P3$stage_2$scalar_variables
t_scale <- data.frame(
  cohort=2000L,deal_id=1L,codinv=10,recency_bin=0,
  log_patent_count_5y=0,patent_trajectory=1,career_age=1,
  focal_group_tenure=1,focal_group_exclusivity=1
)
c_scale <- data.frame(
  cohort=2000L,codinv=c(101,102,103),focal_group=c(1,2,3),recency_bin=c(0,0,3),
  log_patent_count_5y=c(0,0,10),patent_trajectory=1,career_age=1,
  focal_group_tenure=1,focal_group_exclusivity=1
)
p_scale <- data.frame(
  cohort=2000L,deal_id=1L,treated_codinv=10,control_codinv=c(101,102,103)
)
sim_scale <- transform(p_scale,resolution="ipc4",cosine=.5)
shared_scale <- transform(p_scale,shared_ipc4=c(TRUE,TRUE,FALSE))
prepared_scale <- lmv2_prepare_stage2_edges(
  t_scale,c_scale,p_scale,sim_scale,shared_scale,resolution="ipc4"
)
observed_scale <- prepared_scale$scalers$component_sd[
  prepared_scale$scalers$component=="log_patent_count_5y"
]
expected_scale <- stats::sd(c(0,0,0,10))
add_check("stage2_scalar_sd_uses_units_before_pair_filters",
          observed_scale, expected_scale,
          isTRUE(all.equal(observed_scale,expected_scale,tolerance=1e-15)))
add_check("stage2_pair_filter_does_not_drop_scaler_only_unit",
          nrow(prepared_scale$edges), 2, nrow(prepared_scale$edges)==2)

# Runtime interfaces on a tiny real-data fixture.
pair_fixture <- DBI::dbGetQuery(con, "
SELECT t.cohort,t.codinv treated_codinv,c.codinv control_codinv,
       c.focal_group control_group
FROM lmv2_p3_treated_inventor_units t
JOIN lmv2_p3_inventor_general_units c ON c.cohort=t.cohort AND c.role='control'
ORDER BY t.cohort,t.deal_id,t.codinv,c.codinv LIMIT 5")
technology_cache <- lmv2_stage2_technology_cache(con, pair_fixture)
runtime_rows <- table(factor(
  technology_cache$similarity$resolution,
  levels=LMV2_P3$technology$resolutions
))
add_check("three_resolution_inventor_similarity_interface",
          paste(runtime_rows,collapse=","), paste(rep(nrow(pair_fixture),3),collapse=","),
          all(runtime_rows==nrow(pair_fixture)))
add_check("shared_ipc4_cache_is_pair_complete",
          nrow(technology_cache$shared_ipc4), nrow(pair_fixture),
          nrow(technology_cache$shared_ipc4)==nrow(pair_fixture))
ipc_diagnostics <- lmv2_inventor_ipc_diagnostics(
  pair_fixture,technology_cache$similarity
)
add_check("inventor_ipc_diagnostic_interface_covers_three_resolutions",
          paste(sort(unique(ipc_diagnostics$unit$resolution)),collapse=","),
          paste(sort(LMV2_P3$technology$resolutions),collapse=","),
          setequal(ipc_diagnostics$unit$resolution,LMV2_P3$technology$resolutions))

control_fixture <- DBI::dbGetQuery(con, "
SELECT cohort,codinv,focal_group FROM lmv2_p3_inventor_general_units
WHERE role='control' ORDER BY cohort,codinv,focal_group LIMIT 20")
control_focal <- lmv2_build_control_focal_covariates(con, control_fixture)
focal_runtime_ok <- nrow(control_focal)==nrow(control_fixture) &&
  all(!is.na(control_focal$focal_group_tenure)) &&
  all(!is.na(control_focal$focal_group_exclusivity)) &&
  all(control_focal$focal_group_tenure>=1, na.rm=TRUE) &&
  all(control_focal$focal_group_exclusivity>=0 & control_focal$focal_group_exclusivity<=1, na.rm=TRUE)
add_check("on_demand_control_focal_interface", nrow(control_focal), nrow(control_fixture), focal_runtime_ok)

checks_df <- do.call(rbind, checks)
checks_df$p3_version <- LMV2_P3_VERSION
checks_df$p3_config_hash <- LMV2_P3_CONFIG_HASH
checks_df <- checks_df[c("p3_version","p3_config_hash","check","observed","expected","pass")]
utils::write.csv(checks_df, file.path(LMV2_P3_PATHS$audit, "p3_acceptance_checks.csv"),
                 row.names = FALSE, na = "")

status <- data.frame(
  p3_version=LMV2_P3_VERSION,p3_config_hash=LMV2_P3_CONFIG_HASH,
  checks=nrow(checks_df),failures=sum(!checks_df$pass),pass=all(checks_df$pass),
  stringsAsFactors=FALSE
)
utils::write.csv(status,file.path(LMV2_P3_PATHS$audit,"p3_package_status.csv"),row.names=FALSE)
print(status)
if (!status$pass) stop("P3 certification failed; inspect p3_acceptance_checks.csv")

# ============================================================================
# Build PPSCM v2 prepanel, candidate pools, hull census, and abort gate
# ============================================================================
# This stage queries outcomes only for event times -5 through -1.
# It does not estimate optimized synthetic-control weights.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "data.table", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(
  BASE, "R", "39a_lmv2_ppscm_second_attempt_config.R"))
config <- lmv2_ppscm_v2_config()
lmv2_ppscm_assert_freeze(config)
dir.create(config$census_dir, recursive = TRUE, showWarnings = FALSE)

manifest <- utils::read.csv(
  config$units_manifest_path, stringsAsFactors = FALSE)
if (nrow(manifest)!=1L ||
    !isTRUE(as.logical(manifest$certification_pass))) {
  stop("Missing or uncertified symmetric-unit manifest")
}
if (!identical(
    tolower(manifest$units_sha256),
    tolower(lmv2_ppscm_sha256(config$units_path)))) {
  stop("Symmetric-unit parquet hash mismatch")
}

source_path <- file.path(
  BASE, "R", "39c_build_lmv2_ppscm_prepanel.R")
config_path <- file.path(
  BASE, "R", "39a_lmv2_ppscm_second_attempt_config.R")
source_sha256 <- lmv2_ppscm_sha256(source_path)
config_sha256 <- lmv2_ppscm_sha256(config_path)
freeze_sha256 <- lmv2_ppscm_sha256(config$freeze_path)

con <- DBI::dbConnect(
  duckdb::duckdb(), dbdir = config$db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(
  con, sprintf("PRAGMA threads=%d", config$execution$threads))
DBI::dbExecute(
  con, sprintf("PRAGMA memory_limit='%s'",
               config$execution$memory_limit))

for (tbl in c(
    "group_ipc_year", "inventor_year",
    "patent_company_link", "patent_inventor",
    "deal_target_company_strict", "deal_assignment")) {
  if (!DBI::dbExistsTable(con, tbl)) stop("Missing census input: ", tbl)
}

units_sql <- lmv2_ppscm_sql_string(
  con, normalizePath(config$units_path, winslash = "/", mustWork = TRUE))
invisible(DBI::dbExecute(con, sprintf("
CREATE TEMP VIEW pp2_units AS SELECT * FROM read_parquet(%s)
", units_sql)))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_times AS
SELECT UNNEST(range(-5,0))::INTEGER event_time
"))

message("PPSCM v2 Stage C: aggregate pre-period unit outcomes")
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_unit_panel AS
SELECT u.*,t.event_time,
       COALESCE(y.patent_count,0)::DOUBLE patent_count,
       (COALESCE(y.patent_count,0)>0)::INTEGER active_patenting
FROM pp2_units u CROSS JOIN pp2_times t
LEFT JOIN inventor_year y
  ON y.codinv=u.codinv AND y.year=u.cohort+t.event_time
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_treated_path AS
SELECT cohort,deal_id,focal_group,event_time,
       AVG(patent_count)::DOUBLE treated_outcome,
       AVG(active_patenting)::DOUBLE treated_active_share,
       COUNT(DISTINCT codinv)::INTEGER n_treated
FROM pp2_unit_panel WHERE arm='treated'
GROUP BY cohort,deal_id,focal_group,event_time
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_donor_path AS
SELECT cohort,focal_group donor_group,event_time,
       AVG(patent_count)::DOUBLE donor_outcome,
       AVG(active_patenting)::DOUBLE donor_active_share,
       COUNT(DISTINCT codinv)::INTEGER n_donor_inventors
FROM pp2_unit_panel WHERE arm='control'
GROUP BY cohort,focal_group,event_time
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_fixed_career AS
SELECT u.cohort,u.arm,u.deal_id,u.focal_group,
       AVG(u.cohort-4-y.career_first_year)::DOUBLE mean_career_age_m4,
       MEDIAN(u.cohort-4-y.career_first_year)::DOUBLE median_career_age_m4
FROM pp2_units u
JOIN inventor_year y
  ON CAST(y.codinv AS BIGINT)=u.codinv
 AND y.year=u.landmark_affiliation_year
GROUP BY u.cohort,u.arm,u.deal_id,u.focal_group
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_feature_group_years AS
SELECT DISTINCT cohort,focal_group id_group,cohort-5 feature_year
FROM pp2_units
UNION
SELECT DISTINCT cohort,focal_group id_group,cohort-4 feature_year
FROM pp2_units
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_group_year_inventors AS
SELECT f.cohort,f.id_group,f.feature_year,
       COUNT(DISTINCT CAST(pi.codinv AS BIGINT)) inventor_count
FROM pp2_feature_group_years f
JOIN patent_company_link pcl
  ON CAST(pcl.id_group AS BIGINT)=f.id_group
 AND pcl.year=f.feature_year
JOIN patent_inventor pi USING(appln_id)
GROUP BY f.cohort,f.id_group,f.feature_year
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_group_year_patents AS
SELECT f.cohort,f.id_group,f.feature_year,
       COUNT(DISTINCT pcl.appln_id) patent_count
FROM pp2_feature_group_years f
JOIN patent_company_link pcl
  ON CAST(pcl.id_group AS BIGINT)=f.id_group
 AND pcl.year=f.feature_year
GROUP BY f.cohort,f.id_group,f.feature_year
"))

message("PPSCM v2 Stage C: construct firm screening features")
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_firm_roster AS
SELECT DISTINCT cohort,arm,deal_id,focal_group
FROM pp2_units
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_firm_features AS
WITH paths AS (
  SELECT cohort,'treated' arm,deal_id,focal_group,
    MAX(treated_outcome) FILTER (WHERE event_time=-5) mean_patent_m5,
    MAX(treated_outcome) FILTER (WHERE event_time=-4) mean_patent_m4,
    MAX(treated_active_share) FILTER (WHERE event_time=-5) active_share_m5,
    MAX(treated_active_share) FILTER (WHERE event_time=-4) active_share_m4
  FROM pp2_treated_path
  GROUP BY cohort,deal_id,focal_group
  UNION ALL
  SELECT cohort,'control' arm,NULL::BIGINT,donor_group,
    MAX(donor_outcome) FILTER (WHERE event_time=-5),
    MAX(donor_outcome) FILTER (WHERE event_time=-4),
    MAX(donor_active_share) FILTER (WHERE event_time=-5),
    MAX(donor_active_share) FILTER (WHERE event_time=-4)
  FROM pp2_donor_path
  GROUP BY cohort,donor_group
)
SELECT p.*,LN(1+p.mean_patent_m5) log1p_mean_patent_m5,
       LN(1+p.mean_patent_m4) log1p_mean_patent_m4,
       LN(1+COALESCE(gp5.patent_count,0)) log_firm_patent_m5,
       LN(1+COALESCE(gp4.patent_count,0)) log_firm_patent_m4,
       LN(1+COALESCE(gi5.inventor_count,0)) log_firm_inventors_m5,
       LN(1+COALESCE(gi4.inventor_count,0)) log_firm_inventors_m4,
       c.mean_career_age_m4,c.median_career_age_m4
FROM paths p
LEFT JOIN pp2_group_year_patents gp5
  ON gp5.cohort=p.cohort AND gp5.id_group=p.focal_group
 AND gp5.feature_year=p.cohort-5
LEFT JOIN pp2_group_year_patents gp4
  ON gp4.cohort=p.cohort AND gp4.id_group=p.focal_group
 AND gp4.feature_year=p.cohort-4
LEFT JOIN pp2_group_year_inventors gi5
  ON gi5.cohort=p.cohort AND gi5.id_group=p.focal_group
 AND gi5.feature_year=p.cohort-5
LEFT JOIN pp2_group_year_inventors gi4
  ON gi4.cohort=p.cohort AND gi4.id_group=p.focal_group
 AND gi4.feature_year=p.cohort-4
LEFT JOIN pp2_fixed_career c
  ON c.cohort=p.cohort AND c.arm=p.arm
 AND c.deal_id IS NOT DISTINCT FROM p.deal_id
 AND c.focal_group=p.focal_group
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_firm_ipc AS
WITH weighted AS (
 SELECT r.cohort,r.arm,r.deal_id,r.focal_group,
        SUBSTR(g.ipc_code,1,4) ipc_feature,
        SUM(g.patent_count)::DOUBLE weight
 FROM pp2_firm_roster r
 JOIN group_ipc_year g
   ON CAST(g.id_group AS BIGINT)=r.focal_group
  AND g.year BETWEEN r.cohort-7 AND r.cohort-4
 WHERE g.ipc_code IS NOT NULL AND LENGTH(g.ipc_code)>=4
 GROUP BY r.cohort,r.arm,r.deal_id,r.focal_group,
          SUBSTR(g.ipc_code,1,4)
)
SELECT *,weight/SUM(weight) OVER
 (PARTITION BY cohort,arm,deal_id,focal_group) frequency
FROM weighted
"))
invisible(DBI::dbExecute(con, "
CREATE TEMP TABLE pp2_firm_cosine AS
WITH norms AS (
 SELECT cohort,arm,deal_id,focal_group,
        SQRT(SUM(frequency*frequency)) norm
 FROM pp2_firm_ipc
 GROUP BY cohort,arm,deal_id,focal_group
), pairs AS (
 SELECT t.cohort,t.deal_id,t.focal_group treated_group,
        c.focal_group donor_group,t.norm treated_norm,c.norm donor_norm
 FROM norms t
 JOIN norms c ON c.cohort=t.cohort AND c.arm='control'
 WHERE t.arm='treated' AND t.norm>0 AND c.norm>0
), numer AS (
 SELECT p.cohort,p.deal_id,p.treated_group,p.donor_group,
        SUM(t.frequency*c.frequency) numerator
 FROM pairs p
 JOIN pp2_firm_ipc t
   ON t.cohort=p.cohort AND t.arm='treated'
  AND t.deal_id=p.deal_id AND t.focal_group=p.treated_group
 JOIN pp2_firm_ipc c
   ON c.cohort=p.cohort AND c.arm='control'
  AND c.focal_group=p.donor_group
  AND c.ipc_feature=t.ipc_feature
 GROUP BY p.cohort,p.deal_id,p.treated_group,p.donor_group
)
SELECT p.cohort,p.deal_id,p.treated_group,p.donor_group,
       COALESCE(n.numerator,0)::DOUBLE numerator,
       COALESCE(n.numerator,0)/
         NULLIF(p.treated_norm*p.donor_norm,0) cosine
FROM pairs p
LEFT JOIN numer n USING(cohort,deal_id,treated_group,donor_group)
"))

features <- data.table::as.data.table(DBI::dbGetQuery(
  con, "SELECT * FROM pp2_firm_features"))
scalar_vars <- c(
  "log1p_mean_patent_m5", "log1p_mean_patent_m4",
  "active_share_m5", "active_share_m4",
  "log_firm_patent_m5", "log_firm_patent_m4",
  "log_firm_inventors_m5", "log_firm_inventors_m4",
  "mean_career_age_m4", "median_career_age_m4")
if (!nrow(features) ||
    any(!is.finite(as.matrix(features[, ..scalar_vars])))) {
  stop("Firm screening features are empty or non-finite")
}
distance_scalers <- data.table::rbindlist(lapply(
  sort(unique(features$cohort)), function(g) {
    block <- features[cohort==g]
    data.table::data.table(
      cohort=g,feature=scalar_vars,
      center=vapply(scalar_vars,function(v) mean(block[[v]]),numeric(1)),
      scale=vapply(scalar_vars,function(v) {
        s <- stats::sd(block[[v]])
        if (!is.finite(s) || s<1e-10) 0 else s
      },numeric(1)))
  }))
for (v in scalar_vars) {
  features[, paste0("z_",v) := {
    s <- stats::sd(get(v))
    m <- mean(get(v))
    if (!is.finite(s) || s<1e-10) rep(0,.N) else (get(v)-m)/s
  }, by=cohort]
}
cosine <- data.table::as.data.table(DBI::dbGetQuery(
  con, "SELECT * FROM pp2_firm_cosine"))
treated_features <- features[
  arm=="treated",
  c("cohort","deal_id","focal_group",paste0("z_",scalar_vars)),
  with=FALSE]
data.table::setnames(
  treated_features,
  c("focal_group",paste0("z_",scalar_vars)),
  c("treated_group",paste0("t_",scalar_vars)))
donor_features <- features[
  arm=="control",
  c("cohort","focal_group",paste0("z_",scalar_vars)),
  with=FALSE]
data.table::setnames(
  donor_features,
  c("focal_group",paste0("z_",scalar_vars)),
  c("donor_group",paste0("c_",scalar_vars)))
edges <- merge(
  cosine,treated_features,
  by=c("cohort","deal_id","treated_group"),sort=FALSE)
edges <- merge(
  edges,donor_features,
  by=c("cohort","donor_group"),sort=FALSE)
if (!nrow(edges)) stop("No donor edges have valid screening features")
delta_vars <- paste0("delta_",scalar_vars)
for (i in seq_along(scalar_vars)) {
  v <- scalar_vars[[i]]
  edges[, (delta_vars[[i]]) :=
    get(paste0("t_",v))-get(paste0("c_",v))]
}
edges[,distance_component_technology:=1-cosine]
edges[,distance:=sqrt(
  rowSums(as.matrix(.SD)^2)+distance_component_technology^2),
  .SDcols=delta_vars]
data.table::setorder(edges,cohort,deal_id,distance,donor_group)
availability <- edges[,.(available_donor_firms=.N),by=.(cohort,deal_id)]
selected <- edges[,head(.SD,config$donor_pool_cap),
                  by=.(cohort,deal_id)]
selected[,donor_rank:=seq_len(.N),by=.(cohort,deal_id)]
selected_counts <- selected[,.(selected_donor_firms=.N),
                            by=.(cohort,deal_id)]
availability <- merge(
  availability,selected_counts,by=c("cohort","deal_id"),all=TRUE)
availability[is.na(selected_donor_firms),selected_donor_firms:=0L]

message("PPSCM v2 Stage C: construct hull and uniform-gap census")
treated_path <- data.table::as.data.table(DBI::dbGetQuery(
  con, "SELECT * FROM pp2_treated_path"))
donor_path <- data.table::as.data.table(DBI::dbGetQuery(
  con, "SELECT * FROM pp2_donor_path"))
candidate_panel <- merge(
  selected[,.(cohort,deal_id,treated_group,donor_group,
              donor_rank,distance,cosine)],
  donor_path,by=c("cohort","donor_group"),sort=FALSE)
candidate_panel <- merge(
  candidate_panel,treated_path,
  by.x=c("cohort","deal_id","treated_group","event_time"),
  by.y=c("cohort","deal_id","focal_group","event_time"),
  sort=FALSE)
candidate_panel[,`:=`(
  treated_log1p=log1p(treated_outcome),
  donor_log1p=log1p(donor_outcome))]
candidate_panel_all <- data.table::copy(candidate_panel)
hull <- candidate_panel[event_time%in%config$screening_times,.(
  treated_log1p=unique(treated_log1p),
  donor_min_log1p=min(donor_log1p),
  donor_max_log1p=max(donor_log1p),
  donor_range_log1p=max(donor_log1p)-min(donor_log1p)),
  by=.(cohort,deal_id,event_time)]
hull[,`:=`(
  lower_gap=treated_log1p-donor_min_log1p,
  upper_gap=donor_max_log1p-treated_log1p)]
hull[,inside_hull:=
       lower_gap>=-1e-12 & upper_gap>=-1e-12]
hull[,zero_range:=donor_range_log1p<=1e-12]
hull[,boundary_distance_log1p:=pmin(lower_gap,upper_gap)]
hull[,boundary_distance_share:=ifelse(
  donor_range_log1p>1e-12,
  boundary_distance_log1p/donor_range_log1p,
  NA_real_)]
hull_deals <- hull[,.(two_period_hull_support=
  .N==length(config$screening_times) && all(inside_hull)),
  by=.(cohort,deal_id)]
support_deals <- merge(
  availability[selected_donor_firms>=config$minimum_donor_firms],
  hull_deals[two_period_hull_support==TRUE],
  by=c("cohort","deal_id"))
candidate_panel <- merge(
  candidate_panel,
  support_deals[,.(cohort,deal_id,selected_donor_firms)],
  by=c("cohort","deal_id"))

DBI::dbWriteTable(
  con,"pp2_support_deals",
  as.data.frame(support_deals[,.(cohort,deal_id)]),
  temporary=TRUE,overwrite=TRUE)
attachment_by_inventor <- data.table::as.data.table(DBI::dbGetQuery(con, "
WITH retained AS (
  SELECT u.cohort,u.deal_id,u.codinv
  FROM pp2_units u
  JOIN pp2_support_deals s USING(cohort,deal_id)
  WHERE u.arm='treated'
), attached AS (
  SELECT DISTINCT r.cohort,r.deal_id,r.codinv
  FROM retained r
  JOIN deal_target_company_strict dtc USING(deal_id)
  JOIN patent_company_link pcl
    ON CAST(pcl.compcod AS BIGINT)=dtc.target_compcod
   AND pcl.year BETWEEN r.cohort-5 AND r.cohort-1
  JOIN patent_inventor pi
    ON pi.appln_id=pcl.appln_id
   AND CAST(pi.codinv AS BIGINT)=r.codinv
)
SELECT r.cohort,r.deal_id,r.codinv,
       (a.codinv IS NOT NULL) attached_target_m5_m1
FROM retained r
LEFT JOIN attached a USING(cohort,deal_id,codinv)
ORDER BY r.cohort,r.deal_id,r.codinv
"))
attachment_summary <- attachment_by_inventor[, .(
  retained_treated_inventors=.N,
  attached_treated_inventors=sum(attached_target_m5_m1),
  attachment_share=mean(attached_target_m5_m1))]
attachment_by_cohort <- attachment_by_inventor[, .(
  retained_treated_inventors=.N,
  attached_treated_inventors=sum(attached_target_m5_m1),
  attachment_share=mean(attached_target_m5_m1)),by=cohort]

deal_info <- unique(candidate_panel[,.(cohort,deal_id,n_treated)])
eligible_treated <- as.numeric(manifest$treated_inventors)
retained_treated <- sum(deal_info$n_treated)
treated_coverage <- retained_treated/eligible_treated

uniform_deal <- candidate_panel[, .(
  treated_outcome=unique(treated_outcome),
  synthetic_outcome=mean(donor_outcome),
  treated_log1p=unique(treated_log1p),
  synthetic_log1p=mean(donor_log1p),
  n_treated=unique(n_treated)),
  by=.(cohort,deal_id,event_time)]
uniform_deal[,`:=`(
  raw_gap=treated_outcome-synthetic_outcome,
  log1p_gap=treated_log1p-synthetic_log1p)]
uniform_deal[,deal_weight:=n_treated/sum(n_treated),by=event_time]
uniform_pooled <- uniform_deal[, .(
  treated_outcome=sum(deal_weight*treated_outcome),
  synthetic_outcome=sum(deal_weight*synthetic_outcome),
  raw_gap=sum(deal_weight*raw_gap),
  treated_log1p=sum(deal_weight*treated_log1p),
  synthetic_log1p=sum(deal_weight*synthetic_log1p),
  log1p_gap=sum(deal_weight*log1p_gap)),
  by=event_time]
validation_uniform <- uniform_pooled[
  event_time%in%config$validation_times]
uniform_rmse <- sqrt(mean(validation_uniform$raw_gap^2))
uniform_max_abs_gap <- max(abs(validation_uniform$raw_gap))

candidate_panel[,retained_hull_support:=TRUE]
selected[,retained_hull_support:=
  paste(cohort,deal_id)%in%paste(
    support_deals$cohort,support_deals$deal_id)]
hull_share <- nrow(hull_deals[two_period_hull_support==TRUE])/
  max(as.numeric(manifest$treated_deals),1)
census_gate <- data.frame(
  gate=c(
    "minimum_retained_deals","minimum_treated_coverage",
    "minimum_donor_firms_per_retained_deal",
    "uniform_validation_rmse_at_most_0_10",
    "uniform_max_abs_gap_at_most_0_10"),
  value=c(
    nrow(deal_info),treated_coverage,
    if(nrow(support_deals)) min(support_deals$selected_donor_firms) else 0,
    uniform_rmse,uniform_max_abs_gap),
  threshold=c(
    paste0(">=",config$minimum_retained_deals),
    paste0(">=",config$minimum_treated_coverage),
    paste0(">=",config$minimum_donor_firms),
    paste0("<=",config$census_abort_rmse),
    paste0("<=",config$census_abort_max_abs_gap)),
  pass=c(
    nrow(deal_info)>=config$minimum_retained_deals,
    treated_coverage>=config$minimum_treated_coverage,
    nrow(support_deals)>0 &&
      min(support_deals$selected_donor_firms)>=config$minimum_donor_firms,
    is.finite(uniform_rmse) &&
      uniform_rmse<=config$census_abort_rmse,
    is.finite(uniform_max_abs_gap) &&
      uniform_max_abs_gap<=config$census_abort_max_abs_gap),
  stringsAsFactors=FALSE)
census_pass <- all(census_gate$pass)

census_summary <- data.frame(
  eligible_landmark_treated_inventors=eligible_treated,
  retained_treated_inventors=retained_treated,
  treated_coverage=treated_coverage,
  eligible_landmark_deals=as.numeric(manifest$treated_deals),
  deals_with_any_technology_overlap=nrow(availability),
  deals_with_two_period_hull_support=
    nrow(hull_deals[two_period_hull_support==TRUE]),
  hull_support_share=hull_share,
  retained_deals=nrow(deal_info),
  attempt1_treated_inventors=config$attempt1_treated_inventors,
  attempt1_treated_deals=config$attempt1_treated_deals,
  p5c_supported_treated_inventors=
    config$p5c_supported_treated_inventors,
  uniform_validation_rmse=uniform_rmse,
  uniform_validation_max_abs_gap=uniform_max_abs_gap,
  attached_treated_inventors=
    attachment_summary$attached_treated_inventors,
  treated_attachment_share=attachment_summary$attachment_share,
  census_pass=census_pass)

eligible_by_cohort <- data.table::as.data.table(DBI::dbGetQuery(con, "
SELECT cohort,COUNT(DISTINCT deal_id) eligible_deals,
       COUNT(*) eligible_treated_inventors
FROM pp2_units WHERE arm='treated'
GROUP BY cohort ORDER BY cohort
"))
retained_by_cohort <- deal_info[, .(
  retained_deals=.N,
  retained_treated_inventors=sum(n_treated)),by=cohort]
counts_by_cohort <- merge(
  eligible_by_cohort,retained_by_cohort,by="cohort",all.x=TRUE)
counts_by_cohort[
  is.na(retained_deals),
  `:=`(retained_deals=0L,retained_treated_inventors=0)]
sample_flow <- data.frame(
  stage=c(
    "eligible_symmetric_landmark","valid_technology_and_candidate_edges",
    "at_least_five_selected_donors","two_period_hull_support",
    "retained_census_sample"),
  grain="treated_deal",
  count=c(
    as.numeric(manifest$treated_deals),nrow(availability),
    nrow(availability[selected_donor_firms>=config$minimum_donor_firms]),
    nrow(hull_deals[two_period_hull_support==TRUE]),nrow(deal_info)),
  stringsAsFactors=FALSE)

eligible_deal_info <- unique(treated_path[,.(cohort,deal_id,n_treated)])
hull_exclusion_deals <- merge(
  eligible_deal_info,hull_deals,by=c("cohort","deal_id"),all.x=TRUE)
hull_exclusion_deals[
  is.na(two_period_hull_support),two_period_hull_support:=FALSE]
hull_exclusion_deals <- hull_exclusion_deals[
  two_period_hull_support==FALSE][order(-n_treated,cohort,deal_id)]
deal69_hull <- hull[deal_id==69]
deal69_meta <- data.table::as.data.table(DBI::dbGetQuery(con, "
SELECT CAST(deal_id AS BIGINT) deal_id,
       CAST(target_year AS INTEGER) cohort,
       CAST(target_group AS BIGINT) target_group,
       CAST(acquirer_group AS BIGINT) acquirer_group,
       target_value,big_deal,target,acquirer
FROM deal_assignment WHERE deal_id=69
"))
deal69_characteristics <- merge(
  deal69_meta,eligible_deal_info[deal_id==69],
  by=c("cohort","deal_id"),all=TRUE)
if (nrow(deal69_characteristics)) {
  deal69_characteristics[,`:=`(
    retained_primary=FALSE,
    hull_fail_event_times=paste(
      deal69_hull[inside_hull==FALSE]$event_time,collapse=";"),
    minimum_boundary_distance_log1p=
      if(nrow(deal69_hull)) min(deal69_hull$boundary_distance_log1p) else NA_real_)]
}

data.table::setorder(availability,cohort,deal_id)
data.table::setorder(hull,cohort,deal_id,event_time)
data.table::setorder(uniform_deal,cohort,deal_id,event_time)
data.table::setorder(uniform_pooled,event_time)
data.table::setorder(distance_scalers,cohort,feature)
data.table::setorder(counts_by_cohort,cohort)
data.table::setorder(attachment_by_cohort,cohort)
lmv2_ppscm_atomic_csv(
  availability,file.path(config$census_dir,"pool_availability.csv"))
lmv2_ppscm_atomic_csv(
  hull,file.path(config$census_dir,"hull_support.csv"))
lmv2_ppscm_atomic_csv(
  uniform_deal,file.path(config$census_dir,"uniform_deal_paths.csv"))
lmv2_ppscm_atomic_csv(
  uniform_pooled,file.path(config$census_dir,"uniform_pooled_paths.csv"))
lmv2_ppscm_atomic_csv(
  census_summary,file.path(config$census_dir,"census_summary.csv"))
lmv2_ppscm_atomic_csv(
  census_gate,file.path(config$census_dir,"census_gate.csv"))
lmv2_ppscm_atomic_csv(
  distance_scalers,file.path(config$census_dir,"distance_scalers.csv"))
lmv2_ppscm_atomic_csv(
  counts_by_cohort,file.path(config$census_dir,"counts_by_cohort.csv"))
lmv2_ppscm_atomic_csv(
  sample_flow,file.path(config$census_dir,"sample_flow.csv"))
lmv2_ppscm_atomic_csv(
  attachment_summary,
  file.path(config$census_dir,"attachment_summary.csv"))
lmv2_ppscm_atomic_csv(
  attachment_by_cohort,
  file.path(config$census_dir,"attachment_by_cohort.csv"))
lmv2_ppscm_atomic_csv(
  hull_exclusion_deals,
  file.path(config$census_dir,"hull_exclusion_deals.csv"))
lmv2_ppscm_atomic_csv(
  deal69_characteristics,
  file.path(config$census_dir,"deal69_characteristics.csv"))

DBI::dbWriteTable(
  con,"pp2_features_out",as.data.frame(features),
  temporary=TRUE,overwrite=TRUE)
DBI::dbWriteTable(
  con,"pp2_selected_out",as.data.frame(selected),
  temporary=TRUE,overwrite=TRUE)
DBI::dbWriteTable(
  con,"pp2_edges_out",as.data.frame(edges),
  temporary=TRUE,overwrite=TRUE)
DBI::dbWriteTable(
  con,"pp2_prepanel_out",as.data.frame(candidate_panel),
  temporary=TRUE,overwrite=TRUE)
DBI::dbWriteTable(
  con,"pp2_prepanel_all_out",as.data.frame(candidate_panel_all),
  temporary=TRUE,overwrite=TRUE)
DBI::dbWriteTable(
  con,"pp2_treated_path_out",as.data.frame(treated_path),
  temporary=TRUE,overwrite=TRUE)
DBI::dbWriteTable(
  con,"pp2_donor_path_out",as.data.frame(donor_path),
  temporary=TRUE,overwrite=TRUE)
features_path <- file.path(
  config$census_dir,"firm_screening_features.parquet")
pools_path <- file.path(
  config$census_dir,"candidate_donor_pools.parquet")
edges_path <- file.path(
  config$census_dir,"eligible_candidate_edges.parquet")
prepanel_path <- file.path(
  config$census_dir,"ppscm_prepanel.parquet")
prepanel_all_path <- file.path(
  config$census_dir,"ppscm_prepanel_all_top20.parquet")
treated_path_file <- file.path(
  config$census_dir,"treated_preperiod_paths.parquet")
donor_path_file <- file.path(
  config$census_dir,"donor_preperiod_paths.parquet")
lmv2_ppscm_atomic_copy(
  con,"SELECT * FROM pp2_features_out ORDER BY cohort,arm,deal_id,focal_group",
  features_path)
lmv2_ppscm_atomic_copy(
  con,"SELECT * FROM pp2_selected_out ORDER BY cohort,deal_id,donor_rank",
  pools_path)
lmv2_ppscm_atomic_copy(
  con,"SELECT * FROM pp2_edges_out ORDER BY cohort,deal_id,distance,donor_group",
  edges_path)
lmv2_ppscm_atomic_copy(
  con,"SELECT * FROM pp2_prepanel_out ORDER BY cohort,deal_id,donor_rank,event_time",
  prepanel_path)
lmv2_ppscm_atomic_copy(
  con,"SELECT * FROM pp2_prepanel_all_out ORDER BY cohort,deal_id,donor_rank,event_time",
  prepanel_all_path)
lmv2_ppscm_atomic_copy(
  con,"SELECT * FROM pp2_treated_path_out ORDER BY cohort,deal_id,event_time",
  treated_path_file)
lmv2_ppscm_atomic_copy(
  con,"SELECT * FROM pp2_donor_path_out ORDER BY cohort,donor_group,event_time",
  donor_path_file)

census_manifest <- data.frame(
  version=config$version,
  source_sha256=source_sha256,
  config_sha256=config_sha256,
  freeze_sha256=freeze_sha256,
  units_sha256=manifest$units_sha256,
  candidate_pools_sha256=lmv2_ppscm_sha256(pools_path),
  eligible_edges_sha256=lmv2_ppscm_sha256(edges_path),
  prepanel_sha256=lmv2_ppscm_sha256(prepanel_path),
  all_top20_prepanel_sha256=lmv2_ppscm_sha256(prepanel_all_path),
  treated_paths_sha256=lmv2_ppscm_sha256(treated_path_file),
  donor_paths_sha256=lmv2_ppscm_sha256(donor_path_file),
  minimum_outcome_event_time=min(config$pre_times),
  maximum_outcome_event_time=max(config$pre_times),
  optimized_weights_estimated=FALSE,
  post_outcomes_queried=FALSE,
  status=if (census_pass) "CERTIFIED_TO_VALIDATE" else "CENSUS_ABORT",
  failure_reasons=if (census_pass) "" else paste(
    census_gate$gate[!census_gate$pass],collapse=";"),
  census_pass=census_pass,
  stringsAsFactors=FALSE)
lmv2_ppscm_atomic_csv(
  census_manifest,file.path(config$census_dir,"census_manifest.csv"))

artifact_paths <- c(
  units=config$units_path,
  pool_availability=file.path(config$census_dir,"pool_availability.csv"),
  hull_support=file.path(config$census_dir,"hull_support.csv"),
  uniform_deal_paths=file.path(config$census_dir,"uniform_deal_paths.csv"),
  uniform_pooled_paths=file.path(config$census_dir,"uniform_pooled_paths.csv"),
  distance_scalers=file.path(config$census_dir,"distance_scalers.csv"),
  counts_by_cohort=file.path(config$census_dir,"counts_by_cohort.csv"),
  sample_flow=file.path(config$census_dir,"sample_flow.csv"),
  attachment_summary=file.path(
    config$census_dir,"attachment_summary.csv"),
  attachment_by_cohort=file.path(
    config$census_dir,"attachment_by_cohort.csv"),
  hull_exclusion_deals=file.path(
    config$census_dir,"hull_exclusion_deals.csv"),
  deal69_characteristics=file.path(
    config$census_dir,"deal69_characteristics.csv"),
  eligible_candidate_edges=edges_path,
  candidate_pools=pools_path,prepanel=prepanel_path,
  all_top20_prepanel=prepanel_all_path,
  treated_preperiod_paths=treated_path_file,
  donor_preperiod_paths=donor_path_file)
artifact_hashes <- data.frame(
  artifact=names(artifact_paths),
  path=unname(artifact_paths),
  sha256=vapply(artifact_paths,lmv2_ppscm_sha256,character(1)),
  stringsAsFactors=FALSE)
lmv2_ppscm_atomic_csv(
  artifact_hashes,file.path(config$census_dir,"artifact_hashes.csv"))

if (!census_pass) {
  lmv2_ppscm_atomic_lines(c(
    "PPSCM v2 stopped at the frozen census gate.",
    paste(
      census_gate$gate[!census_gate$pass],
      "observed",signif(census_gate$value[!census_gate$pass],6),
      "required",census_gate$threshold[!census_gate$pass])),
    file.path(config$census_dir,"CENSUS_ABORTED.txt"))
  message("PPSCM v2 CENSUS FAILED; no optimized weights estimated")
  print(census_gate)
  quit(save="no",status=2L)
}
message(
  "PPSCM v2 CENSUS PASS | deals=",nrow(deal_info),
  " | coverage=",sprintf("%.3f",treated_coverage),
  " | uniform RMSE=",sprintf("%.4f",uniform_rmse),
  " | max |gap|=",sprintf("%.4f",uniform_max_abs_gap))

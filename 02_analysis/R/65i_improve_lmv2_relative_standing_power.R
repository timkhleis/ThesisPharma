# ============================================================================
# 65i_improve_lmv2_relative_standing_power.R
# Exploratory, outcome-blind precision improvements for relative standing:
#   1. separate loss/gain hinges estimated on full support;
#   2. prognostic pre-deal adjustment;
#   3. fractional-patent standing to reduce integer-count ties.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))
source(file.path(BASE, "R", "65a_lmv2_relative_standing_config.R"))

cfg <- LMV2_RELSTAND
out_dir <- file.path(cfg$output_dir, "power_improvement_v2")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
temp_dir <- normalizePath(
  file.path(out_dir, "duckdb_tmp"), winslash = "/", mustWork = FALSE
)
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

strict_path <- file.path(
  cfg$output_dir, "relative_standing_moderators.parquet"
)
fractional_path <- file.path(
  out_dir, "relative_standing_fractional_moderators.parquet"
)
unit_path <- cfg$inputs$vr_unit_analysis

con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = normalizePath(cfg$inputs$database, winslash = "/", mustWork = TRUE),
  read_only = TRUE
)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf("PRAGMA threads=%d", cfg$execution$threads))
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", cfg$execution$memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", DBI::dbQuoteString(con, temp_dir)
))

strict_sql <- DBI::dbQuoteString(
  con, normalizePath(strict_path, winslash = "/", mustWork = TRUE)
)
unit_sql <- DBI::dbQuoteString(
  con, normalizePath(unit_path, winslash = "/", mustWork = TRUE)
)

# Rebuild the same focal-specific pools used by the corrected count measure.
DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE rs_frac_roster AS
SELECT
  deal_id, cohort, arm, codinv, roster_row_id,
  CAST(focal_group_1 AS BIGINT) focal_group,
  CAST(acquirer_group AS BIGINT) acquirer_group,
  focal_inventors, combined_inventors
FROM read_parquet(%s)
WHERE standing_eligibility='eligible'
", strict_sql))
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_frac_focal_cells AS
SELECT DISTINCT deal_id, cohort, arm, focal_group
FROM rs_frac_roster
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_frac_acquirer_cells AS
SELECT DISTINCT deal_id, cohort, acquirer_group
FROM rs_frac_roster
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_frac_focal_patents AS
SELECT DISTINCT
  c.deal_id, c.cohort, c.arm, c.focal_group,
  CAST(pi.codinv AS BIGINT) codinv,
  CAST(pi.appln_id AS BIGINT) appln_id
FROM rs_frac_focal_cells c
JOIN patent_company_link pcl
  ON CAST(pcl.id_group AS BIGINT)=c.focal_group
 AND pcl.year BETWEEN c.cohort-5 AND c.cohort-1
JOIN patent_inventor pi ON pi.appln_id=pcl.appln_id
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_frac_acquirer_patents AS
SELECT DISTINCT
  c.deal_id, c.cohort, CAST(pi.codinv AS BIGINT) codinv,
  CAST(pi.appln_id AS BIGINT) appln_id
FROM rs_frac_acquirer_cells c
JOIN patent_company_link pcl
  ON CAST(pcl.id_group AS BIGINT)=c.acquirer_group
 AND pcl.year BETWEEN c.cohort-5 AND c.cohort-1
JOIN patent_inventor pi ON pi.appln_id=pcl.appln_id
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_frac_team_size AS
WITH relevant AS (
  SELECT DISTINCT appln_id FROM rs_frac_focal_patents
  UNION
  SELECT DISTINCT appln_id FROM rs_frac_acquirer_patents
)
SELECT CAST(pi.appln_id AS BIGINT) appln_id,
       COUNT(DISTINCT pi.codinv) team_size
FROM patent_inventor pi
JOIN relevant r ON r.appln_id=pi.appln_id
GROUP BY 1
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_frac_focal_productivity AS
SELECT
  p.deal_id, p.cohort, p.arm, p.focal_group, p.codinv,
  SUM(1.0/t.team_size) focal_fractional_patents_5y
FROM rs_frac_focal_patents p
JOIN rs_frac_team_size t USING (appln_id)
GROUP BY 1,2,3,4,5
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_frac_combined_productivity AS
WITH pooled AS (
  SELECT deal_id, cohort, arm, focal_group, codinv, appln_id
  FROM rs_frac_focal_patents
  UNION
  SELECT a.deal_id, a.cohort, f.arm, f.focal_group,
         a.codinv, a.appln_id
  FROM rs_frac_acquirer_patents a
  JOIN rs_frac_focal_cells f USING (deal_id, cohort)
)
SELECT
  p.deal_id, p.cohort, p.arm, p.focal_group, p.codinv,
  SUM(1.0/t.team_size) combined_fractional_patents_5y
FROM pooled p
JOIN rs_frac_team_size t USING (appln_id)
GROUP BY 1,2,3,4,5
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_frac_focal_standing AS
SELECT *,
  100.0*(RANK() OVER (
    PARTITION BY deal_id,cohort,arm,focal_group
    ORDER BY focal_fractional_patents_5y
  )-1)/COUNT(*) OVER (
    PARTITION BY deal_id,cohort,arm,focal_group
  ) focal_fractional_standing_pct
FROM rs_frac_focal_productivity
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_frac_combined_standing AS
SELECT *,
  100.0*(RANK() OVER (
    PARTITION BY deal_id,cohort,arm,focal_group
    ORDER BY combined_fractional_patents_5y
  )-1)/COUNT(*) OVER (
    PARTITION BY deal_id,cohort,arm,focal_group
  ) combined_fractional_standing_pct
FROM rs_frac_combined_productivity
")
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE rs_frac_moderator AS
SELECT
  r.roster_row_id,
  f.focal_fractional_patents_5y,
  c.combined_fractional_patents_5y,
  f.focal_fractional_standing_pct,
  c.combined_fractional_standing_pct,
  f.focal_fractional_standing_pct-c.combined_fractional_standing_pct
    fractional_standing_loss_pp,
  (f.focal_fractional_standing_pct-c.combined_fractional_standing_pct)/10.0
    fractional_standing_loss_10pp
FROM rs_frac_roster r
JOIN rs_frac_focal_standing f
  ON f.deal_id=r.deal_id AND f.cohort=r.cohort AND f.arm=r.arm
 AND f.focal_group=r.focal_group AND f.codinv=r.codinv
JOIN rs_frac_combined_standing c
  ON c.deal_id=r.deal_id AND c.cohort=r.cohort AND c.arm=r.arm
 AND c.focal_group=r.focal_group AND c.codinv=r.codinv
")

if (file.exists(fractional_path) && !file.remove(fractional_path)) {
  stop("Could not replace fractional-standing moderator artifact")
}
DBI::dbExecute(con, sprintf(
  "COPY (SELECT * FROM rs_frac_moderator ORDER BY roster_row_id)
   TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
  DBI::dbQuoteString(
    con, normalizePath(fractional_path, winslash = "/", mustWork = FALSE)
  )
))

fractional_sql <- DBI::dbQuoteString(
  con, normalizePath(fractional_path, winslash = "/", mustWork = TRUE)
)
unit <- DBI::dbGetQuery(con, sprintf("
SELECT
  u.*, s.relative_standing_loss_10pp AS count_loss_10pp,
  s.relative_standing_loss_pp AS count_loss_pp,
  s.focal_inventors, s.combined_inventors,
  f.fractional_standing_loss_10pp AS fractional_loss_10pp,
  f.fractional_standing_loss_pp AS fractional_loss_pp
FROM read_parquet(%s) u
JOIN read_parquet(%s) s USING (roster_row_id)
JOIN read_parquet(%s) f USING (roster_row_id)
WHERE s.standing_eligibility='eligible'
", unit_sql, strict_sql, fractional_sql))
unit$treated <- as.numeric(unit$treated)
if (!nrow(unit) || anyDuplicated(unit$roster_row_id)) {
  stop("Precision-analysis unit data are empty or duplicated")
}

wmean <- function(x, w) sum(x*w)/sum(w)
wsd <- function(x, w) {
  mu <- wmean(x, w)
  sqrt(sum(w*(x-mu)^2)/sum(w))
}
prepare <- function(x, moderator) {
  z <- lmv2_vr_analysis_weights(x)
  tr <- z$treated == 1
  center <- function(v) v-wmean(v[tr], z$analysis_weight[tr])
  standardize <- function(v) {
    (v-wmean(v[tr], z$analysis_weight[tr]))/
      wsd(v[tr], z$analysis_weight[tr])
  }
  loss <- z[[moderator]]
  z$loss_hinge_c <- center(pmax(loss, 0))
  z$gain_hinge_c <- center(pmax(-loss, 0))
  z$tx_loss_hinge <- z$treated*z$loss_hinge_c
  z$tx_gain_hinge <- z$treated*z$gain_hinge_c
  z$trajectory_z <- standardize(z$patent_trajectory)
  z$age_z <- standardize(log1p(z$career_age))
  z$tenure_z <- standardize(log1p(z$focal_group_tenure))
  z$exclusivity_z <- standardize(z$focal_group_exclusivity)
  z$team_any_c <- center(z$team_any)
  team_positive <- tr & z$team_any == 1
  team_mean <- wmean(
    z$persistent_patent_share[team_positive],
    z$analysis_weight[team_positive]
  )
  z$team_intensity <- ifelse(
    z$team_any == 1, z$persistent_patent_share-team_mean, 0
  )
  z$focal_size_z <- standardize(log1p(z$focal_inventors))
  z$added_size_z <- standardize(log1p(pmax(
    z$combined_inventors-z$focal_inventors, 0
  )))
  z$pre_ref_z <- standardize(z$patent_pre_ref)
  z$pre_avg_z <- standardize(z$patent_pre_avg)
  z$prod_bin <- factor(
    ifelse(z$patent_count_5y >= 6, "6+", as.character(z$patent_count_5y)),
    levels = c("1", "2", "3", "4", "5", "6+")
  )
  z
}

base_terms <- c(
  "factor(cohort)", "treated", "loss_hinge_c", "gain_hinge_c",
  "tx_loss_hinge", "tx_gain_hinge", "log_patent_count_5y",
  "log1p(career_age)", "team_any_c", "team_intensity"
)
precision_terms <- c(
  "factor(cohort)", "treated", "loss_hinge_c", "gain_hinge_c",
  "tx_loss_hinge", "tx_gain_hinge", "factor(prod_bin)",
  "treated:factor(prod_bin)", "trajectory_z", "treated:trajectory_z",
  "age_z", "treated:age_z", "tenure_z", "treated:tenure_z",
  "exclusivity_z", "treated:exclusivity_z", "team_any_c",
  "treated:team_any_c", "team_intensity", "treated:team_intensity",
  "focal_size_z", "treated:focal_size_z", "added_size_z",
  "treated:added_size_z", "pre_ref_z", "treated:pre_ref_z",
  "pre_avg_z", "treated:pre_avg_z"
)

deal_multipliers <- lmv2_vr_webb_multipliers(
  sort(unique(unit$deal_id)), cfg
)
fit_one <- function(data, rhs, term, specification, moderator_name) {
  fit <- lmv2_vr_fit_wls(data, "d_patent_ref", rhs)
  covariance <- lmv2_vr_model_covariance(fit)
  ans <- lmv2_vr_linear_result(
    fit, covariance, setNames(1, term), deal_multipliers,
    "ATT gradient per 10pp predicted standing loss", cfg
  )
  ans$specification <- specification
  ans$moderator <- moderator_name
  ans$term <- term
  ans$n_observations <- fit$n
  ans$treated_inventors <- sum(data$treated == 1)
  ans$treated_deals <- length(unique(data$deal_id[data$treated == 1]))
  ans$mde_80 <- (
    ans$governing_critical+stats::qnorm(cfg$inference$target_power)
  )*ans$governing_se
  ans
}

z_count <- prepare(unit, "count_loss_10pp")
z_fractional <- prepare(unit, "fractional_loss_10pp")
results <- rbind(
  fit_one(
    z_count, base_terms, "tx_loss_hinge",
    "count_hinge_baseline", "strict_count_rank"
  ),
  fit_one(
    z_count, precision_terms, "tx_loss_hinge",
    "count_hinge_predeal_precision", "strict_count_rank"
  ),
  fit_one(
    z_fractional, precision_terms, "tx_loss_hinge",
    "fractional_hinge_predeal_precision", "fractional_patent_rank"
  )
)
utils::write.csv(
  results, file.path(out_dir, "relative_standing_power_results.csv"),
  row.names = FALSE
)

support_one <- function(z, moderator, moderator_name) {
  tr <- z$treated == 1
  value <- z[[moderator]]
  positive <- tr & value > 0
  deal_weight <- stats::aggregate(
    analysis_weight ~ deal_id, data = z[positive, ], FUN = sum
  )
  shares <- deal_weight$analysis_weight/sum(deal_weight$analysis_weight)
  data.frame(
    moderator = moderator_name,
    treated_inventors = sum(tr),
    zero_n = sum(tr & value == 0),
    zero_share = mean(value[tr] == 0),
    positive_loss_n = sum(positive),
    positive_loss_share = mean(value[tr] > 0),
    positive_loss_deals = length(unique(z$deal_id[positive])),
    effective_positive_loss_deals = 1/sum(shares^2),
    largest_positive_loss_deal_share = max(shares),
    positive_loss_sd_10pp = wsd(
      value[positive], z$analysis_weight[positive]
    )
  )
}
support <- rbind(
  support_one(z_count, "count_loss_10pp", "strict_count_rank"),
  support_one(
    z_fractional, "fractional_loss_10pp", "fractional_patent_rank"
  )
)
utils::write.csv(
  support, file.path(out_dir, "relative_standing_power_support.csv"),
  row.names = FALSE
)

# The diagnostic years overlap the five-year moderator-construction window;
# this is a trajectory diagnostic, not an independent held-out pretrend test.
panel_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
if (length(panel_files) != length(cfg$estimand$cohorts)) {
  stop("Certified event-panel shard set is incomplete")
}
panel_sql <- lmv2_panel_sql(panel_files)
deal_levels <- sort(unique(unit$deal_id))
run_pretrend <- function(moderator, file_stub) {
  pre_results <- list()
  pre_scores <- list()
  for (event_time in cfg$estimand$pretrend_event_times) {
    pre_y <- DBI::dbGetQuery(con, sprintf("
      SELECT p.roster_row_id,
             CAST(p.patent_count-b.patent_count AS DOUBLE) d_pre
      FROM %1$s p
      JOIN %1$s b USING (roster_row_id)
      WHERE p.event_time=%2$d AND b.event_time=%3$d
    ", panel_sql, event_time, cfg$estimand$reference_event_time))
    q <- merge(unit, pre_y, by="roster_row_id", sort=FALSE)
    q <- prepare(q, moderator)
    fit <- lmv2_vr_fit_wls(q, "d_pre", precision_terms)
    covariance <- lmv2_vr_model_covariance(fit)
    ans <- lmv2_vr_linear_result(
      fit, covariance, c(tx_loss_hinge=1), deal_multipliers,
      paste0("event time ", event_time), cfg
    )
    ans$event_time <- event_time
    ans$specification <- paste0(file_stub, "_hinge_predeal_precision")
    pre_results[[as.character(event_time)]] <- ans
    score <- covariance$S_deal[, "tx_loss_hinge"]
    aligned <- setNames(rep(0, length(deal_levels)), as.character(deal_levels))
    aligned[names(score)] <- score
    pre_scores[[as.character(event_time)]] <- aligned/ans$deal_se
  }
  pre_results <- do.call(rbind, pre_results)
  utils::write.csv(
    pre_results,
    file.path(out_dir, paste0(file_stub, "_pretrend_results.csv")),
    row.names = FALSE
  )
  score_matrix <- do.call(cbind, pre_scores)
  bootstrap_t <- deal_multipliers %*% score_matrix
  observed_t <- pre_results$estimate/pre_results$deal_se
  joint_p <- (
    1+sum(apply(abs(bootstrap_t), 1L, max) >= max(abs(observed_t)))
  )/(
    nrow(bootstrap_t)+1
  )
  pre_omnibus <- data.frame(
    test = paste(
      "joint loss-side gradient trajectory diagnostic,",
      file_stub, "event times -5 to -2"
    ),
    max_abs_t = max(abs(observed_t)),
    deal_wild_p = joint_p,
    bootstrap_replications = cfg$inference$bootstrap_replications
  )
  utils::write.csv(
    pre_omnibus,
    file.path(out_dir, paste0(file_stub, "_pretrend_omnibus.csv")),
    row.names = FALSE
  )
  pre_omnibus
}
count_pretrend <- run_pretrend("count_loss_10pp", "count_standing")
fractional_pretrend_path <- file.path(
  out_dir, "fractional_standing_pretrend_omnibus.csv"
)
fractional_pretrend <- if (file.exists(fractional_pretrend_path)) {
  utils::read.csv(fractional_pretrend_path, stringsAsFactors=FALSE)
} else {
  run_pretrend("fractional_loss_10pp", "fractional_standing")
}

manifest <- data.frame(
  status = "exploratory_outcome_blind_power_improvement",
  relative_standing_version = LMV2_RELSTAND_VERSION,
  strict_moderator_sha256 = digest::digest(file=strict_path, algo="sha256"),
  fractional_moderator_sha256 = digest::digest(
    file=fractional_path, algo="sha256"
  ),
  unit_sha256 = digest::digest(file=unit_path, algo="sha256"),
  result_rows = nrow(results), support_rows = nrow(support)
)
utils::write.csv(
  manifest, file.path(out_dir, "relative_standing_power_manifest.csv"),
  row.names = FALSE
)
message("Relative-standing power-improvement probes complete.")

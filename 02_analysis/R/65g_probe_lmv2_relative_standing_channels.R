# ============================================================================
# 65g_probe_lmv2_relative_standing_channels.R
# Exploratory channel probes after correcting the standing-pool construction.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "fixest", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))
source(file.path(BASE, "R", "65a_lmv2_relative_standing_config.R"))

cfg <- LMV2_RELSTAND
root_dir <- cfg$output_dir
out_dir <- file.path(root_dir, "diagnostics_v2")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
moderator_path <- file.path(root_dir, "relative_standing_moderators.parquet")

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
z <- DBI::dbGetQuery(con, sprintf("
SELECT
  v.*, r.relative_standing_loss_10pp, r.relative_standing_loss_pp,
  r.positive_standing_loss, r.focal_inventors, r.combined_inventors
FROM read_parquet(%s) v
JOIN read_parquet(%s) r USING (roster_row_id)
WHERE r.standing_eligibility='eligible'
", DBI::dbQuoteString(con, normalizePath(
  cfg$inputs$vr_unit_analysis, winslash = "/", mustWork = TRUE
)), DBI::dbQuoteString(con, normalizePath(
  moderator_path, winslash = "/", mustWork = TRUE
))))
z$treated <- as.numeric(z$treated)
z <- lmv2_vr_analysis_weights(z)
tr <- z$treated == 1
wmean <- function(x, w) sum(x * w) / sum(w)
wsd <- function(x, w) {
  m <- wmean(x, w)
  sqrt(sum(w * (x - m)^2) / sum(w))
}
standardize <- function(v) {
  s <- wsd(v[tr], z$analysis_weight[tr])
  (v - wmean(v[tr], z$analysis_weight[tr])) / s
}
center <- function(v) v - wmean(v[tr], z$analysis_weight[tr])

z$loss_c <- center(z$relative_standing_loss_10pp)
z$trajectory_z <- standardize(z$patent_trajectory)
z$age_z <- standardize(log1p(z$career_age))
z$tenure_z <- standardize(log1p(z$focal_group_tenure))
z$exclusivity_z <- standardize(z$focal_group_exclusivity)
z$team_any_c <- center(z$team_any)
z$team_intensity <- ifelse(
  z$team_any == 1,
  z$persistent_patent_share - wmean(
    z$persistent_patent_share[tr & z$team_any == 1],
    z$analysis_weight[tr & z$team_any == 1]
  ), 0
)
z$focal_size_z <- standardize(log1p(z$focal_inventors))
z$added_size_z <- standardize(log1p(pmax(
  z$combined_inventors - z$focal_inventors, 0
)))
z$prod_bin <- factor(
  ifelse(z$patent_count_5y >= 6, "6+", as.character(z$patent_count_5y)),
  levels = c("1", "2", "3", "4", "5", "6+")
)
z$deal_arm <- interaction(z$deal_id, z$treated, drop = TRUE)

flex_terms <- c(
  "loss_c", "treated:loss_c", "factor(prod_bin)",
  "treated:factor(prod_bin)", "trajectory_z", "treated:trajectory_z",
  "age_z", "treated:age_z", "tenure_z", "treated:tenure_z",
  "exclusivity_z", "treated:exclusivity_z", "team_any_c",
  "treated:team_any_c", "team_intensity", "treated:team_intensity",
  "focal_size_z", "treated:focal_size_z", "added_size_z",
  "treated:added_size_z"
)

fit_one <- function(data, terms, fixed_effect, focal_term, specification) {
  fit <- fixest::feols(
    stats::as.formula(paste(
      "d_patent_ref ~ treated +", paste(terms, collapse = " + "),
      "|", fixed_effect
    )),
    data = data, weights = ~analysis_weight,
    cluster = ~deal_id + codinv, notes = FALSE
  )
  ci <- stats::confint(fit, focal_term)
  data.frame(
    specification = specification, term = focal_term,
    estimate = unname(stats::coef(fit)[focal_term]),
    two_way_se = unname(fixest::se(fit)[focal_term]),
    p_value = unname(fixest::pvalue(fit)[focal_term]),
    ci_low = unname(ci[1]), ci_high = unname(ci[2]),
    n_observations = stats::nobs(fit),
    treated_inventors = sum(data$treated == 1),
    deals = length(unique(data$deal_id)),
    stringsAsFactors = FALSE
  )
}

results <- list()
results[[1]] <- fit_one(
  z, flex_terms, "factor(cohort)", "treated:loss_c",
  "flexible_productivity_and_organization_controls"
)

tech <- z[z$techfit_full_reason == "eligible" & is.finite(z$techfit_full), ]
tr_tech <- tech$treated == 1
tech_mean <- wmean(tech$techfit_full[tr_tech], tech$analysis_weight[tr_tech])
tech_sd <- wsd(tech$techfit_full[tr_tech], tech$analysis_weight[tr_tech])
tech$techfit_z <- (tech$techfit_full - tech_mean) / tech_sd
results[[2]] <- fit_one(
  tech, c(flex_terms, "techfit_z", "treated:techfit_z"),
  "factor(cohort)", "treated:loss_c", "flexible_controls_plus_techfit"
)

results[[3]] <- fit_one(
  z, flex_terms, "deal_arm", "treated:loss_c",
  "flexible_controls_deal_by_arm_fixed_effects"
)

loss_region <- z[z$relative_standing_loss_pp > 0, ]
loss_region$loss_positive_c <- loss_region$relative_standing_loss_10pp -
  wmean(
    loss_region$relative_standing_loss_10pp[loss_region$treated == 1],
    loss_region$analysis_weight[loss_region$treated == 1]
  )
loss_terms <- sub("loss_c", "loss_positive_c", flex_terms, fixed = TRUE)
results[[4]] <- fit_one(
  loss_region, loss_terms, "deal_arm", "treated:loss_positive_c",
  "actual_predicted_losses_only"
)

gain_region <- z[z$relative_standing_loss_pp < 0, ]
gain_region$gain_size_c <- -gain_region$relative_standing_loss_10pp -
  wmean(
    -gain_region$relative_standing_loss_10pp[gain_region$treated == 1],
    gain_region$analysis_weight[gain_region$treated == 1]
  )
gain_terms <- sub("loss_c", "gain_size_c", flex_terms, fixed = TRUE)
results[[5]] <- fit_one(
  gain_region, gain_terms, "deal_arm", "treated:gain_size_c",
  "actual_predicted_gains_only"
)

productive <- z[z$patent_count_5y >= 2, ]
productive$positive_loss_c <- productive$positive_standing_loss -
  wmean(
    productive$positive_standing_loss[productive$treated == 1],
    productive$analysis_weight[productive$treated == 1]
  )
binary_terms <- c(
  setdiff(flex_terms, c("loss_c", "treated:loss_c")),
  "positive_loss_c", "treated:positive_loss_c"
)
results[[6]] <- fit_one(
  productive, binary_terms, "deal_arm", "treated:positive_loss_c",
  "positive_loss_indicator_among_2plus_patents"
)

results <- do.call(rbind, results)
utils::write.csv(
  results, file.path(out_dir, "relative_standing_channel_probes.csv"),
  row.names = FALSE
)

region_covariates <- DBI::dbGetQuery(con, sprintf("
WITH u AS (
  SELECT v.*, r.relative_standing_loss_pp, r.focal_inventors,
         r.combined_inventors
  FROM read_parquet(%s) v
  JOIN read_parquet(%s) r USING(roster_row_id)
  WHERE r.standing_eligibility='eligible' AND v.arm='treated'
)
SELECT
  CASE
    WHEN relative_standing_loss_pp < -5 THEN 'gain_gt_5pp'
    WHEN relative_standing_loss_pp < 0 THEN 'gain_0_to_5pp'
    WHEN relative_standing_loss_pp = 0 THEN 'zero'
    WHEN relative_standing_loss_pp <= 5 THEN 'loss_0_to_5pp'
    ELSE 'loss_gt_5pp'
  END region,
  COUNT(*) n, AVG(log_patent_count_5y) mean_log_productivity,
  AVG(techfit_full) mean_techfit, AVG(focal_inventors) mean_focal_inventors,
  AVG(combined_inventors-focal_inventors) mean_added_inventors,
  AVG(focal_group_exclusivity) mean_focal_exclusivity
FROM u GROUP BY 1 ORDER BY MIN(relative_standing_loss_pp)
", DBI::dbQuoteString(con, normalizePath(
  cfg$inputs$vr_unit_analysis, winslash = "/", mustWork = TRUE
)), DBI::dbQuoteString(con, normalizePath(
  moderator_path, winslash = "/", mustWork = TRUE
))))
utils::write.csv(
  region_covariates,
  file.path(out_dir, "relative_standing_region_covariates.csv"),
  row.names = FALSE
)

manifest <- data.frame(
  status = "exploratory_post_results_channel_probe",
  relative_standing_version = LMV2_RELSTAND_VERSION,
  moderator_sha256 = digest::digest(file = moderator_path, algo = "sha256"),
  result_rows = nrow(results), treated_inventors = sum(z$treated == 1)
)
utils::write.csv(
  manifest, file.path(out_dir, "relative_standing_channel_manifest.csv"),
  row.names = FALSE
)
message("Relative-standing channel probes complete.")

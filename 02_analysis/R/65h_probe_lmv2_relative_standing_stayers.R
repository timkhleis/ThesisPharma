# ============================================================================
# 65h_probe_lmv2_relative_standing_stayers.R
# Exploratory corrected relative-standing probes in the initially retained
# (post-treatment-selected) P5b analysis population.
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
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))
source(file.path(BASE, "R", "33a_lmv2_stayer_heterogeneity_config.R"))
source(file.path(BASE, "R", "65a_lmv2_relative_standing_config.R"))

stayer_path <- file.path(
  LMV2_STAYER_HET$output_dir, "stayer_unit_analysis.parquet"
)
moderator_path <- file.path(
  LMV2_RELSTAND$output_dir, "relative_standing_moderators.parquet"
)
out_dir <- file.path(LMV2_RELSTAND$output_dir, "stayer_diagnostics_v2")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
z <- DBI::dbGetQuery(con, sprintf("
SELECT
  s.*, r.relative_standing_loss_10pp, r.relative_standing_loss_pp,
  r.positive_standing_loss, r.focal_inventors, r.combined_inventors
FROM read_parquet(%s) s
JOIN read_parquet(%s) r USING (roster_row_id)
WHERE r.standing_eligibility='eligible'
", DBI::dbQuoteString(con, normalizePath(
  stayer_path, winslash = "/", mustWork = TRUE
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
z$loss_hinge <- pmax(z$relative_standing_loss_10pp, 0)
z$gain_hinge <- pmax(-z$relative_standing_loss_10pp, 0)
z$loss_hinge_c <- center(z$loss_hinge)
z$gain_hinge_c <- center(z$gain_hinge)
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

nuisance_terms <- c(
  "factor(prod_bin)", "treated:factor(prod_bin)",
  "trajectory_z", "treated:trajectory_z", "age_z", "treated:age_z",
  "tenure_z", "treated:tenure_z", "exclusivity_z",
  "treated:exclusivity_z", "team_any_c", "treated:team_any_c",
  "team_intensity", "treated:team_intensity", "focal_size_z",
  "treated:focal_size_z", "added_size_z", "treated:added_size_z"
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
    treated_actual_loss = sum(
      data$treated == 1 & data$relative_standing_loss_pp > 0
    ),
    treated_deals = length(unique(data$deal_id[data$treated == 1])),
    treated_actual_loss_deals = length(unique(data$deal_id[
      data$treated == 1 & data$relative_standing_loss_pp > 0
    ])),
    stringsAsFactors = FALSE
  )
}

results <- list()
results[[1]] <- fit_one(
  z, c("loss_c", "treated:loss_c", nuisance_terms),
  "factor(cohort)", "treated:loss_c",
  "initially_retained_full_support_linear"
)
results[[2]] <- fit_one(
  z,
  c(
    "loss_hinge_c", "treated:loss_hinge_c", "gain_hinge_c",
    "treated:gain_hinge_c", nuisance_terms
  ),
  "deal_arm", "treated:loss_hinge_c",
  "initially_retained_full_support_hinge_loss_slope"
)

loss_region <- z[z$relative_standing_loss_pp > 0, ]
loss_tr <- loss_region$treated == 1
loss_region$loss_positive_c <- loss_region$relative_standing_loss_10pp -
  wmean(
    loss_region$relative_standing_loss_10pp[loss_tr],
    loss_region$analysis_weight[loss_tr]
  )
results[[3]] <- fit_one(
  loss_region,
  c("loss_positive_c", "treated:loss_positive_c", nuisance_terms),
  "deal_arm", "treated:loss_positive_c",
  "initially_retained_actual_predicted_losses_only"
)

productive <- z[z$patent_count_5y >= 2, ]
productive_tr <- productive$treated == 1
productive$positive_loss_c <- productive$positive_standing_loss -
  wmean(
    productive$positive_standing_loss[productive_tr],
    productive$analysis_weight[productive_tr]
  )
results[[4]] <- fit_one(
  productive,
  c("positive_loss_c", "treated:positive_loss_c", nuisance_terms),
  "deal_arm", "treated:positive_loss_c",
  "initially_retained_positive_loss_indicator_among_2plus_patents"
)

results <- do.call(rbind, results)
utils::write.csv(
  results,
  file.path(out_dir, "relative_standing_stayer_channel_probes.csv"),
  row.names = FALSE
)

# Apply the project's governing inference rule (Webb deal bootstrap plus
# two-way deal-inventor clustering, taking the more conservative result) to
# cohort-FE versions that remain full rank under the frozen WLS helper.
deal_multipliers <- lmv2_vr_webb_multipliers(
  sort(unique(z$deal_id)), LMV2_VR_HET
)
governing_one <- function(data, rhs, focal_term, specification) {
  fit <- lmv2_vr_fit_wls(data, "d_patent_ref", rhs)
  covariance <- lmv2_vr_model_covariance(fit)
  ans <- lmv2_vr_linear_result(
    fit, covariance, setNames(1, focal_term), deal_multipliers,
    focal_term, LMV2_VR_HET
  )
  ans$specification <- specification
  ans$term <- focal_term
  ans$n_observations <- fit$n
  ans$treated_inventors <- sum(data$treated == 1)
  ans$treated_actual_loss <- sum(
    data$treated == 1 & data$relative_standing_loss_pp > 0
  )
  ans$treated_deals <- length(unique(data$deal_id[data$treated == 1]))
  ans$treated_actual_loss_deals <- length(unique(data$deal_id[
    data$treated == 1 & data$relative_standing_loss_pp > 0
  ]))
  ans
}

governing <- list()
governing[[1]] <- governing_one(
  z,
  c(
    "treated", "loss_c", "treated:loss_c", nuisance_terms,
    "factor(cohort)"
  ),
  "treated:loss_c", "initially_retained_full_support_linear"
)
governing[[2]] <- governing_one(
  z,
  c(
    "treated", "loss_hinge_c", "treated:loss_hinge_c",
    "gain_hinge_c", "treated:gain_hinge_c", nuisance_terms,
    "factor(cohort)"
  ),
  "treated:loss_hinge_c",
  "initially_retained_full_support_hinge_loss_slope"
)
governing[[3]] <- governing_one(
  loss_region,
  c(
    "treated", "loss_positive_c", "treated:loss_positive_c",
    nuisance_terms, "factor(cohort)"
  ),
  "treated:loss_positive_c",
  "initially_retained_actual_predicted_losses_only"
)
governing[[4]] <- governing_one(
  productive,
  c(
    "treated", "positive_loss_c", "treated:positive_loss_c",
    nuisance_terms, "factor(cohort)"
  ),
  "treated:positive_loss_c",
  "initially_retained_positive_loss_indicator_among_2plus_patents"
)
governing <- do.call(rbind, governing)
utils::write.csv(
  governing,
  file.path(
    out_dir, "relative_standing_stayer_governing_inference.csv"
  ),
  row.names = FALSE
)

manifest <- data.frame(
  status = "exploratory_post_results_initially_retained_probe",
  relative_standing_version = LMV2_RELSTAND_VERSION,
  moderator_sha256 = digest::digest(file = moderator_path, algo = "sha256"),
  stayer_unit_sha256 = digest::digest(file = stayer_path, algo = "sha256"),
  treated_inventors = sum(z$treated == 1),
  treated_actual_loss = sum(tr & z$relative_standing_loss_pp > 0),
  treated_deals = length(unique(z$deal_id[tr])),
  treated_actual_loss_deals = length(unique(
    z$deal_id[tr & z$relative_standing_loss_pp > 0]
  ))
)
utils::write.csv(
  manifest,
  file.path(out_dir, "relative_standing_stayer_manifest.csv"),
  row.names = FALSE
)
message("Initially retained relative-standing probes complete.")

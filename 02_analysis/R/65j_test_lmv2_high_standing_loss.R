# ============================================================================
# 65j_test_lmv2_high_standing_loss.R
# Theory-aligned relative-standing test: among inventors with high target-firm
# standing before acquisition, does a larger predicted downward move imply a
# more negative patent-count ATT?
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest", "WeightIt")) {
  if (!requireNamespace(pkg, quietly=TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))
source(file.path(BASE, "R", "65a_lmv2_relative_standing_config.R"))

cfg <- LMV2_RELSTAND
out_dir <- file.path(cfg$output_dir, "high_standing_loss_v2")
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)
moderator_path <- file.path(
  cfg$output_dir, "relative_standing_moderators.parquet"
)

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown=TRUE), add=TRUE)
unit <- DBI::dbGetQuery(con, sprintf("
SELECT
  u.*, m.focal_standing_pct, m.combined_standing_pct,
  m.relative_standing_loss_pp, m.relative_standing_loss_10pp,
  m.focal_inventors, m.combined_inventors
FROM read_parquet(%s) u
JOIN read_parquet(%s) m USING (roster_row_id)
WHERE m.standing_eligibility='eligible'
", DBI::dbQuoteString(con, normalizePath(
  cfg$inputs$vr_unit_analysis, winslash="/", mustWork=TRUE
)), DBI::dbQuoteString(con, normalizePath(
  moderator_path, winslash="/", mustWork=TRUE
))))
unit$treated <- as.numeric(unit$treated)
if (!nrow(unit) || anyDuplicated(unit$roster_row_id)) {
  stop("High-standing analysis unit is empty or duplicated")
}

wmean <- function(x, w) sum(x*w)/sum(w)
wsd <- function(x, w) {
  mu <- wmean(x, w)
  sqrt(sum(w*(x-mu)^2)/sum(w))
}
prepare <- function(x) {
  z <- lmv2_vr_analysis_weights(x)
  tr <- z$treated == 1
  center <- function(v) v-wmean(v[tr], z$analysis_weight[tr])
  standardize <- function(v) {
    (v-wmean(v[tr], z$analysis_weight[tr]))/
      wsd(v[tr], z$analysis_weight[tr])
  }
  z$loss_hinge_c <- center(pmax(z$relative_standing_loss_10pp, 0))
  z$gain_hinge_c <- center(pmax(-z$relative_standing_loss_10pp, 0))
  z$tx_loss_hinge <- z$treated*z$loss_hinge_c
  z$tx_gain_hinge <- z$treated*z$gain_hinge_c
  z$standing_z <- standardize(z$focal_standing_pct)
  z$trajectory_z <- standardize(z$patent_trajectory)
  z$age_z <- standardize(log1p(z$career_age))
  z$tenure_z <- standardize(log1p(z$focal_group_tenure))
  z$exclusivity_z <- standardize(z$focal_group_exclusivity)
  z$team_any_c <- center(z$team_any)
  positive_team <- tr & z$team_any == 1
  team_mean <- wmean(
    z$persistent_patent_share[positive_team],
    z$analysis_weight[positive_team]
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
    levels=c("1", "2", "3", "4", "5", "6+")
  )
  z
}

precision_terms <- c(
  "factor(cohort)", "treated", "loss_hinge_c", "gain_hinge_c",
  "tx_loss_hinge", "tx_gain_hinge", "standing_z",
  "treated:standing_z", "factor(prod_bin)",
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
fit_one <- function(data, specification, threshold, sample_rule) {
  fit <- lmv2_vr_fit_wls(data, "d_patent_ref", precision_terms)
  covariance <- lmv2_vr_model_covariance(fit)
  ans <- lmv2_vr_linear_result(
    fit, covariance, c(tx_loss_hinge=1), deal_multipliers,
    "ATT gradient per 10pp predicted loss among high-standing inventors",
    cfg
  )
  ans$specification <- specification
  ans$baseline_standing_threshold <- threshold
  ans$sample_rule <- sample_rule
  ans$n_observations <- fit$n
  ans$treated_inventors <- sum(data$treated == 1)
  ans$treated_loss_inventors <- sum(
    data$treated == 1 & data$relative_standing_loss_pp > 0
  )
  ans$treated_deals <- length(unique(data$deal_id[data$treated == 1]))
  ans$treated_loss_deals <- length(unique(data$deal_id[
    data$treated == 1 & data$relative_standing_loss_pp > 0
  ]))
  ans$mde_80 <- (
    ans$governing_critical+stats::qnorm(cfg$inference$target_power)
  )*ans$governing_se
  list(result=ans, fit=fit, covariance=covariance)
}

thresholds <- c(75, 80, 90)
fits <- list()
results <- list()
for (threshold in thresholds) {
  z <- prepare(unit[unit$focal_standing_pct >= threshold, ])
  label <- paste0("high_standing_", threshold, "_full_hinge")
  fits[[label]] <- fit_one(
    z, label, threshold, "all changes; separate loss and gain hinges"
  )
  results[[label]] <- fits[[label]]$result
}

# Secondary dose-response using only actual downward moves. This directly
# mirrors the big-frog-to-smaller-frog comparison but sacrifices precision.
loss80 <- unit[
  unit$focal_standing_pct >= 80 & unit$relative_standing_loss_pp > 0,
]
loss80 <- prepare(loss80)
fits[["high_standing_80_actual_losses_only"]] <- fit_one(
  loss80, "high_standing_80_actual_losses_only", 80,
  "strictly positive predicted losses only"
)
results[["high_standing_80_actual_losses_only"]] <-
  fits[["high_standing_80_actual_losses_only"]]$result
results <- do.call(rbind, results)
utils::write.csv(
  results, file.path(out_dir, "high_standing_loss_results.csv"),
  row.names=FALSE
)

smd <- function(x, variable) {
  tr <- x$treated == 1
  mt <- wmean(x[[variable]][tr], x$analysis_weight[tr])
  mc <- wmean(x[[variable]][!tr], x$analysis_weight[!tr])
  st <- wsd(x[[variable]][tr], x$analysis_weight[tr])
  sc <- wsd(x[[variable]][!tr], x$analysis_weight[!tr])
  (mt-mc)/sqrt((st^2+sc^2)/2)
}
balance_vars <- c(
  "relative_standing_loss_10pp", "focal_standing_pct",
  "log_patent_count_5y", "patent_trajectory", "career_age",
  "focal_group_tenure", "focal_group_exclusivity", "focal_inventors",
  "combined_inventors"
)
balance <- list()
for (threshold in thresholds) {
  z <- prepare(unit[unit$focal_standing_pct >= threshold, ])
  for (variable in balance_vars) {
    balance[[paste(threshold, variable)]] <- data.frame(
      threshold=threshold, sample_rule="full_hinge",
      variable=variable, smd=smd(z, variable)
    )
  }
}
for (variable in balance_vars) {
  balance[[paste("loss80", variable)]] <- data.frame(
    threshold=80, sample_rule="actual_losses_only",
    variable=variable, smd=smd(loss80, variable)
  )
}
balance <- do.call(rbind, balance)
utils::write.csv(
  balance, file.path(out_dir, "high_standing_loss_balance.csv"),
  row.names=FALSE
)

support <- do.call(rbind, lapply(thresholds, function(threshold) {
  z <- prepare(unit[unit$focal_standing_pct >= threshold, ])
  tr_loss <- z$treated == 1 & z$relative_standing_loss_pp > 0
  dw <- stats::aggregate(
    analysis_weight~deal_id, data=z[tr_loss, ], FUN=sum
  )
  share <- dw$analysis_weight/sum(dw$analysis_weight)
  data.frame(
    threshold=threshold,
    treated_high_standing=sum(z$treated == 1),
    treated_actual_loss=sum(tr_loss),
    treated_gain=sum(z$treated == 1 & z$relative_standing_loss_pp < 0),
    actual_loss_deals=length(unique(z$deal_id[tr_loss])),
    effective_loss_deals=1/sum(share^2),
    largest_loss_deal_share=max(share),
    loss_sd_10pp=wsd(
      z$relative_standing_loss_10pp[tr_loss],
      z$analysis_weight[tr_loss]
    )
  )
}))
utils::write.csv(
  support, file.path(out_dir, "high_standing_loss_support.csv"),
  row.names=FALSE
)

# Primary threshold pre-period trajectory diagnostic.
panel_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern="^lmv2_event_panel_c[0-9]+\\.parquet$", full.names=TRUE
))
panel_sql <- lmv2_panel_sql(panel_files)
primary_unit <- unit[unit$focal_standing_pct >= 80, ]
pre_results <- list()
pre_scores <- list()
deal_levels <- sort(unique(unit$deal_id))
for (event_time in cfg$estimand$pretrend_event_times) {
  pre_y <- DBI::dbGetQuery(con, sprintf("
    SELECT p.roster_row_id,
           CAST(p.patent_count-b.patent_count AS DOUBLE) d_pre
    FROM %1$s p JOIN %1$s b USING (roster_row_id)
    WHERE p.event_time=%2$d AND b.event_time=%3$d
  ", panel_sql, event_time, cfg$estimand$reference_event_time))
  q <- merge(primary_unit, pre_y, by="roster_row_id", sort=FALSE)
  q <- prepare(q)
  fit <- lmv2_vr_fit_wls(q, "d_pre", precision_terms)
  covariance <- lmv2_vr_model_covariance(fit)
  ans <- lmv2_vr_linear_result(
    fit, covariance, c(tx_loss_hinge=1), deal_multipliers,
    paste0("event time ", event_time), cfg
  )
  ans$event_time <- event_time
  pre_results[[as.character(event_time)]] <- ans
  score <- covariance$S_deal[, "tx_loss_hinge"]
  aligned <- setNames(rep(0, length(deal_levels)), as.character(deal_levels))
  aligned[names(score)] <- score
  pre_scores[[as.character(event_time)]] <- aligned/ans$deal_se
}
pre_results <- do.call(rbind, pre_results)
utils::write.csv(
  pre_results, file.path(out_dir, "high_standing_80_pretrend_results.csv"),
  row.names=FALSE
)
bootstrap_t <- deal_multipliers %*% do.call(cbind, pre_scores)
observed_t <- pre_results$estimate/pre_results$deal_se
pre_omnibus <- data.frame(
  test="joint high-standing loss gradient, event times -5 to -2",
  max_abs_t=max(abs(observed_t)),
  deal_wild_p=(
    1+sum(apply(abs(bootstrap_t), 1L, max) >= max(abs(observed_t)))
  )/(nrow(bootstrap_t)+1),
  bootstrap_replications=cfg$inference$bootstrap_replications
)
utils::write.csv(
  pre_omnibus,
  file.path(out_dir, "high_standing_80_pretrend_omnibus.csv"),
  row.names=FALSE
)

# Cohort-preserving ATT entropy tilt for the primary top-quintile population.
# The tilt uses only predetermined variables and retains the full separate-hinge
# functional form.
pre_path <- DBI::dbGetQuery(con, sprintf("
SELECT roster_row_id,
  MAX(CASE WHEN event_time=-5 THEN patent_count END) patent_m5,
  MAX(CASE WHEN event_time=-4 THEN patent_count END) patent_m4,
  MAX(CASE WHEN event_time=-3 THEN patent_count END) patent_m3,
  MAX(CASE WHEN event_time=-2 THEN patent_count END) patent_m2,
  MAX(CASE WHEN event_time=-1 THEN patent_count END) patent_m1
FROM %s WHERE event_time BETWEEN -5 AND -1 GROUP BY roster_row_id
", panel_sql))
ebal_unit <- merge(primary_unit, pre_path, by="roster_row_id", sort=FALSE)
ebal_unit$bal_loss <- pmax(ebal_unit$relative_standing_loss_10pp, 0)
ebal_unit$bal_gain <- pmax(-ebal_unit$relative_standing_loss_10pp, 0)
ebal_unit$bal_standing <- ebal_unit$focal_standing_pct
ebal_unit$bal_logprod <- ebal_unit$log_patent_count_5y
ebal_unit$bal_trajectory <- ebal_unit$patent_trajectory
ebal_unit$bal_pre_ref <- ebal_unit$patent_pre_ref
ebal_unit$bal_age <- log1p(ebal_unit$career_age)
ebal_unit$bal_tenure <- log1p(ebal_unit$focal_group_tenure)
ebal_unit$bal_exclusivity <- ebal_unit$focal_group_exclusivity
ebal_unit$bal_team_any <- ebal_unit$team_any
ebal_unit$bal_team_intensity <- ifelse(
  ebal_unit$team_any == 1, ebal_unit$persistent_patent_share, 0
)
ebal_unit$bal_focal_size <- log1p(ebal_unit$focal_inventors)
ebal_unit$bal_added_size <- log1p(pmax(
  ebal_unit$combined_inventors-ebal_unit$focal_inventors, 0
))
for (k in 5:2) {
  ebal_unit[[paste0("bal_dm", k)]] <-
    ebal_unit[[paste0("patent_m", k)]]-ebal_unit$patent_m1
}
rebalance_vars <- c(
  "bal_loss", "bal_gain", "bal_standing", "bal_logprod",
  "bal_trajectory", "bal_pre_ref", "bal_age", "bal_tenure",
  "bal_exclusivity", "bal_team_any", "bal_team_intensity",
  "bal_focal_size", "bal_added_size", paste0("bal_dm", 5:2)
)
q <- ebal_unit
use <- character()
for (variable in rebalance_vars) {
  s <- stats::sd(q[[variable]])
  if (is.finite(s) && s > 1e-10) {
    q[[variable]] <- (q[[variable]]-mean(q[[variable]]))/s
    use <- c(use, variable)
  }
}
ebal_fit <- WeightIt::weightit(
  stats::as.formula(paste(
    "treated ~ factor(cohort) +", paste(use, collapse=" + ")
  )),
  data=q, method="ebal", estimand="ATT", moments=1,
  s.weights=q$raw_weight, maxit=5000
)
ebal_unit$raw_weight_aug <- ifelse(
  ebal_unit$treated == 1,
  ebal_unit$raw_weight,
  ebal_unit$raw_weight*ebal_fit$weights
)
ebal_unit$raw_weight_aug[ebal_unit$treated == 0] <-
  ebal_unit$raw_weight_aug[ebal_unit$treated == 0]*
  sum(ebal_unit$raw_weight_aug[ebal_unit$treated == 1])/
  sum(ebal_unit$raw_weight_aug[ebal_unit$treated == 0])
if (any(!is.finite(ebal_unit$raw_weight_aug)) ||
    any(ebal_unit$raw_weight_aug <= 0)) {
  stop("Invalid high-standing entropy weights")
}
primary_ebal <- ebal_unit
primary_ebal$raw_weight <- primary_ebal$raw_weight_aug
primary_ebal_prepared <- prepare(primary_ebal)
ebal_result <- fit_one(
  primary_ebal_prepared, "high_standing_80_entropy_balanced", 80,
  "all changes; separate hinges; entropy-balanced controls"
)$result
results <- rbind(results, ebal_result)
utils::write.csv(
  results, file.path(out_dir, "high_standing_loss_results.csv"),
  row.names=FALSE
)

ebal_balance_rows <- lapply(rebalance_vars, function(variable) {
  z <- primary_ebal_prepared
  tr <- z$treated == 1
  mt <- wmean(z[[variable]][tr], z$analysis_weight[tr])
  mc <- wmean(z[[variable]][!tr], z$analysis_weight[!tr])
  st <- wsd(z[[variable]][tr], z$analysis_weight[tr])
  sc <- wsd(z[[variable]][!tr], z$analysis_weight[!tr])
  data.frame(
    variable=variable, smd=(mt-mc)/sqrt((st^2+sc^2)/2)
  )
})
ebal_balance <- do.call(rbind, ebal_balance_rows)
utils::write.csv(
  ebal_balance,
  file.path(out_dir, "high_standing_80_entropy_balance.csv"),
  row.names=FALSE
)
weight_diagnostics <- do.call(rbind, lapply(
  sort(unique(primary_ebal$cohort)), function(g) {
    z <- primary_ebal[primary_ebal$cohort == g & primary_ebal$treated == 0, ]
    data.frame(
      cohort=g, control_n=nrow(z),
      control_ess=sum(z$raw_weight)^2/sum(z$raw_weight^2),
      max_control_share=max(z$raw_weight)/sum(z$raw_weight)
    )
  }
))
utils::write.csv(
  weight_diagnostics,
  file.path(out_dir, "high_standing_80_entropy_weight_diagnostics.csv"),
  row.names=FALSE
)

ebal_pre_results <- list()
ebal_pre_scores <- list()
for (event_time in cfg$estimand$pretrend_event_times) {
  pre_y <- DBI::dbGetQuery(con, sprintf("
    SELECT p.roster_row_id,
           CAST(p.patent_count-b.patent_count AS DOUBLE) d_pre
    FROM %1$s p JOIN %1$s b USING (roster_row_id)
    WHERE p.event_time=%2$d AND b.event_time=%3$d
  ", panel_sql, event_time, cfg$estimand$reference_event_time))
  z <- merge(primary_ebal, pre_y, by="roster_row_id", sort=FALSE)
  z <- prepare(z)
  fit <- lmv2_vr_fit_wls(z, "d_pre", precision_terms)
  covariance <- lmv2_vr_model_covariance(fit)
  ans <- lmv2_vr_linear_result(
    fit, covariance, c(tx_loss_hinge=1), deal_multipliers,
    paste0("event time ", event_time), cfg
  )
  ans$event_time <- event_time
  ebal_pre_results[[as.character(event_time)]] <- ans
  score <- covariance$S_deal[, "tx_loss_hinge"]
  aligned <- setNames(rep(0, length(deal_levels)), as.character(deal_levels))
  aligned[names(score)] <- score
  ebal_pre_scores[[as.character(event_time)]] <- aligned/ans$deal_se
}
ebal_pre_results <- do.call(rbind, ebal_pre_results)
utils::write.csv(
  ebal_pre_results,
  file.path(out_dir, "high_standing_80_entropy_pretrend_results.csv"),
  row.names=FALSE
)
ebal_bootstrap_t <- deal_multipliers %*% do.call(cbind, ebal_pre_scores)
ebal_observed_t <- ebal_pre_results$estimate/ebal_pre_results$deal_se
ebal_pre_omnibus <- data.frame(
  test="joint entropy-balanced high-standing loss gradient, t=-5 to -2",
  max_abs_t=max(abs(ebal_observed_t)),
  deal_wild_p=(
    1+sum(apply(abs(ebal_bootstrap_t), 1L, max) >=
      max(abs(ebal_observed_t)))
  )/(nrow(ebal_bootstrap_t)+1),
  bootstrap_replications=cfg$inference$bootstrap_replications
)
utils::write.csv(
  ebal_pre_omnibus,
  file.path(out_dir, "high_standing_80_entropy_pretrend_omnibus.csv"),
  row.names=FALSE
)

# Match the thesis reporting convention: the primary coefficient is an average
# annual effect over t=+1,...,+5; its five-times multiple is the cumulative
# five-year effect. Rescaling changes units, not t statistics or p-values.
cumulative_results <- results
scale_columns <- intersect(
  c(
    "estimate", "deal_se", "two_way_se", "ci_low", "ci_high",
    "governing_se", "mde_80"
  ),
  names(cumulative_results)
)
cumulative_results[scale_columns] <-
  cumulative_results[scale_columns]*5
cumulative_results$effect_scale <-
  "five-year cumulative patents per 10pp predicted standing loss"
cumulative_results$source_scale <-
  "five times the average annual t=+1,...,+5 coefficient"
utils::write.csv(
  cumulative_results,
  file.path(out_dir, "high_standing_loss_five_year_results.csv"),
  row.names=FALSE
)

manifest <- data.frame(
  status="exploratory_theory_aligned_high_standing_loss",
  moderator_sha256=digest::digest(file=moderator_path, algo="sha256"),
  unit_sha256=digest::digest(file=cfg$inputs$vr_unit_analysis, algo="sha256"),
  thresholds=paste(thresholds, collapse=";"),
  primary_threshold=80,
  result_rows=nrow(results), balance_rows=nrow(balance),
  entropy_max_abs_smd=max(abs(ebal_balance$smd)),
  entropy_pretrend_p=ebal_pre_omnibus$deal_wild_p
)
utils::write.csv(
  manifest, file.path(out_dir, "high_standing_loss_manifest.csv"),
  row.names=FALSE
)
message("High-standing relative-loss analysis complete.")

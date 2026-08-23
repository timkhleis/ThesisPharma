# ============================================================================
# 65c_estimate_lmv2_relative_standing.R -- frozen outcome estimation
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest", "MASS")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))
source(file.path(BASE, "R", "65a_lmv2_relative_standing_config.R"))

cfg <- LMV2_RELSTAND
out_dir <- cfg$output_dir
moderator_path <- file.path(out_dir, "relative_standing_moderators.parquet")
build_manifest_path <- file.path(
  out_dir, "relative_standing_build_manifest.csv"
)
required <- c(
  moderator_path, build_manifest_path, cfg$inputs$vr_unit_analysis,
  cfg$inputs$vr_power_manifest
)
if (!all(file.exists(required))) {
  stop("Run 65b and the certified VR package before estimation")
}
build_manifest <- utils::read.csv(
  build_manifest_path, stringsAsFactors = FALSE
)
vr_manifest <- utils::read.csv(
  cfg$inputs$vr_power_manifest, stringsAsFactors = FALSE
)
if (nrow(build_manifest) != 1L ||
    build_manifest$design_hash != lmv2_relstand_hash() ||
    build_manifest$relative_standing_sha256 != digest::digest(
      file = moderator_path, algo = "sha256"
    ) ||
    build_manifest$outcome_estimates_written != 0L ||
    nrow(vr_manifest) != 1L || !isTRUE(vr_manifest$aggregate_att_reproduction_pass) ||
    vr_manifest$unit_analysis_sha256 != digest::digest(
      file = cfg$inputs$vr_unit_analysis, algo = "sha256"
    )) {
  stop("Relative-standing or inherited VR artifact is stale")
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf("PRAGMA threads=%d", cfg$execution$threads))
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", cfg$execution$memory_limit
))

unit <- DBI::dbGetQuery(con, sprintf("
SELECT
  v.*, r.focal_patents_5y, r.focal_inventors,
  r.focal_standing_pct, r.combined_inventors,
  r.combined_standing_pct, r.relative_standing_loss_pp,
  r.relative_standing_loss_10pp, r.positive_standing_loss,
  r.productive_3plus, r.kapoor_top20, r.standing_eligibility
FROM read_parquet(%s) v
JOIN read_parquet(%s) r USING (roster_row_id)
WHERE r.standing_eligibility='eligible'
", DBI::dbQuoteString(
  con, normalizePath(cfg$inputs$vr_unit_analysis,
                     winslash = "/", mustWork = TRUE)
), DBI::dbQuoteString(
  con, normalizePath(moderator_path, winslash = "/", mustWork = TRUE)
)))
unit$treated <- as.numeric(unit$treated)
if (!nrow(unit) || anyDuplicated(unit$roster_row_id)) {
  stop("Eligible unit analysis is empty or duplicated")
}

wmean <- function(x, w) sum(x * w) / sum(w)
wsd <- function(x, w) {
  m <- wmean(x, w)
  sqrt(sum(w * (x - m)^2) / sum(w))
}

prepare <- function(x) {
  z <- lmv2_vr_analysis_weights(x)
  tr <- z$treated == 1
  loss_mean <- wmean(
    z$relative_standing_loss_10pp[tr], z$analysis_weight[tr]
  )
  prod_mean <- wmean(z$log_patent_count_5y[tr], z$analysis_weight[tr])
  prod_sd <- wsd(z$log_patent_count_5y[tr], z$analysis_weight[tr])
  age_raw <- log1p(z$career_age)
  age_mean <- wmean(age_raw[tr], z$analysis_weight[tr])
  age_sd <- wsd(age_raw[tr], z$analysis_weight[tr])
  team_mean <- wmean(z$team_any[tr], z$analysis_weight[tr])
  positive_team <- tr & z$team_any == 1
  team_intensity_mean <- if (any(positive_team)) {
    wmean(
      z$persistent_patent_share[positive_team],
      z$analysis_weight[positive_team]
    )
  } else 0
  positive_loss_mean <- wmean(
    z$positive_standing_loss[tr], z$analysis_weight[tr]
  )
  star_rows <- tr & !is.na(z$kapoor_top20)
  star_mean <- if (any(star_rows)) {
    wmean(z$kapoor_top20[star_rows], z$analysis_weight[star_rows])
  } else NA_real_

  z$loss_c <- z$relative_standing_loss_10pp - loss_mean
  z$prod_z <- (z$log_patent_count_5y - prod_mean) / prod_sd
  z$age_z <- (age_raw - age_mean) / age_sd
  z$team_any_c <- z$team_any - team_mean
  z$team_intensity <- ifelse(
    z$team_any == 1,
    z$persistent_patent_share - team_intensity_mean, 0
  )
  z$positive_loss_c <- z$positive_standing_loss - positive_loss_mean
  z$star_c <- z$kapoor_top20 - star_mean
  z$tx_loss <- z$treated * z$loss_c
  z$tx_prod <- z$treated * z$prod_z
  z$tx_positive_loss <- z$treated * z$positive_loss_c
  z$tx_star <- z$treated * z$star_c
  list(
    data = z,
    centers = c(
      loss_mean = loss_mean, prod_mean = prod_mean, prod_sd = prod_sd,
      positive_loss_mean = positive_loss_mean, star_mean = star_mean
    )
  )
}

common_rhs <- c(
  "factor(cohort)", "treated", "loss_c", "prod_z", "age_z",
  "team_any_c", "team_intensity"
)

deal_levels <- sort(unique(unit$deal_id))
deal_multipliers <- lmv2_vr_webb_multipliers(deal_levels, cfg)
t0 <- Sys.time()

fit_result <- function(
    data, outcome, rhs, term, model, contrast_label,
    sample = "eligible_1993_2010") {
  fit <- lmv2_vr_fit_wls(data, outcome, rhs)
  covariance <- lmv2_vr_model_covariance(fit)
  ans <- lmv2_vr_linear_result(
    fit, covariance, setNames(1, term), deal_multipliers,
    contrast_label, cfg
  )
  ans$model <- model
  outcome_match <- match(outcome, cfg$estimand$outcomes)
  ans$outcome <- if (is.na(outcome_match)) {
    if (outcome == "d_pre") "patent_count" else outcome
  } else {
    names(cfg$estimand$outcomes)[outcome_match]
  }
  ans$sample <- sample
  ans$term <- term
  ans$n_observations <- fit$n
  ans$nominal_deals <- length(unique(fit$deal))
  threshold <- unname(cfg$estimand$meaningful_effect[[ans$outcome]])
  ans$meaningful_threshold <- threshold
  ans$mde <- (
    ans$governing_critical + stats::qnorm(cfg$inference$target_power)
  ) * ans$governing_se
  list(result = ans, fit = fit, covariance = covariance)
}

prepared <- prepare(unit)
z <- prepared$data
results <- list()
fits <- list()
k <- 0L

for (outcome in names(cfg$estimand$outcomes)) {
  outcome_col <- unname(cfg$estimand$outcomes[[outcome]])

  k <- k + 1L
  primary <- fit_result(
    z, outcome_col, c(common_rhs, "tx_loss"), "tx_loss",
    "standing_primary", "ATT gradient per 10pp predicted standing loss"
  )
  results[[k]] <- primary$result
  fits[[paste("primary", outcome, sep = "__")]] <- primary

  k <- k + 1L
  horse <- fit_result(
    z, outcome_col, c(common_rhs, "tx_loss", "tx_prod"), "tx_loss",
    "standing_productivity_horse_race",
    "standing-loss gradient conditional on productivity gradient"
  )
  results[[k]] <- horse$result
  fits[[paste("horse_loss", outcome, sep = "__")]] <- horse

  k <- k + 1L
  horse_prod <- fit_result(
    z, outcome_col, c(common_rhs, "tx_loss", "tx_prod"), "tx_prod",
    "standing_productivity_horse_race",
    "absolute-productivity gradient conditional on standing loss"
  )
  results[[k]] <- horse_prod$result

  prod3 <- prepare(unit[unit$productive_3plus == 1, , drop = FALSE])$data
  k <- k + 1L
  focused <- fit_result(
    prod3, outcome_col,
    c(common_rhs, "positive_loss_c", "tx_loss", "tx_prod",
      "tx_positive_loss"),
    "tx_positive_loss", "productive_3plus_positive_loss",
    "positive loss minus no loss/gain among 3+ patent inventors",
    "eligible_productive_3plus"
  )
  results[[k]] <- focused$result

  star_unit <- unit[!is.na(unit$kapoor_top20), , drop = FALSE]
  star <- prepare(star_unit)$data
  k <- k + 1L
  kapoor <- fit_result(
    star, outcome_col, c(common_rhs, "star_c", "tx_star"), "tx_star",
    "kapoor_top20_sensitivity", "top-20 minus other inventors",
    "eligible_focal_groups_nge5"
  )
  results[[k]] <- kapoor$result
}
results <- do.call(rbind, results)

primary_rows <- results$model == "standing_primary"
results$holm_adjusted_governing_p <- NA_real_
results$holm_adjusted_governing_p[primary_rows] <- stats::p.adjust(
  results$governing_p[primary_rows], method = "holm"
)
utils::write.csv(
  results, file.path(out_dir, "relative_standing_results.csv"),
  row.names = FALSE
)

# Eligible-sample headline, using the same cohort-standardized weights.
headline_rows <- list()
for (outcome in names(cfg$estimand$outcomes)) {
  outcome_col <- unname(cfg$estimand$outcomes[[outcome]])
  h <- fit_result(
    z, outcome_col, c("factor(cohort)", "treated"), "treated",
    "eligible_sample_headline", "eligible-sample ATT"
  )$result
  headline_rows[[outcome]] <- h
}
headline <- do.call(rbind, headline_rows)
headline_source <- utils::read.csv(file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment",
  "P6_ESTIMATION_PRIMARY", "p6_headline_post_att.csv"
), stringsAsFactors = FALSE)
headline_source <- headline_source[
  headline_source$sample == "full_1993_2010" &
    headline_source$summary == "average_annual_t1_to_t5" &
    headline_source$governing %in% c(TRUE, "TRUE") &
    headline_source$outcome %in% names(cfg$estimand$outcomes),
  c("outcome", "estimate")
]
names(headline_source)[2] <- "full_sample_estimate"
headline <- merge(headline, headline_source, by = "outcome", all.x = TRUE)
headline$eligible_minus_full <- headline$estimate - headline$full_sample_estimate
utils::write.csv(
  headline, file.path(out_dir, "relative_standing_headline_comparison.csv"),
  row.names = FALSE
)

weighted_smd <- function(x, variable) {
  rows <- lapply(0:1, function(a) {
    q <- x[x$treated == a, , drop = FALSE]
    v <- q[[variable]]
    w <- q$analysis_weight
    m <- wmean(v, w)
    data.frame(arm = a, mean = m, variance = wmean((v - m)^2, w))
  })
  rows <- do.call(rbind, rows)
  denom <- sqrt(mean(rows$variance))
  if (denom > 0) diff(rows$mean) / denom else 0
}
balance_variables <- c(
  "relative_standing_loss_10pp", "log_patent_count_5y",
  "patent_trajectory", "career_age", "focal_group_tenure",
  "focal_group_exclusivity"
)
balance <- data.frame(
  sample = "eligible_1993_2010",
  variable = balance_variables,
  smd = vapply(balance_variables, function(v) weighted_smd(z, v), numeric(1)),
  stringsAsFactors = FALSE
)
utils::write.csv(
  balance, file.path(out_dir, "relative_standing_balance.csv"),
  row.names = FALSE
)

subgroup_gate <- function(x, group_var, sample_label) {
  x <- prepare(x)$data
  groups <- sort(unique(x[[group_var]]))
  rows <- lapply(groups, function(g) {
    q <- x[x[[group_var]] == g, , drop = FALSE]
    tr <- q[q$treated == 1, , drop = FALSE]
    mass <- stats::aggregate(
      analysis_weight ~ deal_id, data = tr, FUN = sum
    )
    shares <- mass$analysis_weight / sum(mass$analysis_weight)
    covariates <- c(
      "log_patent_count_5y", "patent_trajectory", "career_age",
      "focal_group_tenure", "focal_group_exclusivity"
    )
    smd <- vapply(covariates, function(v) weighted_smd(q, v), numeric(1))
    data.frame(
      sample = sample_label, group = as.character(g),
      treated_inventors = nrow(tr), nominal_deals = nrow(mass),
      effective_deals = 1 / sum(shares^2),
      largest_deal_share = max(shares), max_abs_smd = max(abs(smd)),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out$gate_pass <-
    out$treated_inventors >= cfg$diagnostics$minimum_treated_inventors &
    out$effective_deals >= cfg$diagnostics$minimum_effective_treated_deals &
    out$largest_deal_share <= cfg$diagnostics$maximum_treated_deal_share &
    out$max_abs_smd <= cfg$diagnostics$max_abs_smd
  out
}
gates <- rbind(
  subgroup_gate(
    unit[unit$productive_3plus == 1, , drop = FALSE],
    "positive_standing_loss", "productive_3plus"
  ),
  subgroup_gate(
    unit[!is.na(unit$kapoor_top20), , drop = FALSE],
    "kapoor_top20", "kapoor_focal_groups_nge5"
  )
)
utils::write.csv(
  gates, file.path(out_dir, "relative_standing_subgroup_gates.csv"),
  row.names = FALSE
)

# Pre-period standing gradients at t=-5,...,-2, all relative to t=-1.
# These years enter the five-year moderator, so this is an overlapping-window
# trajectory diagnostic rather than an independent held-out pretrend test.
panel_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
if (length(panel_files) != length(cfg$estimand$cohorts)) {
  stop("Certified event-panel shard set is incomplete")
}
panel_sql <- lmv2_panel_sql(panel_files)
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
  q <- merge(unit, pre_y, by = "roster_row_id", sort = FALSE)
  q <- prepare(q)$data
  f <- fit_result(
    q, "d_pre", c(common_rhs, "tx_loss"), "tx_loss",
    "standing_pretrend", paste0("event time ", event_time),
    "eligible_1993_2010"
  )
  ans <- f$result
  ans$event_time <- event_time
  pre_results[[as.character(event_time)]] <- ans
  score <- f$covariance$S_deal[, "tx_loss"]
  aligned <- setNames(rep(0, length(deal_levels)), as.character(deal_levels))
  aligned[names(score)] <- score
  pre_scores[[as.character(event_time)]] <- aligned / ans$deal_se
}
pre_results <- do.call(rbind, pre_results)
utils::write.csv(
  pre_results, file.path(out_dir, "relative_standing_pretrend_results.csv"),
  row.names = FALSE
)
score_matrix <- do.call(cbind, pre_scores)
bootstrap_t <- deal_multipliers %*% score_matrix
observed_t <- pre_results$estimate / pre_results$deal_se
joint_p <- (
  1 + sum(apply(abs(bootstrap_t), 1L, max) >= max(abs(observed_t)))
) / (nrow(bootstrap_t) + 1)
pre_omnibus <- data.frame(
  test = paste(
    "joint standing-gradient pre-period trajectory diagnostic,",
    "event times -5 to -2"
  ),
  max_abs_t = max(abs(observed_t)), deal_wild_p = joint_p,
  bootstrap_replications = cfg$inference$bootstrap_replications,
  stringsAsFactors = FALSE
)
utils::write.csv(
  pre_omnibus, file.path(out_dir, "relative_standing_pretrend_omnibus.csv"),
  row.names = FALSE
)

manifest <- data.frame(
  design_hash = lmv2_relstand_hash(),
  moderator_sha256 = digest::digest(file = moderator_path, algo = "sha256"),
  vr_unit_analysis_sha256 = digest::digest(
    file = cfg$inputs$vr_unit_analysis, algo = "sha256"
  ),
  source_sha256 = digest::digest(
    file = file.path(BASE, "R", "65c_estimate_lmv2_relative_standing.R"),
    algo = "sha256"
  ),
  primary_result_rows = sum(primary_rows),
  eligible_unit_rows = nrow(unit),
  eligible_treated_inventors = sum(unit$treated == 1),
  eligible_deals = length(deal_levels),
  bootstrap_replications = cfg$inference$bootstrap_replications,
  runtime_minutes = as.numeric(difftime(Sys.time(), t0, units = "mins")),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "relative_standing_estimation_manifest.csv"),
  row.names = FALSE
)
message("Relative-standing estimation complete: ", nrow(results),
        " frozen result rows.")

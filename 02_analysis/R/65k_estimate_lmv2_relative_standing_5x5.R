# ============================================================================
# 65k_estimate_lmv2_relative_standing_5x5.R
# Nested relative-standing predictions on the conventional five-by-five DiD.
# Implements the agreed cohort-preserving entropy tilt for the standing-loss
# prediction and writes separate full-cohort and retained-inventor results.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest", "MASS", "WeightIt")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))
source(file.path(BASE, "R", "33a_lmv2_stayer_heterogeneity_config.R"))
source(file.path(BASE, "R", "65a_lmv2_relative_standing_config.R"))

cfg <- LMV2_RELSTAND
out_dir <- file.path(cfg$output_dir, "nested_5x5")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

moderator_path <- file.path(
  cfg$output_dir, "relative_standing_moderators.parquet"
)
sample_paths <- c(
  full_cohort = cfg$inputs$vr_unit_analysis,
  initially_retained = file.path(
    LMV2_STAYER_HET$output_dir, "stayer_unit_analysis.parquet"
  )
)
required <- c(moderator_path, sample_paths)
if (!all(file.exists(required))) {
  stop("Missing nested relative-standing input: ",
       paste(required[!file.exists(required)], collapse = ", "))
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf("PRAGMA threads=%d", cfg$execution$threads))
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", cfg$execution$memory_limit
))

wmean <- function(x, w) sum(x * w) / sum(w)
wsd <- function(x, w) {
  m <- wmean(x, w)
  sqrt(sum(w * (x - m)^2) / sum(w))
}

load_sample <- function(path) {
  x <- DBI::dbGetQuery(con, sprintf("
    SELECT
      u.*, m.focal_standing_pct, m.combined_standing_pct,
      m.relative_standing_loss_pp, m.relative_standing_loss_10pp,
      m.focal_inventors, m.combined_inventors, m.kapoor_top20
    FROM read_parquet(%s) u
    JOIN read_parquet(%s) m USING (roster_row_id)
    WHERE m.standing_eligibility='eligible'
  ", DBI::dbQuoteString(con, normalizePath(
    path, winslash = "/", mustWork = TRUE
  )), DBI::dbQuoteString(con, normalizePath(
    moderator_path, winslash = "/", mustWork = TRUE
  ))))
  x$treated <- as.numeric(x$treated)
  if (!nrow(x) || anyDuplicated(x$roster_row_id)) {
    stop("Nested relative-standing sample is empty or duplicated")
  }
  x
}

prepare <- function(x) {
  z <- lmv2_vr_analysis_weights(x)
  tr <- z$treated == 1
  center <- function(v) v - wmean(v[tr], z$analysis_weight[tr])
  standardize <- function(v) {
    s <- wsd(v[tr], z$analysis_weight[tr])
    if (!is.finite(s) || s <= 1e-12) stop("Degenerate moderator scale")
    (v - wmean(v[tr], z$analysis_weight[tr])) / s
  }

  z$star_c <- center(z$kapoor_top20)
  z$tx_star <- z$treated * z$star_c
  z$loss_hinge_c <- center(pmax(z$relative_standing_loss_10pp, 0))
  z$gain_hinge_c <- center(pmax(-z$relative_standing_loss_10pp, 0))
  z$tx_loss_hinge <- z$treated * z$loss_hinge_c
  z$tx_gain_hinge <- z$treated * z$gain_hinge_c
  z$standing_z <- standardize(z$focal_standing_pct)
  z$prod_z <- standardize(z$log_patent_count_5y)
  z$trajectory_z <- standardize(z$patent_trajectory)
  z$age_z <- standardize(log1p(z$career_age))
  z$tenure_z <- standardize(log1p(z$focal_group_tenure))
  z$exclusivity_z <- standardize(z$focal_group_exclusivity)
  z$team_any_c <- center(z$team_any)
  positive_team <- tr & z$team_any == 1
  team_mean <- if (any(positive_team)) {
    wmean(
      z$persistent_patent_share[positive_team],
      z$analysis_weight[positive_team]
    )
  } else 0
  z$team_intensity <- ifelse(
    z$team_any == 1, z$persistent_patent_share - team_mean, 0
  )
  z$focal_size_z <- standardize(log1p(z$focal_inventors))
  z$added_size_z <- standardize(log1p(pmax(
    z$combined_inventors - z$focal_inventors, 0
  )))
  z$pre_ref_z <- standardize(z$patent_pre_ref)
  z$pre_avg_z <- standardize(z$patent_pre_avg)
  z$prod_bin <- factor(
    ifelse(z$patent_count_5y >= 6, "6+", as.character(z$patent_count_5y)),
    levels = c("1", "2", "3", "4", "5", "6+")
  )
  z
}

nuisance_terms <- c(
  "factor(prod_bin)", "treated:factor(prod_bin)",
  "trajectory_z", "treated:trajectory_z", "age_z", "treated:age_z",
  "tenure_z", "treated:tenure_z", "exclusivity_z",
  "treated:exclusivity_z", "team_any_c", "treated:team_any_c",
  "team_intensity", "treated:team_intensity", "focal_size_z",
  "treated:focal_size_z", "added_size_z", "treated:added_size_z",
  "pre_ref_z", "treated:pre_ref_z", "pre_avg_z", "treated:pre_avg_z"
)

star_rhs <- c(
  "factor(cohort)", "treated", "prod_z", "age_z", "team_any_c",
  "team_intensity", "star_c", "tx_star"
)
loss_rhs <- c(
  "factor(cohort)", "treated", "loss_hinge_c", "gain_hinge_c",
  "tx_loss_hinge", "tx_gain_hinge", "standing_z",
  "treated:standing_z", nuisance_terms
)
outcomes <- c(
  patent_count = "d_patent_5x5",
  active_patenting = "d_active_5x5"
)

panel_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$", full.names = TRUE
))
if (!length(panel_files)) stop("No certified LMv2 panel shards found")
panel_sql <- lmv2_panel_sql(panel_files)
pre_path <- DBI::dbGetQuery(con, sprintf("
  SELECT roster_row_id,
    MAX(CASE WHEN event_time=-5 THEN patent_count END) patent_m5,
    MAX(CASE WHEN event_time=-4 THEN patent_count END) patent_m4,
    MAX(CASE WHEN event_time=-3 THEN patent_count END) patent_m3,
    MAX(CASE WHEN event_time=-2 THEN patent_count END) patent_m2,
    MAX(CASE WHEN event_time=-1 THEN patent_count END) patent_m1
  FROM %s
  WHERE event_time BETWEEN -5 AND -1
  GROUP BY roster_row_id
", panel_sql))

entropy_tilt <- function(x, sample_name) {
  z <- merge(x, pre_path, by = "roster_row_id", sort = FALSE)
  if (nrow(z) != nrow(x) || anyDuplicated(z$roster_row_id)) {
    stop("Incomplete pre-deal path for entropy tilt in ", sample_name)
  }
  z$bal_loss <- pmax(z$relative_standing_loss_10pp, 0)
  z$bal_gain <- pmax(-z$relative_standing_loss_10pp, 0)
  z$bal_standing <- z$focal_standing_pct
  z$bal_logprod <- z$log_patent_count_5y
  z$bal_trajectory <- z$patent_trajectory
  z$bal_pre_ref <- z$patent_pre_ref
  z$bal_age <- log1p(z$career_age)
  z$bal_tenure <- log1p(z$focal_group_tenure)
  z$bal_exclusivity <- z$focal_group_exclusivity
  z$bal_team_any <- z$team_any
  z$bal_team_intensity <- ifelse(
    z$team_any == 1, z$persistent_patent_share, 0
  )
  z$bal_focal_size <- log1p(z$focal_inventors)
  z$bal_added_size <- log1p(pmax(
    z$combined_inventors - z$focal_inventors, 0
  ))
  for (k in 5:2) {
    z[[paste0("bal_dm", k)]] <-
      z[[paste0("patent_m", k)]] - z$patent_m1
  }
  balance_vars <- c(
    "bal_loss", "bal_gain", "bal_standing", "bal_logprod",
    "bal_trajectory", "bal_pre_ref", "bal_age", "bal_tenure",
    "bal_exclusivity", "bal_team_any", "bal_team_intensity",
    "bal_focal_size", "bal_added_size", paste0("bal_dm", 5:2)
  )
  q <- z
  use <- character()
  for (variable in balance_vars) {
    s <- stats::sd(q[[variable]])
    if (is.finite(s) && s > 1e-10) {
      q[[variable]] <- (q[[variable]] - mean(q[[variable]])) / s
      use <- c(use, variable)
    }
  }
  fit <- WeightIt::weightit(
    stats::as.formula(paste(
      "treated ~ factor(cohort) +", paste(use, collapse = " + ")
    )),
    data = q, method = "ebal", estimand = "ATT", moments = 1,
    s.weights = q$raw_weight, maxit = 5000
  )
  z$raw_weight_aug <- ifelse(
    z$treated == 1, z$raw_weight, z$raw_weight * fit$weights
  )
  treated_mass <- sum(z$raw_weight_aug[z$treated == 1])
  control_mass <- sum(z$raw_weight_aug[z$treated == 0])
  z$raw_weight_aug[z$treated == 0] <-
    z$raw_weight_aug[z$treated == 0] * treated_mass / control_mass
  if (any(!is.finite(z$raw_weight_aug)) ||
      any(z$raw_weight_aug <= 0)) {
    stop("Invalid entropy weights for ", sample_name)
  }
  z$raw_weight <- z$raw_weight_aug
  prepared <- prepare(z)
  balance <- do.call(rbind, lapply(balance_vars, function(variable) {
    tr <- prepared$treated == 1
    mt <- wmean(prepared[[variable]][tr], prepared$analysis_weight[tr])
    mc <- wmean(prepared[[variable]][!tr], prepared$analysis_weight[!tr])
    st <- wsd(prepared[[variable]][tr], prepared$analysis_weight[tr])
    sc <- wsd(prepared[[variable]][!tr], prepared$analysis_weight[!tr])
    denom <- sqrt((st^2 + sc^2) / 2)
    data.frame(
      sample = sample_name, variable = variable,
      smd = if (is.finite(denom) && denom > 0) (mt - mc) / denom else 0,
      stringsAsFactors = FALSE
    )
  }))
  weight_diagnostics <- do.call(rbind, lapply(
    sort(unique(z$cohort)), function(g) {
      controls <- z[z$cohort == g & z$treated == 0, , drop = FALSE]
      data.frame(
        sample = sample_name, cohort = g, control_n = nrow(controls),
        control_ess = sum(controls$raw_weight)^2 /
          sum(controls$raw_weight^2),
        max_control_share = max(controls$raw_weight) /
          sum(controls$raw_weight),
        stringsAsFactors = FALSE
      )
    }
  ))
  list(data = prepared, balance = balance, weights = weight_diagnostics)
}

fit_contrast <- function(
    data, outcome, rhs, term, label, multipliers, sample, prediction,
    specification, preferred) {
  fit <- lmv2_vr_fit_wls(data, outcome, rhs)
  covariance <- lmv2_vr_model_covariance(fit)
  ans <- lmv2_vr_linear_result(
    fit, covariance, setNames(1, term), multipliers, label, cfg
  )
  ans$sample <- sample
  ans$prediction <- prediction
  ans$specification <- specification
  ans$preferred <- preferred
  ans$reporting_role <- if (sample == "full_cohort") {
    "primary full-cohort heterogeneity estimate"
  } else {
    "descriptive only; initially retained is post-treatment selected"
  }
  ans$outcome <- names(outcomes)[match(outcome, outcomes)]
  ans$window <- "five_post_minus_five_pre"
  ans$effect_scale <- if (prediction == "star_vulnerability") {
    "top-20 target inventors minus other target inventors"
  } else {
    "per 10-percentage-point predicted standing loss among top-20 inventors"
  }
  ans$n_observations <- fit$n
  ans$treated_inventors <- sum(data$treated == 1)
  ans$treated_deals <- length(unique(data$deal_id[data$treated == 1]))
  ans$treated_loss_inventors <- if (prediction == "standing_loss_among_stars") {
    sum(data$treated == 1 & data$relative_standing_loss_pp > 0)
  } else NA_integer_
  ans$treated_loss_deals <- if (prediction == "standing_loss_among_stars") {
    length(unique(data$deal_id[
      data$treated == 1 & data$relative_standing_loss_pp > 0
    ]))
  } else NA_integer_
  ans
}

weighted_smd <- function(x, variable) {
  rows <- lapply(0:1, function(a) {
    q <- x[x$treated == a, , drop = FALSE]
    v <- q[[variable]]
    w <- q$analysis_weight
    m <- wmean(v, w)
    c(mean = m, variance = wmean((v - m)^2, w))
  })
  rows <- do.call(rbind, rows)
  denom <- sqrt(mean(rows[, "variance"]))
  if (is.finite(denom) && denom > 0) {
    (rows[2, "mean"] - rows[1, "mean"]) / denom
  } else 0
}

diagnostic_variables <- c(
  "relative_standing_loss_10pp", "focal_standing_pct",
  "log_patent_count_5y", "patent_trajectory", "career_age",
  "focal_group_tenure", "focal_group_exclusivity", "focal_inventors",
  "combined_inventors"
)

result_rows <- list()
diagnostic_rows <- list()
entropy_balance_rows <- list()
entropy_weight_rows <- list()
star_definition_checks <- logical()
outcome_window_checks <- logical()
index <- 0L
dindex <- 0L

for (sample_name in names(sample_paths)) {
  unit <- load_sample(sample_paths[[sample_name]])
  unit <- unit[!is.na(unit$kapoor_top20), , drop = FALSE]
  if (!nrow(unit) || any(unit$focal_inventors < 5)) {
    stop("Top-20 eligibility failed for sample ", sample_name)
  }
  star_definition_checks[[sample_name]] <- all(
    (unit$focal_standing_pct >= 80) == (unit$kapoor_top20 == 1)
  )
  outcome_window_checks[[sample_name]] <-
    max(abs(
      unit$d_patent_5x5 - (unit$patent_post_avg - unit$patent_pre_avg)
    )) <= 1e-12 &&
    max(abs(
      unit$d_active_5x5 - (unit$active_post_avg - unit$active_pre_avg)
    )) <= 1e-12
  star_data <- prepare(unit)
  high_unit <- unit[unit$focal_standing_pct >= 80, , drop = FALSE]
  high_data <- prepare(high_unit)
  entropy <- entropy_tilt(high_unit, sample_name)
  high_entropy_data <- entropy$data
  entropy_balance_rows[[sample_name]] <- entropy$balance
  entropy_weight_rows[[sample_name]] <- entropy$weights
  multipliers <- lmv2_vr_webb_multipliers(
    sort(unique(unit$deal_id)), cfg
  )

  for (outcome_name in names(outcomes)) {
    index <- index + 1L
    result_rows[[index]] <- fit_contrast(
      star_data, outcomes[[outcome_name]], star_rhs, "tx_star",
      "Top-20 minus other-inventor five-by-five DiD",
      multipliers, sample_name, "star_vulnerability",
      "matched_design_weight", TRUE
    )
    index <- index + 1L
    result_rows[[index]] <- fit_contrast(
      high_data, outcomes[[outcome_name]], loss_rhs, "tx_loss_hinge",
      "Unbalanced loss-side five-by-five DiD gradient among top-20 inventors",
      multipliers, sample_name, "standing_loss_among_stars",
      "matched_design_weight_sensitivity", FALSE
    )
    index <- index + 1L
    result_rows[[index]] <- fit_contrast(
      high_entropy_data, outcomes[[outcome_name]], loss_rhs, "tx_loss_hinge",
      "Entropy-balanced loss-side five-by-five DiD gradient among top-20 inventors",
      multipliers, sample_name, "standing_loss_among_stars",
      "cohort_preserving_entropy_preferred", TRUE
    )
  }

  groups <- list(
    nonstar = star_data[star_data$kapoor_top20 == 0, , drop = FALSE],
    star = star_data[star_data$kapoor_top20 == 1, , drop = FALSE],
    high_standing_loss_unbalanced = high_data,
    high_standing_loss_entropy = high_entropy_data
  )
  for (group_name in names(groups)) {
    q <- groups[[group_name]]
    tr <- q[q$treated == 1, , drop = FALSE]
    deal_mass <- stats::aggregate(
      analysis_weight ~ deal_id, data = tr, FUN = sum
    )
    shares <- deal_mass$analysis_weight / sum(deal_mass$analysis_weight)
    for (variable in diagnostic_variables) {
      dindex <- dindex + 1L
      diagnostic_rows[[dindex]] <- data.frame(
        sample = sample_name, group = group_name, variable = variable,
        smd = weighted_smd(q, variable),
        treated_inventors = nrow(tr),
        treated_deals = nrow(deal_mass),
        effective_treated_deals = 1 / sum(shares^2),
        largest_treated_deal_share = max(shares),
        stringsAsFactors = FALSE
      )
    }
  }
}

results <- do.call(rbind, result_rows)
results$holm_p_within_sample <- NA_real_
preferred_rows <- results$preferred
results$holm_p_within_sample[preferred_rows] <- ave(
  results$governing_p[preferred_rows], results$sample[preferred_rows],
  FUN = function(p) stats::p.adjust(p, method = "holm")
)
results$annual_patent_difference <- ifelse(
  results$outcome == "patent_count", results$estimate, NA_real_
)
results$annual_patent_ci_low <- ifelse(
  results$outcome == "patent_count", results$ci_low, NA_real_
)
results$annual_patent_ci_high <- ifelse(
  results$outcome == "patent_count", results$ci_high, NA_real_
)
results$five_year_cumulative_patents <- ifelse(
  results$outcome == "patent_count", 5 * results$estimate, NA_real_
)
results$five_year_cumulative_ci_low <- ifelse(
  results$outcome == "patent_count", 5 * results$ci_low, NA_real_
)
results$five_year_cumulative_ci_high <- ifelse(
  results$outcome == "patent_count", 5 * results$ci_high, NA_real_
)
results$active_patenting_pp <- ifelse(
  results$outcome == "active_patenting", 100 * results$estimate, NA_real_
)
results$active_patenting_ci_low_pp <- ifelse(
  results$outcome == "active_patenting", 100 * results$ci_low, NA_real_
)
results$active_patenting_ci_high_pp <- ifelse(
  results$outcome == "active_patenting", 100 * results$ci_high, NA_real_
)

diagnostics <- do.call(rbind, diagnostic_rows)
entropy_balance <- do.call(rbind, entropy_balance_rows)
entropy_weights <- do.call(rbind, entropy_weight_rows)
diagnostic_summary <- stats::aggregate(
  abs(smd) ~ sample + group, data = diagnostics, FUN = max
)
names(diagnostic_summary)[3] <- "max_abs_smd"
diagnostic_summary$balance_gate_pass <-
  diagnostic_summary$max_abs_smd <= cfg$diagnostics$max_abs_smd

results$report_in_main <- results$preferred & !(
  results$sample == "initially_retained" &
    results$prediction == "standing_loss_among_stars"
)
reader <- results[results$report_in_main, c(
  "sample", "prediction", "outcome", "specification", "reporting_role",
  "effect_scale", "estimate",
  "ci_low", "ci_high", "governing_p", "holm_p_within_sample",
  "annual_patent_difference", "five_year_cumulative_patents",
  "five_year_cumulative_ci_low", "five_year_cumulative_ci_high",
  "active_patenting_pp", "active_patenting_ci_low_pp",
  "active_patenting_ci_high_pp", "n_observations", "treated_inventors",
  "treated_loss_inventors", "treated_loss_deals", "treated_deals"
)]
retained_standing_loss_appendix <- results[
  results$preferred & results$sample == "initially_retained" &
    results$prediction == "standing_loss_among_stars",
  names(reader), drop = FALSE
]

utils::write.csv(
  results, file.path(out_dir, "relative_standing_5x5_results.csv"),
  row.names = FALSE
)
utils::write.csv(
  reader, file.path(out_dir, "table_relative_standing_5x5.csv"),
  row.names = FALSE
)
utils::write.csv(
  retained_standing_loss_appendix,
  file.path(
    out_dir, "table_relative_standing_5x5_retained_loss_appendix.csv"
  ),
  row.names = FALSE
)
utils::write.csv(
  diagnostics, file.path(out_dir, "relative_standing_5x5_balance.csv"),
  row.names = FALSE
)
utils::write.csv(
  diagnostic_summary,
  file.path(out_dir, "relative_standing_5x5_balance_summary.csv"),
  row.names = FALSE
)
utils::write.csv(
  entropy_balance,
  file.path(out_dir, "relative_standing_5x5_entropy_balance.csv"),
  row.names = FALSE
)
utils::write.csv(
  entropy_weights,
  file.path(out_dir, "relative_standing_5x5_entropy_weight_diagnostics.csv"),
  row.names = FALSE
)

checks <- data.frame(
  check = c(
    "main_table_excludes_retained_standing_loss",
    "retained_standing_loss_is_preserved_in_appendix",
    "raw_results_include_labeled_unbalanced_sensitivity",
    "top_quintile_threshold_matches_stored_star_flag",
    "five_by_five_outcomes_match_post_minus_pre_averages",
    "all_results_use_five_by_five_window",
    "all_estimates_and_intervals_finite",
    "full_cohort_entropy_balance_passes",
    "full_cohort_is_not_retention_selected",
    "retained_results_are_separately_labeled"
  ),
  pass = c(
    nrow(reader) == 6L &&
      !any(reader$sample == "initially_retained" &
           reader$prediction == "standing_loss_among_stars"),
    nrow(retained_standing_loss_appendix) == 2L &&
      all(retained_standing_loss_appendix$sample == "initially_retained") &&
      all(retained_standing_loss_appendix$prediction ==
          "standing_loss_among_stars"),
    nrow(results) == 12L && any(!results$preferred) &&
      all(results$specification[!results$preferred] ==
          "matched_design_weight_sensitivity"),
    all(star_definition_checks),
    all(outcome_window_checks),
    all(results$window == "five_post_minus_five_pre"),
    all(is.finite(results$estimate)) && all(is.finite(results$ci_low)) &&
      all(is.finite(results$ci_high)),
    max(abs(entropy_balance$smd[
      entropy_balance$sample == "full_cohort"
    ])) <= cfg$diagnostics$max_abs_smd,
    any(results$sample == "full_cohort"),
    any(results$sample == "initially_retained")
  ),
  stringsAsFactors = FALSE
)
lmv2_relstand_assert(checks)
utils::write.csv(
  checks, file.path(out_dir, "relative_standing_5x5_certification.csv"),
  row.names = FALSE
)

manifest <- data.frame(
  status = "nested_relative_standing_five_by_five",
  source_sha256 = digest::digest(
    file = file.path(BASE, "R", "65k_estimate_lmv2_relative_standing_5x5.R"),
    algo = "sha256"
  ),
  moderator_sha256 = digest::digest(file = moderator_path, algo = "sha256"),
  full_unit_sha256 = digest::digest(file = sample_paths[["full_cohort"]],
                                    algo = "sha256"),
  retained_unit_sha256 = digest::digest(
    file = sample_paths[["initially_retained"]], algo = "sha256"
  ),
  result_rows = nrow(results),
  reader_rows = nrow(reader),
  retained_standing_loss_appendix_rows =
    nrow(retained_standing_loss_appendix),
  bootstrap_replications = cfg$inference$bootstrap_replications,
  outcome_window = "mean(t=+1,...,+5)-mean(t=-5,...,-1)",
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "relative_standing_5x5_manifest.csv"),
  row.names = FALSE
)

message("Nested five-by-five relative-standing estimates complete: ",
        nrow(results), " result rows.")
